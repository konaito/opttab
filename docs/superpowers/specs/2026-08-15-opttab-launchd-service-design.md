# OptTab: メニューバー常駐アプリ → launchd常駐サービス

2026-08-15

## 目的

OptTabをメニューバーから消し、Homebrewでインストールして `brew services` で
起動・停止する単体バイナリのバックグラウンドサービスにする。sleepwatcherと同じ
運用感にする。

満たすべき要件は4つ。

1. メニューバーアイコンを出さない（UIはHUDだけ）
2. `brew services start/stop opttab` で起動・停止・ログイン時起動を制御する
3. `.app` バンドルではなく `bin` に置く単体バイナリにする
4. GUIの設定面（権限確認・終了メニュー）を持たない

## 測定した制約: TCCは非バンドルバイナリを「実パス」で識別する

設計の形を決めているのはこの一点なので、先に書く。以下は推測ではなく、
2026-08-15にこのマシン（macOS 26.5.1）で実測した結果である。

`__TEXT,__info_plist` セクションに `CFBundleIdentifier` を埋め込み、
Developer ID Application + hardened runtime で署名した単体バイナリを
LaunchAgentから起動し、アクセシビリティを要求した。TCC.dbに載った行は次のとおり。

```
kTCCServiceAccessibility|…/Cellar/opttabspike/0.1.0/bin/opttabspike|1|2
                                                                   ↑client_type=1
```

`client_type=1` は「クライアントを絶対パスで識別する」を意味する
（`0` はbundle ID）。埋め込みInfo.plistがあっても、Developer ID署名があっても、
非バンドルバイナリは常にパスで識別される。さらにLaunchAgentの
`ProgramArguments` にはsymlinkパスを書いたにもかかわらず、記録されたのは
**symlink解決後の実パス**だった。

ここから3つの実測結果が出た。

| 操作 | 結果 |
|---|---|
| 同一パスでバイナリを差し替え、同じidentity・同じ signing identifier で再署名（cdhashは変化） | **権限は維持される** |
| バイナリを別パスへ移動（`0.1.0/` → `0.2.0/`） | **権限は失われる**。旧パスのエントリは `auth_value=2` のまま孤児化し、新パスは `auth_value=0` で再登録される |
| 埋め込みInfo.plistによるbundle ID識別 | 起きない。常に `client_type=1` |

この挙動は同じマシンの既存エントリでも裏が取れている。

```
kTCCServiceListenEvent|/opt/homebrew/Cellar/sleepwatcher/2.2.1/sbin/sleepwatcher|1|2
kTCCServiceSystemPolicyAllFiles|…/uv/python/cpython-3.14.2-macos-aarch64-none/bin/python3.14|1|0
```

sleepwatcher自身がバージョン番号入りのCellar実パスで登録されている。
`brew upgrade` でCellarのバージョンディレクトリが変わればこのエントリは孤児になる。
sleepwatcherはTCC権限を必要としないので誰も困らないが、OptTabは
アクセシビリティ（CGEventTap）と画面収録（ScreenCaptureKit）を使う。

**結論: 実行されるバイナリをCellar直下に置くことはできない。**
バージョンに依存しない固定パスに実体を置き、launchdはそこを起動する。

## 設計

### バイナリ形態

`.app` バンドルを廃止し、単体のMach-O実行ファイルにする。
`Info.plist` は `Support/Info.plist` に置き、SwiftPMの `linkerSettings` で
`-sectcreate __TEXT __info_plist` によりバイナリへ埋め込む。

TCCの識別には効かないことが分かったが、`NSHighResolutionCapable` は
HUDのRetina描画に必要なので埋め込みは維持する。`CFBundleIdentifier` は
`NSApplication` およびログ表示の識別子として引き続き意味がある。

