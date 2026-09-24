# cosmic-files-context-actions

Custom context menu actions for **COSMIC Files**, the file manager of the
[COSMIC desktop](https://github.com/pop-os/cosmic-files).

Since COSMIC Desktop 1.0.10 the file manager supports user-defined entries in its right-click menu.
They are read from the manager's own configuration file — there is no GUI for them yet
(checked against cosmic-files 1.8.0, September 2026).

The example in this repository is the one I use every day: **right-click a `.sh` file →
"Ausführen"** ("Run" in German) → the script is started with bash. No `chmod +x`, no terminal
round trip.

## Install

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

Right-click a `.sh` file: the entry shows up in the more/"…" section of the context menu.

## The example

[`context_actions`](context_actions):

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
]
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

Offer the action for files and folders alike:

```ron
(name: "Ausführen", confirm: false, selection: Any, steps: ["/bin/bash %f"])
```

Hand the whole selection to one script instead of starting it once per file:

```ron
(name: "Ausführen", confirm: true, selection: Files, steps: ["/bin/bash %F"])
```

Rename the action per language by just changing `name` — e.g. `name: "Run"`.

## Pitfalls

* **No extension on the file name.** `context_actions.ron` is not read.
* **No output window, no feedback.** Commands are started detached
  (`spawn_detached`); cosmic-files does not wait for them and shows nothing. If a script is
  interactive, have it open a terminal itself; otherwise write a log file.
* **`steps` is not a fail-fast chain.** If a step fails, the next one still runs; the failure is
  only logged to the journal (`log::warn`).
* **`%f` with a multi-selection starts the command once per file.** Use `%F` to process all of
  them in one go.
* Only the field codes shown above were read from the source; `%F` / `%U` are **not** exercised in
  the example (it uses `%f`).

## Tested with

cosmic-files `1:1.8.0-1.1` on CachyOS (Arch), 24 September 2026: the menu entry appears and runs
the selected `.sh` file.

## Sources

* [pop-os/cosmic-files](https://github.com/pop-os/cosmic-files) — `src/context_action.rs`,
  `src/mime_app.rs` (`exec_to_command`), `src/config.rs`, `src/menu.rs`, `src/app.rs`
* [Issue #1445 — Custom Context Menu Actions / User Scripts Support](https://github.com/pop-os/cosmic-files/issues/1445)
* COSMIC Desktop 1.0.10 release notes (file manager actions)

## License

MIT — see [LICENSE](LICENSE). The configuration file is not creative work in any meaningful sense;
copy it, change it, no conditions.
