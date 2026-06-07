# skills

Personal skills repository for cc-switch style subscriptions.

Skill folders live directly at the repository root. The sync workflow mirrors upstream skills from `obra/superpowers`, then applies Chinese descriptions from `codex-skills/translations.json`.

## Layout

- `brainstorming/`, `writing-skills/`, etc.: root-level skill folders with `SKILL.md`
- `codex-skills/translations.json`: Chinese description map
- `codex-skills/sync-superpowers-skills.ps1`: upstream sync script
- `.github/workflows/sync-superpowers-skills.yml`: scheduled/manual sync workflow