`main.swift` の `setActivationPolicy(.accessory)` はそのまま。HUDはAquaセッション上の
`NSPanel` として描画される。sudo無しの `brew services` が作るのはユーザードメインの
LaunchAgent（`LimitLoadToSessionType: Aqua`）なので、この描画は成立する。
実測でも、LaunchAgentから起動したプロセスがステータスアイテムとHUDの両方を
描画できることを確認済み。

### 配置

```
$(brew --prefix)/Cellar/opttab/<version>/bin/opttab   formulaのインストール先
$(brew --prefix)/bin/opttab                            CLI用symlink（doctor等）
$(brew --prefix)/var/opttab/opttab                     ★launchdが起動する実体。TCCの鍵
```

`var` はHomebrewがバージョンをまたいで保持するディレクトリなので、
`brew upgrade` でもパスが変わらない。formulaの `postinstall` で
Cellarから `var/opttab/opttab` へコピーする。

コピーは必ず `rm -f` してから `cp` する。実行中のMach-Oへ直接 `cp` すると
`ETXTBSY` で失敗する。`rm` + `cp` はinodeが変わるがパスは同じなので、
TCCの鍵はパスである以上、権限は維持される（実測済み）。

### launchd / brew services

formulaに `service` ブロックを置く。

```ruby
service do
  run var/"opttab"/"opttab"
  keep_alive true
  log_path var/"log/opttab.log"
  error_log_path var/"log/opttab.log"
end
```

`brew services start opttab` が `~/Library/LaunchAgents/homebrew.mxcl.opttab.plist`
を生成し、ログイン時起動もlaunchdが担う。アプリ側の `SMAppService` による
ログイン項目登録は削除する（二重管理になるため）。

### CLI

GUIの設定面を持たない代わりに、最小限のサブコマンドを持つ。

```
opttab            引数なし = デーモン本体として常駐する（launchdが呼ぶ形）
opttab --version  バージョンを出力して終了
opttab doctor     サービスの状態と権限を出力して終了
```

**`doctor` は自プロセスの権限を見てはならない。** `AXIsProcessTrusted()` は
呼び出したプロセスについて答える。ターミナルから `opttab doctor` を実行すると
ターミナル（ghostty等）の権限が返るため、デーモンが未許可でも「許可済み」と
報告してしまう。権限の有無が問われるのは
`$(brew --prefix)/var/opttab/opttab` として動いているデーモンだけである。

そこで、デーモンが自分の権限状態を状態ファイルへ書き、`doctor` はそれを読む。

- 状態ファイル: `$(brew --prefix)/var/opttab/status.json`
- デーモンは起動時と権限状態の変化時に書く（既存の3秒リトライタイマーに相乗り）
- 内容: `{"pid", "version", "executablePath", "accessibility", "screenRecording", "updatedAt"}`
- `doctor` は状態ファイル + `launchctl print gui/<uid>/homebrew.mxcl.opttab` の
  実行状態を突き合わせて出力する
- 状態ファイルが無い / 古い場合は「サービスが起動していない」と報告する

TCC.dbを直接読む方法は採らない。読むにはターミナル側にフルディスクアクセスが必要で、
一般ユーザーの環境では成立しない。

`doctor` は権限が欠けている場合、該当する設定パネルを開くURLを併せて表示する
（自動で開かない。CLIから勝手にGUIを開かない）。

### 権限の初回付与フロー

1. `brew install opttab` → `brew services start opttab`
2. デーモンが起動し、アクセシビリティ未許可なら `AXIsProcessTrustedWithOptions`
   でシステムのダイアログを出す（Aquaセッションなので表示される）
3. ユーザーが システム設定 → プライバシーとセキュリティ → アクセシビリティ で
   `opttab` をONにする
4. デーモンは3秒ごとに再試行しており、許可された時点でイベントタップを開始する
   （既存の `AppDelegate` のリトライ機構をそのまま使う）
5. 画面収録は未許可でも動く（サムネイル無しの縮退運転）。`CGRequestScreenCaptureAccess`
   がTCCエントリを作るので、システム設定のリストには現れる

