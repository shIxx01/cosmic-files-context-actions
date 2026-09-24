# cosmic-files-context-actions

Custom context menu actions for **COSMIC Files**, the file manager of the
[COSMIC desktop](https://github.com/pop-os/cosmic-files).

Since COSMIC Desktop 1.0.10 the file manager supports user-defined entries in its right-click menu.
They are read from the manager's own configuration file — there is no GUI for them yet
(checked against cosmic-files 1.8.0, September 2026).

Two examples, both taken from daily use on a CachyOS/Arch machine:

1. **Run a shell script** — right-click a `.sh` file → *Ausführen* ("Run") → started with bash.
   No `chmod +x`, no terminal round trip.
2. **Shortcut on the desktop** — right-click any file or folder → *Auf den Desktop* ("To the
   desktop") → a symlink appears on the desktop. The counterpart of Windows'
   *Send to → Desktop (create shortcut)*, which COSMIC Files does not have built in.

## Install

### 1. The configuration file

cosmic-config stores every configuration property as its own file in RON format, so the file has to
exist at exactly this path, with exactly this name and **no extension**:

```sh
mkdir -p ~/.config/cosmic/com.system76.CosmicFiles/v1
cp context_actions ~/.config/cosmic/com.system76.CosmicFiles/v1/context_actions
```

Then restart the file manager — it reads the actions when it starts:

```sh
pkill -x cosmic-files; cosmic-files &
```

The entries show up in the more/"…" section of the context menu.

### 2. The script for the desktop shortcut

Put [`scripts/desktop-shortcut.sh`](scripts/desktop-shortcut.sh) somewhere permanent and make it
executable:

```sh
install -Dm755 scripts/desktop-shortcut.sh ~/.local/bin/desktop-shortcut.sh
```

Its path in `context_actions` has to be the **absolute** path, written out in full — see the pitfall
about `~` below. Adjust that line after copying.

## The examples

[`context_actions`](context_actions) — replace `/home/you` with your own home directory:

```ron
[
    (
        name: "Ausführen",
        confirm: false,
        selection: Files,
        steps: [
            "/bin/bash %f",
        ],
    ),
    (
        name: "Auf den Desktop",
        confirm: false,
        selection: Any,
        steps: [
            "/home/you/.local/bin/desktop-shortcut.sh %F",
        ],
    ),
]
```

### Desktop shortcuts: what the script does

`desktop-shortcut.sh FILE...` creates one symlink per argument in the desktop directory. It takes
that directory from `xdg-user-dir DESKTOP` and falls back to `~/Desktop`. On a German desktop that
is `~/Schreibtisch` — the script follows the locale instead of hard-coding a folder name.

* Names are kept: on the desktop, `Bericht.pdf` points to the file you right-clicked.
* If the name is taken by something else, the new shortcut is numbered — `Bericht.pdf (2)`,
  `(3)` … — the way Windows does it.
* A shortcut that already exists (a symlink to the same target) is left alone instead of being
  duplicated.
* A file that already lives on the desktop is reported as skipped, not linked to itself.
* A symlink you right-click is resolved first, so shortcuts do not chain.
* Because a context action shows no output, the result is reported through `notify-send`
  (created / skipped / failed). Without `notify-send` in `PATH` the script stays silent and still
  works.
* Exit code 0 on success, 1 if anything failed, 2 on a usage error — usable from a terminal too.

```
$ desktop-shortcut.sh ~/Dokumente/Bericht.pdf ~/Dokumente/Bericht.pdf
created /home/tom/Schreibtisch/Bericht.pdf -> /home/tom/Dokumente/Bericht.pdf
```

## Fields

Taken from the source (`src/context_action.rs`, `src/config.rs`, `src/menu.rs`, `src/app.rs`):

| Field | Meaning |
| --- | --- |
| `name` | Menu label, shown as-is — any language you like. |
| `confirm` | `false`: run immediately. `true`: a dialog asks `Run "<name>"?` and names how many items it will run on. |
| `selection` | `Files`: only when the selection contains no folder. `Folders`: only when everything selected is a folder. `Any`: always (at least one item must be selected). Lowercase `files` / `folders` / `any` are accepted too. |
| `steps` | Commands, executed in order. Each entry is one `Exec` line, parsed like a `.desktop` file's `Exec` (see below). An empty list means the action is ignored. |

## Field codes in `steps`

`steps` go through the same `Exec` parser as desktop entries
(`mime_app::exec_to_command`), so the freedesktop field codes work:

| Code | Expands to |
| --- | --- |
| `%f`, `%u` | one selected file path — the command is started **once per selected file** |
| `%F`, `%U` | the whole selection in a **single** invocation, one argument per path |
| `%c` | the `name` of the action |
| `%k` | path of the desktop entry — empty here, a context action is not a desktop entry |
| `%%` | a literal `%` |

The actions also appear in the right-click menu of a sidebar or path entry, where they apply to that
single location.

## Variations

Ask before every run (safer for destructive scripts):

```ron
(name: "Ausführen", confirm: true, selection: Files, steps: ["/bin/bash %f"])
```

Offer the run action for files and folders alike:

```ron
(name: "Ausführen", confirm: false, selection: Any, steps: ["/bin/bash %f"])
```

Hand the whole selection to one script instead of starting it once per file:

```ron
(name: "Ausführen", confirm: true, selection: Files, steps: ["/bin/bash %F"])
```

Rename the actions per language by just changing `name` — e.g. `name: "Run"` and
`name: "Send to desktop"`.

## Pitfalls

* **No extension on the file name.** `context_actions.ron` is not read.
* **No shell, so no shell expansion.** A `steps` line is split and executed directly
  (`shlex::split` + `process::Command`), never through a shell: `~`, `$HOME`, `*` and pipes are
  **not** expanded. Write absolute paths, or put the logic in a script and call that.
* **No output window, no feedback.** Commands are started detached
  (`spawn_detached`); cosmic-files does not wait for them and shows nothing. Have the script report
  through `notify-send` (as `desktop-shortcut.sh` does) or write a log file.
* **`steps` is not a fail-fast chain.** If a step fails, the next one still runs; the failure is
  only logged to the journal (`log::warn`).
* **`%f` with a multi-selection starts the command once per file.** Use `%F` to process all of
  them in one go — which is what the desktop shortcut action needs.
* **Desktop icons live in the XDG desktop directory.** `xdg-user-dir DESKTOP` decides; on a German
  system that is `~/Schreibtisch`, not `~/Desktop`.
* Only the field codes shown above were read from the source; `%F` / `%U` are not exercised by the
  first example (it uses `%f`), but they are by the second one.

## Tested with

cosmic-files `1:1.8.0-1.1` on CachyOS (Arch), 24 September 2026:

* the menu entry appears and runs the selected `.sh` file (example 1),
* `desktop-shortcut.sh` was exercised with: a file, a folder, a name with umlauts, a repeated run
  (skipped), a name collision (numbered `(2)`), a file that already sits on the desktop (skipped),
  a symlink (resolved to the target), a missing path (failed, exit 1), no arguments (exit 2),
  a missing desktop directory (exit 1), and with `notify-send` missing from `PATH` (silent, still
  creates the shortcut).

## Sources

* [pop-os/cosmic-files](https://github.com/pop-os/cosmic-files) — `src/context_action.rs`,
  `src/mime_app.rs` (`exec_to_command`), `src/config.rs`, `src/menu.rs`, `src/app.rs`
* [Issue #1445 — Custom Context Menu Actions / User Scripts Support](https://github.com/pop-os/cosmic-files/issues/1445)
* COSMIC Desktop 1.0.10 release notes (file manager actions)

## License

MIT — see [LICENSE](LICENSE). The configuration file is not creative work in any meaningful sense;
copy it, change it, no conditions.
