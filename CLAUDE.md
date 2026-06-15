# CLAUDE.md

Guidance for working in this repository.

## CLI surface (config-driven — OUT of the domain-verb grammar)

halo は **config-driven**。`~/.config/halo/config.toml`（保存で hot-reload）が
唯一の制御面で、runtime の制御 CLI は持たない。atelier Phase 3（family CLI
文法統一）でも halo は **OUT** ＝ yabai 式 domain-verb 文法の対象外（制御 CLI を
発明するのは refactor ではなく feature）。正典は
[cli-grammar.md](https://github.com/akira-toriyama/atelier/blob/main/docs/cli-grammar.md)。

認識する flag は `--emit-schema`（config.toml の JSON Schema を stdout に）と
family 共通 carve-out の `-h`/`--help` のみ。**それ以外の引数は loud に exit 2**
（family 横断 sub-規約「no silent fallback」— 黙って起動しない）。引数なしの
通常起動（`open Halo.app` / brew services / LaunchAgent）は argv が空なので
この拒否に当たらない。実装は [Sources/Halo/main.swift](Sources/Halo/main.swift)。

## Roadmap board (GitHub Projects)

issue 運用（集約 Project「roadmap」#5・Inbox 既定 / Status フロー / `Closes #N`）は
family 共通ポリシー。正典 → https://github.com/akira-toriyama/atelier/blob/main/docs/roadmap-board.md
