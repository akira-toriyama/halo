# halo

macOS のアクティブウィンドウにネオンの枠線を描くツール。フォーカス
されている窓に枠が張り付き、**ドラッグすると滑らかに追従**し
(window-server イベントを ~5ms で取得 — 遅い AX 経路ではない)、
**フォーカスが変わると光る**ので、今どの窓にいるか一目で分かる。

**facet** ファミリーの一員 —
[facet](https://github.com/akira-toriyama/facet) ウィンドウマネージャと
自然に併用できるが、facet には一切依存しない。(facet は最小構成の
ウィンドウマネージャを保ち、halo は独立した focused なツール ——
facet の「隣接機能は sibling repo に置く」決定に従う。)

[English README](README.md)

## 要件

- Apple Silicon, macOS 13+
- SIP は **有効のまま**で良い。halo は window server を *観測* するだけ
  (read-only な private SkyLight) で、透明なオーバーレイを描くだけ ——
  窓を動かしたり触ったりは一切しない。

## インストール

**Homebrew (ソースからビルド):**

```sh
brew install akira-toriyama/tap/halo
open "$(brew --prefix)/opt/halo/Halo.app"
```

**ビルド済み (`Halo.zip` — [Releases](https://github.com/akira-toriyama/halo/releases)):**
ad-hoc 署名 (公証なし) なので、ダウンロード時に macOS が隔離する。
`/Applications` に展開した後:

```sh
xattr -dr com.apple.quarantine /Applications/Halo.app
open /Applications/Halo.app
```

halo は `LSUIElement` agent (Dock アイコンなし・フォーカスを奪わない)
で、**権限は一切不要** —— read-only な private SkyLight で窓の座標を
読み、クリックを透過するオーバーレイを描くだけ。起動すればそれで動く。

## 設定

halo は `~/.config/halo/config.toml` を読む (任意 — 妥当なデフォルトが
ある)。テンプレートをコピーして編集:

```sh
mkdir -p ~/.config/halo
curl -fsSL https://raw.githubusercontent.com/akira-toriyama/halo/main/config.toml \
  -o ~/.config/halo/config.toml
```

キーは facet の `[border]` に揃えてある:

- `effect` — `off | neon | cyber | vapor | kawaii | rainbow | random`
  (リングに乗せるパレット。focus フラッシュはこれを点滅する)
- `glow`, `width`, `color` (`effect = off` 時の静止色)
- `cycle-seconds`, `cycle-colors` (rainbow 以外も自分のパレットを循環),
  `min-width` / `max-width` (両方指定で太さが呼吸する)
- `corner-radius`, `pad`, `min-size`, `exclude`

未知 / 不正なキーは無視されデフォルトのまま (タイポで壊れない)。

## ビルド / 実行 (開発)

デプロイフローは facet に揃えてある: `package.sh` が `Halo.app` を
組み立て、`run.sh` がビルド + 再起動、リリースは GitHub の rolling
draft、publish で Homebrew が自動更新される。

```sh
./run.sh          # release ビルド → Halo.app 組み立て → 再起動 (HALO_DEBUG on → /tmp/halo.log)
./stop.sh         # 起動中の halo を全部停止 (bundle / 生バイナリ両方)
./package.sh      # Halo.app の組み立てだけ (ad-hoc 署名)

swift build -c release && .build/release/halo &   # bundle なしの生バイナリ
```

halo は TCC 権限を一切使わないので、facet と違って自己署名証明書の
手順も dev/release のバンドル分割も無い —— ad-hoc 署名で十分。コミットは
facet ファミリーの gitmoji + Conventional Commits 規約
(`git config core.hooksPath scripts/hooks`; 詳細は
[docs/commit-convention.md](docs/commit-convention.md))。

## 仕組み

専用の SkyLight 接続が window の MOVE / RESIZE / フォーカス変化イベントを
購読し、main run loop で drain する。この**専用接続が肝**：AppKit
アプリはプロセスの main SkyLight 接続ではこれらを受け取れない
(AppKit が握っているため)。これが AX ベースの手法が「ワンテンポ遅い」
と感じる罠の正体。詳細は `Sources/Halo/WindowServerEvents.swift`。
