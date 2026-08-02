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

### Homebrew (recommended)

```bash
brew install konaito/tap/opttab
cp -R "$(brew --prefix opttab)/OptTab.app" ~/Applications/
open ~/Applications/OptTab.app
```

Built locally by Homebrew — no Gatekeeper quarantine.

### From source

```bash
git clone https://github.com/konaito/opttab.git
cd opttab
./Scripts/bundle.sh        # swift build + .app bundle + codesign → ~/Applications
open ~/Applications/OptTab.app
```

Requirements: macOS 14+, Xcode Command Line Tools.

First launch asks for **Accessibility** (required — the hotkey) and
**Screen Recording** (optional — thumbnails). OptTab lives in the menu bar;
enable *Launch at Login* from its menu.

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
git clone https://github.com/konaito/opttab.git
cd opttab
./Scripts/bundle.sh
open ~/Applications/OptTab.app
```

初回起動時に**アクセシビリティ**（必須・ホットキー用）と**画面収録**（任意・サムネイル用）の
許可を求められる。画面収録を許可しなくてもアイコン表示で動作する。
メニューバーの OptTab アイコンから「ログイン時に起動」を有効にできる。

### 操作

| キー | 動作 |
|---|---|
| `⌥` + `⇥` | HUD表示・順送り |
| `⌥` + `⇧` + `⇥` | 逆送り |
| `⌥` を離す | 選択ウィンドウへジャンプ |
| `esc` | キャンセル |
| 一瞬だけ押す | 直前のウィンドウへトグル |
