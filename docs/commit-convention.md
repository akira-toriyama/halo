# Commit convention & versioning

This repo commits with **gitmoji + Conventional Commits**; from the messages
[git-cliff](https://git-cliff.org) computes semver and the release notes.
Mirrors facet's convention (same culture across the family).

## Format

```
<gitmoji> <type>(<scope>)<!>: <subject>

<body, optional>

<footer, optional / BREAKING CHANGE: ...>
```

- `<gitmoji>` … exactly one leading gitmoji in the `:sparkles:` **text form**
  (grep-friendly; not the emoji glyph). e.g. `:bug:`.
- `<type>` … Conventional Commits type (`feat` `fix` `perf` `refactor` `docs`
  `test` `build` `ci` `chore` `style` `revert`). **semver is decided by this.**
- `<scope>` … optional, **parenthesised only**: `(border)` `(focus)` `(config)`
  `(packaging)` `(homebrew)` `(ci)` etc. For sub-scopes use dashes inside the
  parens. Multi-word scopes go inside the parens too: `(commit-lint)`,
  `(update-tap)`.
- `!` … breaking change. Or a `BREAKING CHANGE: <desc>` footer.
- `<subject>` … imperative, concise. English or Japanese (match history).

### Examples

```
:sparkles: feat(border): cycle the ring through the neon palette
:zap: perf(focus): settle-deferred re-resolve
:bug: fix(config): clamp width to a sane minimum
:memo: docs: document the Homebrew tap flow
:wrench: chore: strengthen .gitignore
:green_heart: ci: pin latest-stable Xcode (Swift 6)
```

## semver mapping

| Change | Type / marker | Version |
|---|---|---|
| Breaking change | `<type>!` / `BREAKING CHANGE:` | **major** |
| New feature | `feat` | **minor** |
| Bug fix / perf | `fix` / `perf` | **patch** |
| Everything else (`docs` `ci` `chore` `style` `test` `refactor` `build`) | — | **no bump** |

The **type is authoritative** for semver; gitmoji is for readability and
changelog grouping (if they disagree, the type wins). Bot commits
(`github-actions`, `*[bot]`) are excluded from versioning and the changelog
(see [cliff.toml](../cliff.toml) `commit_parsers`).

## Release flow

Releases are automated by [.github/workflows/release.yml](../.github/workflows/release.yml)
(rolling-draft model):

1. Merge `feat:`/`fix:`/`perf:` to `main`. git-cliff computes the next version
   and the workflow creates/updates a single **draft** GitHub Release with the
   built `Halo.zip` attached. No tag yet.
2. Review the draft; **Publish** it in the GitHub UI — GitHub creates the tag
   (`vX.Y.Z`) on the target commit at publish time.
3. Publishing fires [.github/workflows/update-tap.yml](../.github/workflows/update-tap.yml),
   which bumps the Homebrew tap formula (`akira-toriyama/homebrew-tap`,
   `Formula/halo.rb`) to the new tag + source-tarball sha256.

`workflow_dispatch` with `dry_run=true` is a full preview (no draft, no
version consumed). Non-bumping-only changes ⇒ the workflow no-ops.

The initial version is `v1.0.0` ([cliff.toml](../cliff.toml) `initial_tag`).
CHANGELOG is not pushed to `main`; the GitHub Release notes are canonical.

## Local hook (optional, low-dependency)

No Node required. Enable the bundled shell hook:

```sh
git config core.hooksPath scripts/hooks
```

`commit-msg` validates the gitmoji + Conventional form. CI validates the same
on every PR via [.github/workflows/commit-lint.yml](../.github/workflows/commit-lint.yml).