formulaの `caveats` にこの手順を書く。

### 移行

既存ユーザーは公証済みcaskで `/Applications/OptTab.app` を使っている。
新旧が同時に走ると **2つのCGEventTapが ⌥⇥ を奪い合う**ので、明示的に潰す。

移行手順（`caveats` と README に記載）:

```bash
brew services stop opttab      # 念のため
brew uninstall --cask opttab   # 旧 .app を削除
```

加えて `opttab doctor` が以下を検出して警告を出す。

- `/Applications/OptTab.app` または `~/Applications/OptTab.app` が存在する
- `~/Library/LaunchAgents/dev.konaito.opttab.plist` が存在する
  （このマシンで検証用に手で作ったもの。`homebrew.mxcl.opttab.plist` と
  二重起動になる）
- `OptTab.app` のプロセスが動いている

検出時は削除コマンドを表示するだけにする。`postinstall` から他所のファイルを
消すのは越権なので行わない。

### 配布

公証済みcaskは廃止する。`.app` とバイナリの二本立ては二重起動事故を招くため、
インストール経路を1つに絞る。

- `Scripts/notarize-release.sh` を、`.app` ではなく単体バイナリを
  Developer ID + hardened runtime で署名し、公証してGitHub Releaseへ上げる形に書き換える
  - 単体Mach-Oには `stapler staple` できない。Homebrewの `curl` は
    quarantine属性を付けないため、Gatekeeperの実行時検証には引っかからない
  - 公証は「配布物が改竄されていないことの担保」として維持する
- `Scripts/bundle.sh` は `.app` を作る役目を終える。ローカル開発用に
  「ビルド → `var/opttab/opttab` へ配置 → エージェント再起動」を行う
  `Scripts/install-local.sh` へ置き換える
- konaito/homebrew-tap 側で cask を削除し、prebuiltバイナリを取得する
  formula に差し替える（**別リポジトリなので独立した作業として扱う**）

### アーキテクチャ

現状のリリースビルドはarm64単独。formulaで配る以上、Intel Macで壊れる。
`notarize-release.sh` で `swift build --arch arm64 --arch x86_64` により
universalバイナリを作る。universal化が難しい場合は formula に
`depends_on arch: :arm64` を書いて明示的にarm64専用とする。どちらを採るかは
ビルドを通してから判断する。

### ドキュメント

- `README.md`（英語・日本語の両方）: インストール手順、メニューバーへの言及、
  「ログイン時に起動」の説明を差し替える
- `docs/index.html`: LPのインストールコマンドが `brew install --cask` のままなので直す
- 上記tapリポジトリの更新

## 非目標

- `.app` バンドルの維持
- GUIの設定画面
- システムドメインのLaunchDaemon化（HUDの描画にAquaセッションが要るため不可能）
- 既存のホットキー・ウィンドウ列挙・HUD描画のロジック変更

## 検証

Phase 0で以下は実測済み。

- 単体バイナリでアクセシビリティ・画面収録の両方を取得できる
- 同一パスでのバイナリ差し替えで両権限が維持される
- パス変更で権限が失われる
- LaunchAgentから起動したプロセスがHUDを描画でき、Retinaで、
  別Space・フルスクリーンのウィンドウも列挙できる

実装フェーズで確認すること。

- `swift test` の既存46テストが通る（ロジックには触れないので通るはず）
- `brew install --build-from-source` ではなくprebuilt取得のformulaがローカルtapで動く
- `brew services start/stop/restart opttab` が期待どおり動く
- **`brew upgrade` がサービスを再起動するか**。再起動しない場合、削除済みinodeの
  古いバイナリが動き続けるので、`caveats` に `brew services restart opttab` を明記する。
  これは推測せず実際に確かめる
- `opttab doctor` が、デーモン停止中・権限未許可・旧`.app`残存の各ケースで
  正しく報告する
