# OptTab 設計ドキュメント

日付: 2026-08-02
ステータス: 承認待ち

## 目的

macOSで `Option+Tab` により、**アクティブなアプリのウィンドウ**をサムネイル付きHUDで切り替える。
macOS標準の `Cmd+\`` は同一Space内のウィンドウにしか届かないため、**別Space・フルスクリーン・最小化中のウィンドウも対象にする**ことが本ツールの存在理由。

きっかけ: Dia browserがプロファイル切り替えをウィンドウ内で行う仕様になり、別Spaceに分かれた2枚のDiaウィンドウを行き来する手段がなくなった。

## 成功条件

- Dia/Chromeの2ウィンドウが別Space（フルスクリーン含む）にあっても、Option+Tab一発で行き来できる
- Option押しっぱなし→Tab連打で順送り、離した瞬間に確定してジャンプ
- 1回押してすぐ離すと「直前のウィンドウ」にトグル（Cmd+Tabと同じメンタルモデル）
- Diaのタブスイッチャー風のサムネイル付きカードUI

## スコープ

- 対象: **アクティブアプリのウィンドウのみ**（アプリ間切り替えは標準のCmd+Tabに任せる）
- 形態: **メニューバー常駐アプリ**（Dockアイコンなし・LSUIElement、メニューバーにアイコンとQuit/Launch at Loginメニュー）
- 配布: 自分用。ad-hoc署名、`~/Applications` に配置
- 対象OS: macOS 26（Tahoe）。ScreenCaptureKit / SCScreenshotManager前提（macOS 14+ API）

### やらないこと（YAGNI）

- 全アプリ横断のウィンドウ一覧（Windows風Alt+Tab）
- 私有API（CGS*）の使用。公開APIのみ。物足りなくなったら後から個別に検討
- 設定UI。挙動は固定（必要になったらdefaultsキーで追加）

## アーキテクチャ

Swift Package（executable target）→ ビルドスクリプトで .app バンドル化。

```
OptTab.app (LSUIElement)
├── AppDelegate / MenuBarController   … 常駐・メニュー・権限チェック
├── HotkeyMonitor                     … CGEventTap
├── SwitcherController                … 状態機械（発動→巡回→確定/キャンセル）
├── WindowProvider                    … ウィンドウ列挙（SCK + AX）
├── ThumbnailService                  … SCScreenshotManagerでスクショ＋キャッシュ
├── SwitcherPanel                     … 非アクティブ化NSPanel + SwiftUIカードUI
└── FocusService                      … AXRaise + activateでジャンプ
```

### HotkeyMonitor

- `CGEventTap`（session tap, headInsertEventTap）で `keyDown` / `flagsChanged` を監視
- Option修飾付きTab keyDownを**横取り**（イベントをシステムに流さず consume）
- Option+Tab = 順送り / Option+Shift+Tab = 逆送り / Esc = キャンセル
- `flagsChanged` でOptionの解放を検知 → 確定
- OSによるtap無効化（タイムアウト）を検知したら自動再有効化

### WindowProvider

- 発動時に `NSWorkspace.frontmostApplication` のPIDを取得
- `SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)` で全Spaceのウィンドウを列挙し、対象PIDでフィルタ
- AX API（`AXUIElementCopyAttributeValue` の `kAXWindowsAttribute`）と突き合わせ、最小化ウィンドウも含める
- 除外: タイトル空かつ極小のウィンドウ（ツールチップ・パネル類）。レイヤー0のみ
- 並び順: 現在のウィンドウが先頭、以降は前面順。**初期選択は2番目**（=直前のウィンドウ）

### ThumbnailService

- `SCScreenshotManager.captureImage(contentFilter:configuration:)` でウィンドウ単位のスクショ
- HUD表示は即時（プレースホルダ=アプリアイコン）、スクショは非同期で差し込み
- 取得失敗（別Spaceで内容が取れない等）は**アプリアイコン＋タイトルのカードにフォールバック**
- 直近のサムネイルをメモリキャッシュし、次回発動時は古い画像を先に出して裏で更新

### SwitcherPanel

- `NSPanel`（`.nonactivatingPanel`）+ SwiftUI。**キーフォーカスを奪わない**（奪うと「アクティブアプリ」が変わり列挙が壊れる）
- 画面中央（マウスのあるスクリーン）にカード横並び、選択中カードをハイライト
- カード: サムネイル（or アイコン）＋ウィンドウタイトル1行
- マウスクリックでも選択確定できる

### FocusService

- 最小化中なら `AXMinimized = false` で復元
- `AXRaise` アクション + `NSRunningApplication.activate()` でジャンプ
- 別Space/フルスクリーンのウィンドウはmacOSが自動でSpaceを切り替える

## データフロー

1. Option+Tab検知 → 最前面アプリのウィンドウをスナップショット取得
2. ウィンドウ2枚未満なら何もしない（HUDも出さない）
3. HUD表示、選択=2番目。Tab/Shift+Tabで巡回
4. Option解放 → HUD閉じる → FocusServiceで選択ウィンドウへ
5. Esc → HUD閉じるだけ

## 権限とエラー処理

- 必要権限: **アクセシビリティ**（event tap・AXRaise）と**画面収録**（サムネイル）
- 起動時にチェックし、未許可なら該当のシステム設定ペインをdeep linkで開いて案内
- 画面収録が未許可でもサムネイル無し（アイコンカード）で動作は継続する（縮退運転）
- event tap再有効化、SCK呼び出し失敗時はアイコンフォールバック

## テスト

- `SwitcherState`（巡回・確定・キャンセルの状態機械）と ウィンドウ並び替えロジックを純粋なSwiftに切り出し、`swift test` でユニットテスト
- 手動テストマトリクス: {同一Space, 別Space, フルスクリーン, 最小化} × {Dia, Chrome, Finder}
- ローカル検証必須: `swift build` と `swift test` をpush前に必ず実行

## ビルド・運用

- `swift build -c release` → `Scripts/bundle.sh` で .app 生成（Info.plist: LSUIElement=true）→ ad-hoc `codesign` → `~/Applications/OptTab.app`
- ログイン時自動起動: `SMAppService.mainApp`（メニューからトグル）
- リポジトリ: `~/dev/opttab`

## 既知のリスク

- 別Spaceのウィンドウはサムネイルが取れない/古い場合がある → アイコンフォールバックで許容（用途上ウィンドウ数は2〜3枚で、タイトルで判別可能）
- Option+Tabを常用するアプリ（一部ターミナル・IDE）ではその機能を上書きする → 必要になったら除外アプリリストを追加
- Electron系など一部アプリはAXRaiseの挙動に癖がある → テストマトリクスで確認
