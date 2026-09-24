#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Checks for install.sh and scripts/desktop-shortcut.sh.
#
#   tests/checks.sh
#
# Runs completely in a sandbox: its own HOME, its own config directory, its own desktop
# directory, a fake notify-send and a fake terminal emulator. Nothing outside the sandbox is
# touched, no window is opened, no notification is shown.
#
# Prints one line per check and a summary at the end; exit code 0 when everything passed.

set -u

repo=$(cd -- "$(dirname -- "$0")/.." && pwd)
sandbox=$(mktemp -d "${TMPDIR:-/tmp}/cosmic-files-checks.XXXXXX")
home=$sandbox/home
desk=$sandbox/desk
cfg=$home/.config/cosmic/com.system76.CosmicFiles/v1/context_actions
bin=$home/.local/bin
log=$sandbox/notify.log
pass=0
fail=0

check() { # check <what> <expected> <actual>
    if [ "$2" = "$3" ]; then
        printf '  OK   %s\n' "$1"
        pass=$((pass + 1))
    else
        printf '  FAIL %s\n         expected: %s\n         actual:   %s\n' "$1" "$2" "$3"
        fail=$((fail + 1))
    fi
}

contains() { # contains <what> <needle> <haystack>
    case "$3" in
        *"$2"*) check "$1" "found" "found" ;;
        *) check "$1" "found '$2'" "got: $3" ;;
    esac
}

# --- sandbox ------------------------------------------------------------------------------

mkdir -p "$home/.local/share/applications" "$home/.local/share/icons" "$bin" "$desk" \
    "$sandbox/fakebin" "$sandbox/work/folder"

printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> %s\n' "$log" >"$sandbox/fakebin/notify-send"
printf '#!/bin/sh\necho terminal\n' >"$sandbox/fakebin/cosmic-term"
chmod +x "$sandbox/fakebin/notify-send" "$sandbox/fakebin/cosmic-term"

# a program that brings its own .desktop entry: GUI, no terminal
printf '#!/bin/sh\necho gui\n' >"$bin/MyGui"
chmod +x "$bin/MyGui"
printf '[Desktop Entry]\nType=Application\nName=MyGui\nExec=MyGui\nTerminal=false\n' \
    >"$home/.local/share/applications/mygui.desktop"

# a program without an entry: taken as a command-line program
printf '#!/bin/sh\necho cli\n' >"$bin/MyCli"
chmod +x "$bin/MyCli"

printf '#!/bin/sh\necho appimage\n' >"$sandbox/work/MyApp.AppImage"
chmod +x "$sandbox/work/MyApp.AppImage"
printf '#!/bin/sh\necho script\n' >"$sandbox/work/run-me.sh"
chmod +x "$sandbox/work/run-me.sh"
printf 'text\n' >"$sandbox/work/report.txt"
printf '[Desktop Entry]\nType=Application\nName=Handmade\nExec=/bin/true\n' \
    >"$sandbox/work/handmade.desktop"

run() { # run <language> <file...>
    local language="$1"
    shift
    HOME="$home" LANG="$language" PATH="$sandbox/fakebin:$PATH" DESKTOP_SHORTCUT_DIR="$desk" \
        DESKTOP_SHORTCUT_TERMINAL="${TERMINAL_MODE:-auto}" "$bin/desktop-shortcut.sh" "$@"
}

install_config() { # install_config <language>
    HOME="$home" LANG="$1" "$repo/install.sh" --prefix "$bin" >/dev/null
}

label() { # label <first|second>
    local index=1
    if [ "$1" = second ]; then
        index=2
    fi
    grep -o 'name: "[^"]*"' "$cfg" | sed -n "${index}p" | cut -d'"' -f2
}

# --- installer ----------------------------------------------------------------------------

