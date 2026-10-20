# PR titles and labels

The workflow `.github/workflows/pr-labels.yml` applies all PR labels. Do not add or remove these labels manually. The workflow changes them back.

## PR title

The PR title must use the Conventional Commits format:

```
<type>: <description>
<type>(<scope>): <description>
```

Add `!` before the colon for a breaking change, for example `feat!: remove old planner`.

The `pr-title` check fails if the title does not use this format. This check is required, so the PR cannot merge. Main allows squash merges only, and the PR title becomes the commit message on main. Commits on the branch can use any format.

## Kind labels

The title type sets one kind label.

| Type       | Label           |
| ---------- | --------------- |
| `feat`     | `enhancement`   |
| `fix`      | `bug`           |
| `docs`     | `documentation` |
| `refactor` | `refactor`      |
| `test`     | `test`          |
| `ci`       | `ci`            |
| `chore`    | `chore`         |
| `build`    | `ci`            |
| `perf`     | `enhancement`   |
| `style`    | `chore`         |
| `revert`   | no label        |

## Size labels

The number of changed lines (additions + deletions) sets one size label.

| Label     | Changed lines |
| --------- | ------------- |
| `size:XS` | 0–9           |
| `size:S`  | 10–99         |
| `size:M`  | 100–499       |
| `size:L`  | 500–999       |
| `size:XL` | 1000 or more  |

## Area labels

The changed file paths set zero or more area labels. `.github/labeler.yml` contains the paths.

| Label        | Paths                                                  |
| ------------ | ------------------------------------------------------ |
| `area:plan`  | `plan/`                                                |
| `area:tests` | `tests/`                                               |
| `area:docs`  | `docs/`, `GLOSSARY.md`, `UX.md`, `CLAUDE.md`           |
| `area:ci`    | `.github/`, `scripts/`, `.luacheckrc`, `stylua.toml`   |

Files in `probes/` get no area label.
