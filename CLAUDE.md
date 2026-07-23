# CLAUDE.md — halo

Guidance for working in this repository.

## Docs

English-only and code-first — follow the fleet
[doc-consistency policy](https://github.com/akira-toriyama/.github/blob/main/docs/doc-consistency-policy.md)
(no stored translations; truth lives in the code/CLI, docs point to it).

## CLI surface (config-driven — OUT of the domain-verb grammar)

halo is **config-driven**: `~/.config/halo/config.toml` (hot-reloaded on save)
is the only control surface — there is no runtime control CLI. Under atelier
Phase 3 (unifying the family's CLI grammar) halo is deliberately **OUT** — not a
target of the yabai-style domain-verb grammar, because inventing a control CLI
would be a feature, not a refactor. The canonical grammar is
[cli-grammar.md](https://github.com/akira-toriyama/atelier/blob/main/docs/cli-grammar.md).

The only flags halo recognizes are `--emit-schema` (writes config.toml's JSON
Schema to stdout) and the family-wide carve-out `-h` / `--help`. **Any other
argument exits 2, loudly** (the family's "no silent fallback" sub-rule — never
start up silently). A normal launch with no arguments (`open Halo.app` / brew
services / a LaunchAgent) has an empty argv, so it never hits that rejection.
The implementation is [Sources/Halo/main.swift](Sources/Halo/main.swift).

## Shared libraries (atelier)

This app rides the swift app family's shared libraries (see the
[atelier](https://github.com/akira-toriyama/atelier) plan). Where a shared
library owns a responsibility, **extend the library rather than reimplementing
it** (the north star: never say "copy facet's theme" again). The exact
module → target wiring is authoritative in [Package.swift](Package.swift).

- **[sill](https://github.com/akira-toriyama/sill)** — the shared theming / CLI
  foundation (design → [`docs/DESIGN.md`](https://github.com/akira-toriyama/sill/blob/main/docs/DESIGN.md)).
  halo uses `Effects` (border resolve / theme) and `ConfigSchema` (the taplo
  schema behind `--emit-schema`).
- **[swift-toml-edit](https://github.com/akira-toriyama/swift-toml-edit)** — the
  family's one TOML implementation (the `Toml` module, a Swift port of
  toml_edit). halo uses it to parse config.toml.

## Roadmap board (GitHub Projects)

Issue workflow — the aggregated Project "roadmap" #5, Inbox by default, the
Status flow, `Closes #N` — is a family-wide policy. Canonical →
https://github.com/akira-toriyama/atelier/blob/main/docs/roadmap-board.md