echo "== installer: German system =="
install_config de_DE.UTF-8
check "menu label 1 is German" "Ausführen" "$(label first)"
check "menu label 2 is German" "Auf den Desktop" "$(label second)"
contains "configuration holds the installed script" "$bin/desktop-shortcut.sh %F" "$(cat "$cfg")"
check "script installed and executable" "yes" "$([ -x "$bin/desktop-shortcut.sh" ] && echo yes || echo no)"
check "no backup inside the version directory" "0" \
    "$(ls "$home"/.config/cosmic/com.system76.CosmicFiles/v1/*.backup-* 2>/dev/null | wc -l)"

echo "== installer: English system =="
install_config en_US.UTF-8
check "menu label 1 is English" "Run" "$(label first)"
check "menu label 2 is English" "Send to Desktop" "$(label second)"
check "one backup next to the version directory" "1" \
    "$(ls "$home"/.config/cosmic/com.system76.CosmicFiles/context_actions.backup-* 2>/dev/null | wc -l)"
contains "the backup holds the German file" "Ausführen" \
    "$(cat "$home"/.config/cosmic/com.system76.CosmicFiles/context_actions.backup-*)"

echo "== installer: other languages =="
check "French system falls back to English" "Run" \
    "$(HOME="$home" LANG=fr_FR.UTF-8 "$repo/install.sh" --print | grep -o 'name: "[^"]*"' | head -1 | cut -d'"' -f2)"
check "LC_ALL wins over LANG" "Run" \
    "$(HOME="$home" LC_ALL=en_US.UTF-8 LANG=de_DE.UTF-8 "$repo/install.sh" --print | grep -o 'name: "[^"]*"' | head -1 | cut -d'"' -f2)"
check "--lang de overrides the system" "Ausführen" \
    "$(HOME="$home" LANG=en_US.UTF-8 "$repo/install.sh" --lang de --print | grep -o 'name: "[^"]*"' | head -1 | cut -d'"' -f2)"
HOME="$home" "$repo/install.sh" --lang xx --print >/dev/null 2>&1
check "unsupported language exits with 2" "2" "$?"

# --- script messages ----------------------------------------------------------------------

echo "== script messages: German system =="
rm -rf "$desk"; mkdir -p "$desk"; : >"$log"
TERMINAL_MODE=no run de_DE.UTF-8 "$sandbox/work/run-me.sh" >"$sandbox/out-de" 2>&1
check "exit code 0" "0" "$?"
contains "console line is German" "Starter angelegt" "$(cat "$sandbox/out-de")"
check "Comment is German" "Comment=Starter für $sandbox/work/run-me.sh" \
    "$(grep -m1 '^Comment=' "$desk/run-me.desktop")"
contains "notification is German" "Verknüpfung auf dem Schreibtisch" "$(cat "$log")"

echo "== script messages: English system =="
rm -rf "$desk"; mkdir -p "$desk"; : >"$log"
TERMINAL_MODE=no run en_US.UTF-8 "$sandbox/work/run-me.sh" >"$sandbox/out-en" 2>&1
contains "console line is English" "created launcher" "$(cat "$sandbox/out-en")"
check "Comment is English" "Comment=Launcher for $sandbox/work/run-me.sh" \
    "$(grep -m1 '^Comment=' "$desk/run-me.desktop")"
contains "notification is English" "Shortcut on the desktop" "$(cat "$log")"

echo "== script messages: usage hint =="
HOME="$home" LANG=de_DE.UTF-8 "$bin/desktop-shortcut.sh" >"$sandbox/usage-de" 2>&1
check "usage error exits with 2" "2" "$?"
contains "usage hint is German" "Aufruf:" "$(cat "$sandbox/usage-de")"
HOME="$home" LANG=en_US.UTF-8 "$bin/desktop-shortcut.sh" >"$sandbox/usage-en" 2>&1
contains "usage hint is English" "usage:" "$(cat "$sandbox/usage-en")"

# --- launcher contents --------------------------------------------------------------------

echo "== launcher contents =="
rm -rf "$desk"; mkdir -p "$desk"
TERMINAL_MODE=auto run en_US.UTF-8 "$bin/MyCli" >/dev/null 2>&1
contains "command-line program is wrapped in a terminal" ' -e ' "$(grep -m1 '^Exec=' "$desk/MyCli.desktop")"
check "launcher says Terminal=false" "false" \
    "$(grep -m1 '^Terminal=' "$desk/MyCli.desktop" | cut -d= -f2)"
rm -rf "$desk"; mkdir -p "$desk"
TERMINAL_MODE=auto run en_US.UTF-8 "$bin/MyGui" >/dev/null 2>&1
check "program with its own entry is not wrapped" "false" \
    "$(grep -m1 '^Terminal=' "$desk/MyGui.desktop" | cut -d= -f2)"
rm -rf "$desk"; mkdir -p "$desk"
TERMINAL_MODE=auto run en_US.UTF-8 "$sandbox/work/MyApp.AppImage" >/dev/null 2>&1
check "AppImage counts as a GUI program" "false" \
    "$(grep -m1 '^Terminal=' "$desk/MyApp.desktop" | cut -d= -f2)"
rm -rf "$desk"; mkdir -p "$desk"
TERMINAL_MODE=yes run en_US.UTF-8 "$sandbox/work/MyApp.AppImage" >/dev/null 2>&1
contains "DESKTOP_SHORTCUT_TERMINAL=yes forces the terminal" ' -e ' \
    "$(grep -m1 '^Exec=' "$desk/MyApp.desktop")"
check "launcher passes desktop-file-validate" "0" \
    "$(desktop-file-validate "$desk/MyApp.desktop" >/dev/null 2>&1; echo $?)"

# --- shortcuts ----------------------------------------------------------------------------

echo "== shortcuts and special cases =="
rm -rf "$desk"; mkdir -p "$desk"
TERMINAL_MODE=no run en_US.UTF-8 "$sandbox/work/report.txt" "$sandbox/work/folder" \
    "$sandbox/work/handmade.desktop" "$sandbox/work/missing.txt" >"$sandbox/out-reg" 2>&1
check "missing path exits with 1" "1" "$?"
check "document becomes a symlink" "yes" "$([ -L "$desk/report.txt" ] && echo yes || echo no)"
check "folder becomes a symlink" "yes" "$([ -L "$desk/folder" ] && echo yes || echo no)"
check ".desktop file becomes a symlink" "yes" "$([ -L "$desk/handmade.desktop" ] && echo yes || echo no)"
contains "missing path is reported" "not found" "$(cat "$sandbox/out-reg")"

rm -rf "$desk"; mkdir -p "$desk"; : >"$log"
TERMINAL_MODE=no run en_US.UTF-8 "$sandbox/work/report.txt" >/dev/null 2>&1
TERMINAL_MODE=no run en_US.UTF-8 "$sandbox/work/report.txt" >/dev/null 2>&1
contains "a second run skips its own shortcut" "shortcut already exists" "$(cat "$log")"

printf 'mine\n' >"$desk/report.txt"
rm -f "$desk/report.txt"; printf 'mine\n' >"$desk/report.txt"
TERMINAL_MODE=no run en_US.UTF-8 "$sandbox/work/report.txt" >/dev/null 2>&1
check "a name collision is counted up" "yes" "$([ -L "$desk/report.txt (2)" ] && echo yes || echo no)"
check "the foreign file stays untouched" "mine" "$(cat "$desk/report.txt")"

rm -rf "$desk"; mkdir -p "$desk"; : >"$log"
TERMINAL_MODE=no run en_US.UTF-8 "$bin/MyCli" >/dev/null 2>&1
TERMINAL_MODE=no run en_US.UTF-8 "$bin/MyCli" >/dev/null 2>&1
contains "an existing launcher is recognised" "launcher already exists" "$(cat "$log")"

printf 'here\n' >"$desk/already-here.txt"
TERMINAL_MODE=no run en_US.UTF-8 "$desk/already-here.txt" >/dev/null 2>&1
contains "a file on the desktop is skipped" "already on the desktop" "$(cat "$log")"

# --- summary ------------------------------------------------------------------------------

echo
echo "sandbox: $sandbox"
echo "result: $pass passed, $fail failed"
if [ "$fail" -eq 0 ]; then
    rm -rf "$sandbox"
    exit 0
fi
exit 1
