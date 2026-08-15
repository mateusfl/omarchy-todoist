# Todoist for Omarchy

A bar widget + popup for [Todoist](https://todoist.com), built for the
[Omarchy](https://omarchy.org) shell. Shows a task count in the bar and
opens a popup with Inbox/Today/Upcoming tabs, natural-language quick-add,
and one-click task completion — styled with the active Omarchy theme,
mixed with Todoist's own priority/project colors.

Authentication and data come from the official
[`td` CLI](https://github.com/Doist/todoist-cli): this plugin never sees or
stores your API token itself, `td` keeps it in your OS keyring.

## Requirements

- Omarchy with the Quickshell-based shell (`omarchy-shell`)
- [`td`](https://github.com/Doist/todoist-cli), the official Todoist CLI:
  ```bash
  npm install -g @doist/todoist-cli
  ```

## Install

```bash
omarchy plugin add https://github.com/mateusfl/omarchy-todoist.git --enable
```

Or by hand:

```bash
git clone https://github.com/mateusfl/omarchy-todoist.git ~/.config/omarchy/plugins/mateusfl.todoist
omarchy-shell shell rescanPlugins
omarchy plugin enable mateusfl.todoist
```

The widget lands in the bar's right section by default; move it with
`omarchy bar move mateusfl.todoist --section <left|center|right>`.

## Usage

- Click the bar icon to open the popup.
- **Inbox / Today / Upcoming** tabs switch which `td` list is shown.
  Today's tab covers overdue + due-today; Upcoming covers overdue +
  due-today + the next 7 days.
- Type into the quick-add field and press Enter (or the **+** button) to
  create a task. It speaks Todoist's own quick-add syntax — due dates,
  `p1`..`p4` priority, `#project`, `@label` all work.
- Click a task's checkbox to complete it.
- Click a task's text to open it in Todoist.
- The refresh icon re-fetches; the bar icon itself also middle-click
  refreshes.

### First run (authentication)

If `td` has no stored credential yet, the popup shows a **Log in with
browser** button (opens Todoist's OAuth flow) or a field to paste a
personal API token (Todoist → Settings → Integrations → Developer).

### Configure

Click the settings (gear) icon in the popup header to open the settings
pane. Currently that's just the UI language — `English` or `Português
(Brasil)`, more may be added over time. The choice is saved with the
widget's own settings in `~/.config/omarchy/shell.json` and survives
restarts.

## Remove

```bash
omarchy plugin remove mateusfl.todoist
```

## Adding a language

All UI strings live in `Strings.js`, keyed by language tag. To add one:

1. Add `{ value: "<tag>", label: "<Display name>" }` to `LANGUAGES`.
2. Add a `DICTS["<tag>"]` dictionary with the same keys as the existing
   `en-US`/`pt-BR` entries.

Nothing else needs to change — the settings dropdown reads `LANGUAGES`
directly, and every string lookup goes through `Strings.t(lang, key)`.

## License

MIT — see [LICENSE](LICENSE).
