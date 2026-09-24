#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# desktop-shortcut.sh - put a shortcut (symlink) for every given file or folder on the desktop.
# The Linux counterpart of Windows' "Send to > Desktop (create shortcut)".
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

created=()
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

    link="$desktop_dir/$name"
    if [ -L "$link" ] && [ "$(readlink -f -- "$link")" = "$target" ]; then
        skipped+=("$name: shortcut already exists")
        continue
    fi

    # Name taken (by anything else): number it, the way Windows does.
    number=2
    while [ -e "$link" ] || [ -L "$link" ]; do
        if [ "$number" -gt 99 ]; then
            link=""
            break
        fi
        link="$desktop_dir/$name ($number)"
        number=$((number + 1))
    done

    if [ -z "$link" ]; then
        failed+=("$name: no free name on the desktop")
        continue
    fi

    if ln -s -- "$target" "$link"; then
        created+=("$(basename -- "$link")")
        echo "created $link -> $target"
    else
        failed+=("$name: could not create the shortcut")
    fi
done

body=""
if [ "${#created[@]}" -gt 0 ]; then
    body+="Created: ${created[*]}"$'\n'
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
elif [ "${#created[@]}" -gt 0 ]; then
    notify "Shortcut on the desktop" "$body" normal
else
    notify "Shortcut on the desktop: nothing to do" "$body" low
fi
