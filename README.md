# ⌥⇥ OptTab

**Option+Tab window switcher for macOS — for the windows `` Cmd+` `` can't reach.**

macOS's built-in same-app window switcher (`` Cmd+` ``) only cycles windows inside the
current Space. OptTab switches between windows of the **active app** across
**Spaces, fullscreen, and minimized** — with a thumbnail HUD that never steals focus.

🌐 **Landing page: https://konaito.github.io/opttab/**

[日本語READMEは下にあります](#日本語)

## Features

- **Crosses Spaces & fullscreen** — reaches every real window of the active app; macOS
  jumps to the right Space for you
- **Thumbnail HUD** — live previews via ScreenCaptureKit, shown on the display your
  cursor is on, non-activating (never steals focus)
- **Active app only** — `⌘Tab` switches apps, `⌥Tab` switches windows. Two keys, two jobs
- **Knows tabs aren't windows** — background native tabs (Ghostty, Terminal…) are
  filtered out; only actually-switchable windows appear
- **Public APIs only** — CGEventTap + ScreenCaptureKit + Accessibility. No private CGS
  calls, no injection
- **Graceful degradation** — works without Screen Recording permission (icon cards
  instead of thumbnails)
- **No menu bar icon** — runs as a launchd service, managed by `brew services`

## Keys

| Key | Action |
|---|---|
| `⌥` + `⇥` | open HUD / cycle forward |
| `⌥` + `⇧` + `⇥` | cycle backward |
| release `⌥` | switch to the selected window |
| `esc` | cancel |
| quick tap | toggle to the previous window |
| click a card | switch to that window |

## Install

```bash
brew install konaito/tap/opttab
brew services start opttab
```

**Upgrading from 0.1.0 or earlier?** Read [Migrating from the menu bar
app](#migrating) first — starting the new service while the old `.app` is
still running means both will fight over `⌥⇥`.

OptTab runs as a background service managed by launchd — no menu bar icon,
no dock icon. `brew services` handles start, stop, and launch-at-login.

On first start it asks for **Accessibility** (required — the hotkey).
Grant it in System Settings > Privacy & Security > Accessibility for
`$(brew --prefix)/var/opttab/opttab`. **Screen Recording** is optional;
without it the HUD shows icons instead of live thumbnails.

Check the service and both permissions at once:

```bash
opttab doctor
```

### Upgrading

```bash
brew upgrade opttab
brew services restart opttab
```

Permissions survive upgrades: the binary launchd runs lives at a
version-independent path (`$(brew --prefix)/var/opttab/opttab`), and macOS
keys TCC grants for non-bundled binaries by that path.

<a id="migrating"></a>
### Migrating from the menu bar app (≤ 0.1.0)

Remove the old one **before** installing the formula:

```bash
brew uninstall --cask opttab
```

Two reasons the order matters. The old `.app` and the new service both install
a CGEventTap and will fight over `⌥⇥`. And while the cask is still installed it
owns the name `opttab`, so the formula installs *without linking* and `opttab`
never lands on your `PATH`. If you already installed in the wrong order:

```bash
brew uninstall --cask opttab
brew link opttab
```

If **OptTab** still shows up in System Settings > General > Login Items,
remove it there too — the old app registered itself as a login item, and
uninstalling the cask doesn't clear that entry.

`opttab doctor` warns if it finds any leftovers.

### Uninstall

```bash
brew services stop opttab
brew uninstall opttab
rm -rf "$(brew --prefix)/var/opttab"
```

`brew uninstall opttab` alone leaves `$(brew --prefix)/var/opttab/` behind by
design — that's what preserves your Accessibility/Screen Recording grants
across a reinstall. Remove it only if you're done with OptTab for good, and
stop the service first or it stays loaded.

### From source

```bash
git clone https://github.com/konaito/opttab.git
cd opttab
./Scripts/install-local.sh
```

Requirements: macOS 14+, Xcode Command Line Tools.

## How it works

```
CGEventTap        ──▶ capture ⌥⇥ before apps see it; commit on ⌥ release
ScreenCaptureKit  ──▶ enumerate windows across all Spaces + thumbnails
Accessibility     ──▶ match CG ↔ AX windows ──▶ AXRaise the target
  └─ no AX handle? (other-Space Chromium…) ──▶ press its Window-menu item
```

Windows that have neither an AX handle nor a Window-menu item (background native
tabs) are unreachable by definition and excluded from the HUD.

## Development

```bash
swift build && swift test
```

Pure logic (ordering, state machine, key interpretation, CG↔AX matching) is unit
tested; system-facing code is kept in thin, isolated wrappers.

## License

[MIT](LICENSE)

---

## 日本語

**`` Cmd+` `` が届かないウィンドウのための Option+Tab ウィンドウスイッチャー。**

macOS標準の同一アプリ内ウィンドウ切り替え（`` Cmd+` ``）は同じSpace内しか巡回できない。
OptTabは**アクティブアプリのウィンドウ**を、**別Space・フルスクリーン・最小化**を含めて
サムネイルHUDで切り替える。

### インストール

```bash
brew install konaito/tap/opttab
brew services start opttab
```

**0.1.0以前からアップグレードする場合**: 先に[メニューバー版からの移行](#migrating-ja)
を読むこと。旧`.app`が起動したまま新サービスを入れると `⌥⇥` を奪い合う。

launchd常駐のバックグラウンドサービスとして動く。メニューバーアイコンもDockアイコンも
出さない。起動・停止・ログイン時起動は `brew services` が管理する。

初回起動時に**アクセシビリティ**（必須・ホットキー用）を求められる。
システム設定 > プライバシーとセキュリティ > アクセシビリティ で
`$(brew --prefix)/var/opttab/opttab` を許可する。
**画面収録**は任意で、許可しない場合はサムネイルの代わりにアイコンが表示される。

状態と権限はまとめて確認できる。

```bash
opttab doctor
```

### アップグレード

```bash
brew upgrade opttab
brew services restart opttab
```

権限はアップグレードをまたいで維持される。launchdが起動するバイナリは
バージョンに依存しない固定パス（`$(brew --prefix)/var/opttab/opttab`）にあり、
macOSは非バンドルバイナリのTCC許可をそのパスで識別するため。

<a id="migrating-ja"></a>
### メニューバー版（0.1.0以前）からの移行

formulaを入れる**前に**旧版を消すこと。

```bash
brew uninstall --cask opttab
```

順序が効く理由は2つある。旧`.app`と新サービスは両方ともCGEventTapを張るので `⌥⇥` を
奪い合う。加えて、caskがインストールされたままだとcaskが `opttab` という名前を保持する
ため、**formulaがリンクされず** `opttab` が `PATH` に載らない。逆順で入れてしまったら:

```bash
brew uninstall --cask opttab
brew link opttab
```

システム設定 > 一般 > ログイン項目に**OptTab**がまだ残っていたら、そこでも削除する
こと。旧版はログイン項目として自己登録しており、caskのアンインストールだけでは
消えない。

残骸があれば `opttab doctor` が警告する。

### アンインストール

```bash
brew services stop opttab
brew uninstall opttab
rm -rf "$(brew --prefix)/var/opttab"
```

`brew uninstall opttab` だけでは `$(brew --prefix)/var/opttab/` が意図的に残る。
これはアクセシビリティ・画面収録の許可を再インストールをまたいで維持するため。
完全に使わなくなる場合のみ削除すること。先にサービスを止めないと常駐したままになる。

### ソースから

```bash
git clone https://github.com/konaito/opttab.git
cd opttab
./Scripts/install-local.sh
```

### 操作

| キー | 動作 |
|---|---|
| `⌥` + `⇥` | HUD表示・順送り |
| `⌥` + `⇧` + `⇥` | 逆送り |
| `⌥` を離す | 選択ウィンドウへジャンプ |
| `esc` | キャンセル |
| 一瞬だけ押す | 直前のウィンドウへトグル |
