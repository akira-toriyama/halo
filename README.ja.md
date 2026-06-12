# halo

macOS のアクティブウィンドウにネオンの枠線を描くツール。フォーカス
されている窓に枠が張り付き、**ドラッグすると滑らかに追従**し
(window-server イベントを ~5ms で取得 — 遅い AX 経路ではない)、
**フォーカスが変わると光る（オプションでフォーカス窓が振動する）**ので、
今どの窓にいるか一目で分かる。

**facet** ファミリーの一員 —
[facet](https://github.com/akira-toriyama/facet) ウィンドウマネージャと
自然に併用できるが、facet には一切依存しない。(facet は最小構成の
ウィンドウマネージャを保ち、halo は独立した focused なツール ——
facet の「隣接機能は sibling repo に置く」決定に従う。)

[English README](README.md)

## 要件

- Apple Silicon, macOS 13+
- SIP は **有効のまま**で良い。リング自体は read-only (private SkyLight
  + クリック透過オーバーレイ)。オプションの **focus-shake** は AX で
  フォーカス窓を動かすので Accessibility が要る —— 付与するか、
  `shake = false` で権限不要のままにできる。

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

halo は `LSUIElement` agent (Dock アイコンなし・フォーカスを奪わない)。
リングは **権限不要**。**focus-shake** (既定 ON) はフォーカス窓を動かす
ため **Accessibility** が要る —— 初回起動時に System Settings → Privacy
& Security → Accessibility で halo を許可 (or `shake = false` で権限不要の
まま)。

## 設定

halo は `~/.config/halo/config.toml` を読む (任意 — 妥当なデフォルトが
ある)。テンプレートをコピーして編集:

```sh
mkdir -p ~/.config/halo
curl -fsSL https://raw.githubusercontent.com/akira-toriyama/halo/main/config.toml \
  -o ~/.config/halo/config.toml
```

キーは facet の `[border]` に揃えてある:

- `effect` — `off | neon | cyber | vapor | kawaii | rainbow | chomp | random`
  (リングに乗せるパレット。focus フラッシュはこれを点滅する。`chomp` は
  facet・wand と共有するアーケード effect —— 静止は青、点滅で
  pellet 黄 / ghost 赤)
- `glow`, `width`, `color` (`effect = off` 時の静止色)
- `cycle-seconds`, `cycle-colors` (rainbow 以外も自分のパレットを循環),
  `min-width` / `max-width` (両方指定で太さが呼吸する)
- `corner-radius`, `pad`, `min-size`, `exclude`
- `[shake]` — `shake` (focus-shake の on/off)・`shake-amplitude` (左右
  振幅 pt)・`shake-duration-ms`。フォーカス変化でフォーカス窓が一瞬
  左右に揺れて**厳密に元位置へ戻る** (位置のみ＝隣の窓は不変)。AX で
  窓を動かすので lazy-AX アプリ (Chrome, Calendar) は動かない。
- `[sound]` — `sound` (音声ファイルのパス。空 = OFF)・`sound-volume`
  (`0.0`–`1.0`)。フォーカス変化で短い効果音を鳴らす —— リングの
  フラッシュ・shake に続く 3 つ目の focus フィードバック。権限不要・
  音源は同梱しない (自前ファイルを指す)・latest-wins なので alt-tab
  連打でも音が積み重ならない。
- `[pets]` — `line-pets` (フォーカス窓のリングを**周回するアーケード
  スプライト**のリスト。例 `["chomp", "ghost"]`・空 `[]` = OFF)・
  `pet-scale`・`pet-lap-seconds`(窓を1周する秒数・窓サイズに依らず
  一定)。小さなペットがリングを追いかけ合って回る。opt-in・権限
  不要・theme 非依存 (各ペットのシルエットが自前の色)。sill の共有描画
  —— facet の tree・wand のカードにも同じペットが出る。

未知 / 不正なキーは無視されデフォルトのまま (タイポで壊れない)。編集は
**即時反映** —— halo が `config.toml` を ~0.4s でホットリロードする
(再起動不要)。

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
