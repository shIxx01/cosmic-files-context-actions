#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# desktop-shortcut.sh - put a shortcut for every given file or folder on the desktop.
# The Linux counterpart of Windows' "Send to > Desktop (create shortcut)".
#
#   executable file (program, AppImage, script)  -> a real .desktop launcher with an icon
#   anything else (document, folder)             -> a symlink
#
# A file that already is a .desktop launcher stays a symlink: it brings its own icon.
#
# Usage:
#   desktop-shortcut.sh FILE...
#
# Environment:
#   DESKTOP_SHORTCUT_DIR   target directory instead of the XDG desktop directory
#                          (used by the tests; normal runs do not need it)

set -u
set -o pipefail

desktop_dir="${DESKTOP_SHORTCUT_DIR:-}"
if [ -z "$desktop_dir" ]; then
    desktop_dir=$(xdg-user-dir DESKTOP 2>/dev/null || true)
fi
if [ -z "$desktop_dir" ] || [ ! -d "$desktop_dir" ]; then
    desktop_dir="$HOME/Desktop"
fi

if [ "$#" -eq 0 ]; then
    echo "usage: $(basename -- "$0") FILE..." >&2
    exit 2
fi

if [ ! -d "$desktop_dir" ]; then
    echo "desktop directory '$desktop_dir' does not exist" >&2
    exit 1
fi

# cosmic-files shows no output of a context action, so report through the notification daemon.
notify() { # notify <summary> <body> [urgency]
    command -v notify-send >/dev/null 2>&1 || return 0
    notify-send -a "Desktop shortcut" -u "${3:-normal}" "$1" "$2" 2>/dev/null || true
}

# Best effort: an icon for a program - a picture next to it, or a name the icon themes know.
# Falls back to the generic "application-x-executable", which every theme carries.
find_icon() { # find_icon <directory-of-the-program> <name-without-extension>
    local dir="$1" name="$2" search hit candidate
    for candidate in "$dir/$name.png" "$dir/$name.svg" "$dir/$name.xpm"; do
        if [ -f "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    for search in "$HOME/.local/share/icons" "$HOME/.local/share/pixmaps" /usr/share/pixmaps /usr/share/icons; do
        [ -d "$search" ] || continue
        hit=$(find "$search" -maxdepth 6 \
            \( -iname "$name.png" -o -iname "$name.svg" -o -iname "$name.xpm" \) \
            -print -quit 2>/dev/null)
        if [ -n "$hit" ]; then
            printf '%s\n' "$hit"
            return 0
        fi
    done
    printf 'application-x-executable\n'
    return 0
}

# First free name in the desktop directory, or nothing when everything up to (99) is taken.
unique_path() { # unique_path <base-name> <suffix>
    local base="$1" suffix="$2" candidate="$desktop_dir/$1$2" number=2
    while [ -e "$candidate" ] || [ -L "$candidate" ]; do
        if [ "$number" -gt 99 ]; then
            return 1
        fi
        candidate="$desktop_dir/$base ($number)$suffix"
        number=$((number + 1))
    done
    printf '%s\n' "$candidate"
    return 0
}

# A launcher this script wrote for exactly that target, if there is one.
existing_launcher() { # existing_launcher <target>
    local target="$1" file
    for file in "$desktop_dir"/*.desktop; do
        [ -f "$file" ] || continue
        if grep -qxF -- "X-DesktopShortcut-Target=$target" "$file" 2>/dev/null; then
            printf '%s\n' "$file"
            return 0
        fi
    done
    return 1
}

make_launcher() { # make_launcher <target> <launcher-path>
    local target="$1" launcher="$2" name icon quoted dir
    name=$(basename -- "$target")
    case "$name" in
        *.AppImage | *.appimage | *.run | *.bin | *.exe | *.sh) name="${name%.*}" ;;
    esac
    dir=$(dirname -- "$target")
    # Exec is no shell line: the path has to be quoted by the desktop entry rules.
    quoted=$(printf '%s' "$target" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
    icon=$(find_icon "$dir" "$name")
    {
        printf '[Desktop Entry]\n'
        printf 'Type=Application\n'
        printf 'Version=1.0\n'
        printf 'Name=%s\n' "$name"
        printf 'Comment=Launcher for %s\n' "$target"
        printf 'Exec="%s" %%U\n' "$quoted"
        printf 'Path=%s\n' "$dir"
        printf 'Icon=%s\n' "$icon"
        printf 'Terminal=false\n'
        printf 'Categories=Utility;\n'
        printf 'X-DesktopShortcut-Target=%s\n' "$target"
    } >"$launcher" || return 1
    # The executable bit is what makes the file manager trust the launcher.
    chmod 755 "$launcher" || return 1
    return 0
}

created_links=()
created_launchers=()
skipped=()
failed=()

for arg in "$@"; do
    if [ ! -e "$arg" ] && [ ! -L "$arg" ]; then
        failed+=("$(basename -- "$arg"): not found")
        continue
    fi

    # Shortcut to the real target, so a shortcut to a shortcut does not pile up.
    target=$(realpath -- "$arg" 2>/dev/null) || target="$arg"
    name=$(basename -- "$target")

    if [ "$(dirname -- "$target")" = "$desktop_dir" ]; then
        skipped+=("$name: already on the desktop")
        continue
    fi

    # An executable file that is not itself a launcher gets a real .desktop file with an icon.
    if [ -f "$target" ] && [ -x "$target" ] && [ "${target%.desktop}" = "$target" ]; then
        if existing_launcher "$target" >/dev/null; then
            skipped+=("$name: launcher already exists")
            continue
        fi
        launcher_name="$name"
        case "$launcher_name" in
            *.AppImage | *.appimage | *.run | *.bin | *.exe | *.sh) launcher_name="${launcher_name%.*}" ;;
        esac
        launcher=$(unique_path "$launcher_name" .desktop) || {
            failed+=("$name: no free name on the desktop")
            continue
        }
        if make_launcher "$target" "$launcher"; then
            created_launchers+=("$(basename -- "$launcher")")
            echo "created launcher $launcher -> $target"
        else
            failed+=("$name: could not write the launcher")
        fi
        continue
    fi

    link="$desktop_dir/$name"
    if [ -L "$link" ] && [ "$(readlink -f -- "$link")" = "$target" ]; then
        skipped+=("$name: shortcut already exists")
        continue
    fi
    link=$(unique_path "$name" '') || {
        failed+=("$name: no free name on the desktop")
        continue
    }
    if ln -s -- "$target" "$link"; then
        created_links+=("$(basename -- "$link")")
        echo "created shortcut $link -> $target"
    else
        failed+=("$name: could not create the shortcut")
    fi
done

body=""
if [ "${#created_launchers[@]}" -gt 0 ]; then
    body+="Launchers: ${created_launchers[*]}"$'\n'
fi
if [ "${#created_links[@]}" -gt 0 ]; then
    body+="Shortcuts: ${created_links[*]}"$'\n'
fi
if [ "${#skipped[@]}" -gt 0 ]; then
    body+="Skipped: ${skipped[*]}"$'\n'
fi
if [ "${#failed[@]}" -gt 0 ]; then
    body+="Failed: ${failed[*]}"$'\n'
fi

if [ "${#failed[@]}" -gt 0 ]; then
    notify "Shortcut on the desktop: failed" "$body" critical
    echo "$body" >&2
    exit 1
elif [ "${#created_links[@]}" -gt 0 ] || [ "${#created_launchers[@]}" -gt 0 ]; then
    notify "Shortcut on the desktop" "$body" normal
else
    notify "Shortcut on the desktop: nothing to do" "$body" low
fi
