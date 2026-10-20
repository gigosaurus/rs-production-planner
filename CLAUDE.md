## Agent skills

### Issue tracker

The project keeps issues as GitHub issues in `gigosaurus/rs-production-planner`. See `docs/agents/issue-tracker.md`.

Before you start work on an issue, assign it to `@me`. See "When you start work on an issue" in `docs/agents/issue-tracker.md`.

### Triage labels

The default labels are needs-triage, needs-info, ready-for-agent, ready-for-human and wontfix. See `docs/agents/triage-labels.md`.

### PR titles and labels

PR titles must use the Conventional Commits format, for example `feat: count module`. A workflow applies the kind, size and area labels. See `docs/agents/pr-labels.md`.

### Domain docs

The project has one context: one `GLOSSARY.md` at the root, and `docs/adr/`. See `docs/agents/domain.md`.

## RuneScape plugin development

We write plugins in Lua against the RuneScape Client API. `runescape-docs/knowledge-base/` contains a local Markdown copy of the official docs.

### API reference (always loaded)
@../runescape-docs/knowledge-base/api-signatures.md

This file lists every documented function, event, event payload field, type, property and enum value.
- Use only APIs that are in this list. If an API is not in the list, it does not exist. Say so, and suggest an alternative. Do not guess.
- Use names, letter case, argument order and types exactly as the list shows them.

### Before you write or change code that uses an API
1. Find the applicable page in `runescape-docs/knowledge-base/llms.txt`. This file is an index of all pages, with a one-line summary of each page.
2. Read that page in `runescape-docs/knowledge-base/pages/`. It has tables of parameters and return values, examples, and the warnings for that feature.
3. Obey each **[WARNING]** and **[IMPORTANT]** note on the page. These notes cover required permissions, unsupported cases, and things that cause the rejection of a plugin.

### Modules
Every module must return a table. The game client's `require` returns `nil` for a module that returns a function (see `probes/require-probe`).

### Checks
CI (`.github/workflows/checks.yml`) runs these checks on each pull request. Run them before you commit:
- `lua5.4 tests/run.lua`
- `luacheck plan tests` (config: `.luacheckrc`)
- `stylua plan tests` (config: `stylua.toml`). Run it two times. One pass does not always give stable output.
- `scripts/check-manifests.sh`

### Pull request titles
The `pr-title` job (`.github/workflows/pr-labels.yml`) fails a pull request when its title does not start with `<type>: ` or `<type>(<scope>): `. The title becomes the squash commit on `main`.
- Types: `feat`, `fix`, `docs`, `refactor`, `test`, `ci`, `chore`, `build`, `perf`, `style`, `revert`.
- Example: `docs: assign an issue to @me before work starts`.

### Before you prepare a plugin for submission
Read `pages/submission/guidelines.md`, `pages/submission/adequacy.md` and `pages/submission/process.md`. Then check the plugin against them.

### Do not
- Do not load `llms-full.md` (approximately 200k tokens). Read individual pages instead.
- Do not load all of `constraints-and-warnings.md`. To find the restrictions of a feature across pages, search the file (grep) for the feature name.
- Do not edit files in `runescape-docs/`. The tools in `runescape-docs/tools/` make these files.

## Policy
- Write short answers. Each token is important. Use Simplified Technical English (ASD-STE100): short sentences, active voice, one idea in each sentence, approved words. Remove words that add no information. This applies to all text: answers, comments, test names, documents and UI text in the game.
- Do not assume. When a decision is open and the user gave no direction, stop and ask. Do not choose a default and continue.
