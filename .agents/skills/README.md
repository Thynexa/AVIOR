# Vendored skills: superpowers

The skill directories in this folder are vendored from the
[superpowers](https://github.com/obra/superpowers) plugin by Jesse Vincent,
version **6.0.3**, licensed MIT (see [`LICENSE-superpowers`](./LICENSE-superpowers)).

The content is copied as-is except for one adaptation: cross-skill references
that used the plugin namespace (`<skill>`) are rewritten to the bare
skill names (`<skill>`). Plugin skills are namespaced, but project skills under
`.claude/skills/<name>/SKILL.md` are invoked by their direct names, so the
namespaced references would otherwise point at skills that don't exist here.

## Why vendored instead of installed as a plugin

Claude Code on the web runs in ephemeral cloud containers that clone the repo
fresh each session. A plugin declared in `.claude/settings.json`
(`extraKnownMarketplaces` + `enabledPlugins`) is only *registered* there — the
actual install is not reliably performed at session start, and a plugin
installed mid-session (e.g. via a `SessionStart` hook) does not load into that
same session. Project skills under `.claude/skills/<name>/SKILL.md`, by
contrast, are auto-discovered on every session with **no install step, no
network access, and no GitHub-proxy dependency** — so they work the same in
local and web sessions and persist across containers.

## Scope and caveats

- Only the **skills** are vendored. The plugin's hooks, slash commands, and any
  MCP pieces are intentionally **not** included. The skills are therefore
  available to the model but are not force-dispatched by the upstream
  `using-superpowers` hook — the model invokes them on match via the Skill tool.
- Each skill directory keeps its own support files (`scripts/`, `references/`,
  etc.); intra-skill relative references are preserved.

## Updating

Re-install the upstream plugin and re-copy its `skills/` directory:

```bash
claude plugin marketplace add obra/superpowers-marketplace
claude plugin install superpowers@superpowers-marketplace
cp -a "$(claude plugin path superpowers 2>/dev/null || echo ~/.claude/plugins/cache/superpowers-marketplace/superpowers/<version>)/skills/." .claude/skills/
# Re-apply the de-namespacing adaptation described above:
find .claude/skills -type f -name "*.md" -exec sed -i 's///g' {} +
```

Track releases at https://github.com/obra/superpowers/releases.

## v6 migration notes (from 5.1.0)

- **Subagent-driven development:** `spec-reviewer-prompt.md` and
  `code-quality-reviewer-prompt.md` are replaced by a single
  `task-reviewer-prompt.md`. New helper scripts live under
  `subagent-driven-development/scripts/`.
- **Git worktrees:** no longer uses `~/.config/superpowers/worktrees/`; worktrees
  land in the project (`.worktrees/` or `worktrees/`).
- **Using-superpowers:** added platform tool references for Antigravity, Claude
  Code, and Pi; descriptions are more vendor-neutral.
