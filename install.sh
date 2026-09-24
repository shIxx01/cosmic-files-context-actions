#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# install.sh - install the desktop-shortcut script and write the context_actions file for
# COSMIC Files.
#
# cosmic-files shows the configured "name" of a context action exactly as it stands - the
# configuration has no translation of its own. So the menu labels are written in the system
# language: German on a German system, English everywhere else. Run this script again after
# changing the system language.
#
# Usage:
#   ./install.sh [--lang de|en] [--prefix DIR] [--print]
#
# Options:
#   --lang de|en    language of the menu labels (default: from LC_ALL / LC_MESSAGES / LANG)
#   --prefix DIR    where to install desktop-shortcut.sh (default: ~/.local/bin)
#   --print         only print the configuration, change nothing
#   -h, --help      this text
#
# What it does:
#   1. installs scripts/desktop-shortcut.sh into <prefix> (0755),
#   2. writes ~/.config/cosmic/com.system76.CosmicFiles/v1/context_actions with two actions,
#      an existing file is backed up first - next to the version directory, not inside it,
#      because cosmic-config reads every file in there as a setting,
#   3. tells you to restart cosmic-files (it reads context_actions at startup).

set -u
set -o pipefail

repo_dir=$(cd -- "$(dirname -- "$0")" && pwd)
prefix="$HOME/.local/bin"
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/cosmic/com.system76.CosmicFiles/v1"
config_file="$config_dir/context_actions"
language_override=""
print_only=0

usage() {
    cat <<'EOF'
usage: install.sh [--lang de|en] [--prefix DIR] [--print]

  --lang de|en    language of the menu labels (default: from LC_ALL / LC_MESSAGES / LANG)
  --prefix DIR    where to install desktop-shortcut.sh (default: ~/.local/bin)
  --print         only print the configuration, change nothing
  -h, --help      this text
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --lang)
            language_override="${2:-}"
            shift 2
            ;;
        --lang=*)
            language_override="${1#*=}"
            shift
            ;;
        --prefix)
            prefix="${2:-}"
            shift 2
            ;;
        --prefix=*)
            prefix="${1#*=}"
            shift
            ;;
        --print)
            print_only=1
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            echo "unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

# --- language -----------------------------------------------------------------------------

system_language() {
    local tag="${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" name
    name="${tag%%_*}"
    name="${name%%-*}"
    name="${name%%.*}"
    case "$name" in
        de) printf 'de\n' ;;
        *) printf 'en\n' ;;
    esac
}

ui_lang="${language_override:-$(system_language)}"
case "$ui_lang" in
    de | en) ;;
    *)
        echo "unsupported language '$ui_lang' (supported: de, en)" >&2
        exit 2
        ;;
esac

case "$ui_lang" in
    de)
        label_run="Ausführen"
        label_desktop="Auf den Desktop"
        ;;
    en)
        label_run="Run"
        label_desktop="Send to Desktop"
        ;;
esac

script_path="$prefix/desktop-shortcut.sh"
source_script="$repo_dir/scripts/desktop-shortcut.sh"

if [ ! -f "$source_script" ]; then
    echo "scripts/desktop-shortcut.sh not found next to this script ($repo_dir)" >&2
    exit 1
fi

configuration=$(
    cat <<EOF
[
    (
        name: "$label_run",
        confirm: false,
        selection: Files,
        steps: [
            "/bin/bash %f",
        ],
    ),
    (
        name: "$label_desktop",
        confirm: false,
        selection: Any,
        steps: [
            "$script_path %F",
        ],
    ),
]
EOF
)

if [ "$print_only" -eq 1 ]; then
    printf '%s\n' "$configuration"
    exit 0
fi

install -Dm755 "$source_script" "$script_path" || exit 1
mkdir -p "$config_dir" || exit 1

backup=""
if [ -f "$config_file" ]; then
    # Outside the version directory: cosmic-config treats every file in there as a setting.
    backup="${config_dir%/*}/context_actions.backup-$(date +%Y%m%d-%H%M%S)"
    cp -- "$config_file" "$backup" || exit 1
fi

printf '%s\n' "$configuration" >"$config_file" || exit 1

echo "installed: $script_path"
echo "written:   $config_file (language: $ui_lang, labels: $label_run, $label_desktop)"
if [ -n "$backup" ]; then
    echo "backup:    $backup"
fi
echo
echo "cosmic-files reads the actions when it starts, so restart it:"
echo "    pkill -x cosmic-files; cosmic-files &"
echo
echo "changed the system language? run this script again to rewrite the labels."
