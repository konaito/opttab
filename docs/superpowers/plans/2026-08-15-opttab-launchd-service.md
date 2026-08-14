# OptTab launchd常駐サービス化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** OptTabをメニューバー常駐の`.app`から、`brew services`で管理するlaunchd常駐の単体バイナリへ移行する。

**Architecture:** `.app`バンドルを廃止し、Info.plistを`__TEXT,__info_plist`セクションへ埋め込んだuniversal単体バイナリにする。TCCが非バンドルバイナリを実パスで識別するため、launchdが起動する実体は`$(brew --prefix)/var/opttab/opttab`という**バージョン非依存の固定パス**に置き、formulaの`postinstall`がCellarからそこへコピーする。デーモンは自分の権限状態を`status.json`へ5秒ごとに書き、`opttab doctor`はそれを読んで報告する（doctor自身の権限を見ても呼び出し元ターミナルの権限が返るため意味がない）。

**Tech Stack:** Swift 5.10 / SwiftPM / AppKit / ApplicationServices / ScreenCaptureKit / launchd / Homebrew formula

**Spec:** `docs/superpowers/specs/2026-08-15-opttab-launchd-service-design.md`

## Global Constraints

- macOS 14.0 以上（`Package.swift` の `platforms: [.macOS(.v14)]`、Info.plist の `LSMinimumSystemVersion` = `14.0`）
- Swift tools version 5.10
- 外部依存パッケージを追加しない（現状ゼロ依存を維持する）
- バンドルID: `dev.konaito.opttab`
- 署名: `Developer ID Application: KOUTA NAITOU (T79674CM55)`、`--options runtime`、`-i dev.konaito.opttab`
- **署名の signing identifier を変えてはならない。** 変えるとTCCのcsreq検証に落ちて既存ユーザーの権限が飛ぶ
- launchdが起動する実体のパスは `$(brew --prefix)/var/opttab/opttab` 固定。**このパスを変えてはならない**（TCCの識別キーそのもの）
- universalビルドの成果物パスは `.build/apple/Products/Release/OptTab`（`swift build -c release --arch arm64 --arch x86_64` 使用時）。通常の `.build/release/OptTab` ではない
- 純ロジックはユニットテストする。システムに触る部分は薄いラッパへ隔離する（このリポジトリの既存方針）
- ユーザー向け文言は英語（README英語節・formula caveats）と日本語（README日本語節）の両方を更新する

---

### Task 1: CLI引数パースと `--version` / `--help`

デーモン本体・`--version`・`doctor` を1つのバイナリで分岐させる入口を作る。
`doctor` の中身はTask 5で実装するので、ここでは分岐だけ通す。

**Files:**
- Create: `Sources/OptTabCore/CLICommand.swift`
- Create: `Sources/OptTabCore/OptTabVersion.swift`
- Modify: `Sources/OptTab/main.swift`
- Test: `Tests/OptTabCoreTests/CLICommandTests.swift`

**Interfaces:**
- Consumes: なし
- Produces:
  - `public enum CLICommand: Equatable { case daemon, version, doctor, help, unknown(String) }`
  - `public static func CLICommand.parse(_ arguments: [String]) -> CLICommand` — 引数はプログラム名を除いたもの
  - `public static let CLICommand.helpText: String`
  - `public enum OptTabVersion { public static var current: String }`

- [ ] **Step 1: Write the failing test**

`Tests/OptTabCoreTests/CLICommandTests.swift`:

```swift
import XCTest
@testable import OptTabCore

final class CLICommandTests: XCTestCase {
    // 引数なし = デーモンとして常駐する
    func testNoArgumentsIsDaemon() {
        XCTAssertEqual(CLICommand.parse([]), .daemon)
    }

    func testVersionFlag() {
        XCTAssertEqual(CLICommand.parse(["--version"]), .version)
        XCTAssertEqual(CLICommand.parse(["-v"]), .version)
    }

    func testHelpFlag() {
        XCTAssertEqual(CLICommand.parse(["--help"]), .help)
        XCTAssertEqual(CLICommand.parse(["-h"]), .help)
    }

    func testDoctorSubcommand() {
        XCTAssertEqual(CLICommand.parse(["doctor"]), .doctor)
    }

    // 未知の引数は unknown。デーモンとして起動してしまわないこと
    func testUnknownArgument() {
        XCTAssertEqual(CLICommand.parse(["--bogus"]), .unknown("--bogus"))
        XCTAssertEqual(CLICommand.parse(["status"]), .unknown("status"))
    }

    // 余分な引数は最初のものだけ見る（launchdはProgramArgumentsを1つしか渡さない）
    func testFirstArgumentWins() {
        XCTAssertEqual(CLICommand.parse(["doctor", "--version"]), .doctor)
    }

    func testHelpTextMentionsEverySubcommand() {
        let text = CLICommand.helpText
        XCTAssertTrue(text.contains("doctor"))
        XCTAssertTrue(text.contains("--version"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CLICommandTests`
Expected: FAIL — `cannot find 'CLICommand' in scope`

- [ ] **Step 3: Write minimal implementation**

`Sources/OptTabCore/CLICommand.swift`:

```swift
import Foundation

/// バイナリ1つでデーモン本体とCLIサブコマンドを兼ねるための引数解釈。
public enum CLICommand: Equatable {
    /// 引数なし。launchdから起動される常駐モード。
    case daemon
    case version
    case doctor
    case help
    case unknown(String)

    /// プログラム名を除いた引数列を解釈する。
    public static func parse(_ arguments: [String]) -> CLICommand {
        guard let first = arguments.first else { return .daemon }
        switch first {
        case "--version", "-v": return .version
        case "--help", "-h": return .help
        case "doctor": return .doctor
        default: return .unknown(first)
        }
    }

    public static let helpText = """
        opttab — Option+Tab window switcher for macOS

        usage:
          opttab              run as the background service (launchd invokes this)
          opttab doctor       report service state and permissions
          opttab --version    print version
          opttab --help       print this help

        The service is managed by Homebrew:
          brew services start opttab
          brew services stop opttab
          brew services restart opttab
        """
}
```

`Sources/OptTabCore/OptTabVersion.swift`:

```swift
import Foundation

public enum OptTabVersion {
    /// バイナリの __TEXT,__info_plist セクションに埋め込んだ
    /// CFBundleShortVersionString を読む。
    public static var current: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
            ?? "unknown"
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter CLICommandTests`
Expected: PASS（7テスト）

- [ ] **Step 5: main.swift を分岐させる**

`Sources/OptTab/main.swift` を全置換:

```swift
import AppKit
import Foundation
import OptTabCore

switch CLICommand.parse(Array(CommandLine.arguments.dropFirst())) {
case .version:
    print(OptTabVersion.current)

case .help:
    print(CLICommand.helpText)

case .doctor:
    // Task 5 で Doctor.run() に差し替える
    print(CLICommand.helpText)

case .unknown(let argument):
    FileHandle.standardError.write(
        Data("opttab: unknown argument '\(argument)'\n".utf8))
    FileHandle.standardError.write(Data((CLICommand.helpText + "\n").utf8))
    exit(2)

case .daemon:
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
```

- [ ] **Step 6: ビルドと `--version` の動作確認**

```bash
swift build -c release
.build/release/OptTab --version
.build/release/OptTab --help
.build/release/OptTab --bogus; echo "exit=$?"
```

Expected: `--version` は `0.2.0`（`Support/Info.plist` の値）を出力。`--help` は使用法を出力。`--bogus` は `exit=2`。
いずれの場合もHUDやメニューバーが出ず即座に終了すること。

- [ ] **Step 7: Commit**

```bash
git add Sources/OptTabCore/CLICommand.swift Sources/OptTabCore/OptTabVersion.swift \
        Sources/OptTab/main.swift Tests/OptTabCoreTests/CLICommandTests.swift
git commit -m "feat: CLI引数パースを追加し、--version/--help/doctorを分岐させる"
```

---

### Task 2: デーモン状態ファイルの表現とパス解決

デーモンが自分の権限状態を書き出すためのモデルと、その置き場所を決める純ロジック。
書き込み・読み込みの実行はTask 3とTask 5で行う。

**Files:**
- Create: `Sources/OptTabCore/DaemonStatus.swift`
- Test: `Tests/OptTabCoreTests/DaemonStatusTests.swift`

**Interfaces:**
- Consumes: なし
- Produces:
  - `public struct DaemonStatus: Codable, Equatable { public let pid: Int32; public let version: String; public let executablePath: String; public let accessibility: Bool; public let screenRecording: Bool; public let updatedAt: Date }`
  - `public init(pid: Int32, version: String, executablePath: String, accessibility: Bool, screenRecording: Bool, updatedAt: Date)`
  - `public static func DaemonStatus.encode(_ status: DaemonStatus) throws -> Data`
  - `public static func DaemonStatus.decode(_ data: Data) throws -> DaemonStatus`
  - `public static func DaemonStatus.isFresh(_ status: DaemonStatus, now: Date, tolerance: TimeInterval) -> Bool`
  - `public enum StatusFile { public static func path(forExecutable executablePath: String) -> String; public static func candidatePaths(prefixes: [String]) -> [String]; public static let defaultPrefixes: [String] }`

- [ ] **Step 1: Write the failing test**

`Tests/OptTabCoreTests/DaemonStatusTests.swift`:

```swift
import XCTest
@testable import OptTabCore

final class DaemonStatusTests: XCTestCase {
    private func status(updatedAt: Date = Date(timeIntervalSince1970: 1_000_000),
                        accessibility: Bool = true,
                        screenRecording: Bool = true) -> DaemonStatus {
        DaemonStatus(pid: 4242,
                     version: "0.2.0",
                     executablePath: "/opt/homebrew/var/opttab/opttab",
                     accessibility: accessibility,
                     screenRecording: screenRecording,
                     updatedAt: updatedAt)
    }

    // JSONを往復しても内容が変わらない
    func testRoundTrip() throws {
        let original = status()
        let decoded = try DaemonStatus.decode(try DaemonStatus.encode(original))
        XCTAssertEqual(decoded, original)
    }

    // doctorが人の目で読めるよう、キーがそのままJSONに出ていること
    func testEncodedJSONContainsKeys() throws {
        let json = String(decoding: try DaemonStatus.encode(status()), as: UTF8.self)
        XCTAssertTrue(json.contains("\"accessibility\""))
        XCTAssertTrue(json.contains("\"screenRecording\""))
        XCTAssertTrue(json.contains("\"executablePath\""))
    }

    // 壊れたJSONはthrowする（doctorが「サービス停止中」と扱えるように）
    func testDecodeGarbageThrows() {
        XCTAssertThrowsError(try DaemonStatus.decode(Data("not json".utf8)))
    }

    // 5秒ハートビートに対し許容30秒。範囲内なら生きている
    func testFreshWithinTolerance() {
        let now = Date(timeIntervalSince1970: 1_000_020)
        XCTAssertTrue(DaemonStatus.isFresh(status(), now: now, tolerance: 30))
    }

    func testStaleBeyondTolerance() {
        let now = Date(timeIntervalSince1970: 1_000_031)
        XCTAssertFalse(DaemonStatus.isFresh(status(), now: now, tolerance: 30))
    }

    // 時計が巻き戻ってもstale扱いにしない（未来の更新時刻を許容する）
    func testFutureTimestampIsFresh() {
        let now = Date(timeIntervalSince1970: 999_990)
        XCTAssertTrue(DaemonStatus.isFresh(status(), now: now, tolerance: 30))
    }

    // 状態ファイルは実行ファイルと同じディレクトリに置く。
    // launchdが起動するのは <prefix>/var/opttab/opttab なので隣に status.json ができる
    func testStatusFilePathIsSiblingOfExecutable() {
        XCTAssertEqual(
            StatusFile.path(forExecutable: "/opt/homebrew/var/opttab/opttab"),
            "/opt/homebrew/var/opttab/status.json")
    }

    func testStatusFilePathHandlesUsrLocal() {
        XCTAssertEqual(
            StatusFile.path(forExecutable: "/usr/local/var/opttab/opttab"),
            "/usr/local/var/opttab/status.json")
    }

    // doctorはCellar経由で実行されるため自分の位置からvarを導けない。
    // 既知のprefix候補を順に見る
    func testCandidatePaths() {
        XCTAssertEqual(
            StatusFile.candidatePaths(prefixes: ["/opt/homebrew", "/usr/local"]),
            ["/opt/homebrew/var/opttab/status.json",
             "/usr/local/var/opttab/status.json"])
    }

    func testDefaultPrefixesCoverBothArchitectures() {
        XCTAssertTrue(StatusFile.defaultPrefixes.contains("/opt/homebrew"))
        XCTAssertTrue(StatusFile.defaultPrefixes.contains("/usr/local"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter DaemonStatusTests`
Expected: FAIL — `cannot find 'DaemonStatus' in scope`

- [ ] **Step 3: Write minimal implementation**

`Sources/OptTabCore/DaemonStatus.swift`:

```swift
import Foundation

/// 常駐しているデーモンが自分の状態を書き出すためのモデル。
///
/// `opttab doctor` が自プロセスで `AXIsProcessTrusted()` を呼んでも、
/// 答えるのは呼び出し元のターミナルについてであってデーモンについてではない。
/// 権限の有無が問われるのは固定パスで動いているデーモンだけなので、
/// デーモン自身に書かせて doctor はそれを読む。
public struct DaemonStatus: Codable, Equatable {
    public let pid: Int32
    public let version: String
    public let executablePath: String
    public let accessibility: Bool
    public let screenRecording: Bool
    public let updatedAt: Date

    public init(pid: Int32,
                version: String,
                executablePath: String,
                accessibility: Bool,
                screenRecording: Bool,
                updatedAt: Date) {
        self.pid = pid
        self.version = version
        self.executablePath = executablePath
        self.accessibility = accessibility
        self.screenRecording = screenRecording
        self.updatedAt = updatedAt
    }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    public static func encode(_ status: DaemonStatus) throws -> Data {
        try encoder.encode(status)
    }

    public static func decode(_ data: Data) throws -> DaemonStatus {
        try decoder.decode(DaemonStatus.self, from: data)
    }

    /// デーモンは5秒ごとに書き直す。許容を超えて古ければ死んでいるとみなす。
    /// 時計の巻き戻りで誤判定しないよう、未来の時刻は常に新鮮扱いにする。
    public static func isFresh(_ status: DaemonStatus,
                               now: Date,
                               tolerance: TimeInterval) -> Bool {
        now.timeIntervalSince(status.updatedAt) <= tolerance
    }
}

public enum StatusFile {
    public static let fileName = "status.json"

    /// 実行ファイルの隣に置く。launchdが起動するのは
    /// <prefix>/var/opttab/opttab なので <prefix>/var/opttab/status.json になる。
    public static func path(forExecutable executablePath: String) -> String {
        (executablePath as NSString).deletingLastPathComponent
            + "/" + fileName
    }

    /// doctorはCellar以下から実行されるので自分の位置からvarを導けない。
    /// 既知のHomebrew prefixを順に探す。
    public static func candidatePaths(prefixes: [String]) -> [String] {
        prefixes.map { "\($0)/var/opttab/\(fileName)" }
    }

    /// Apple Silicon と Intel の標準prefix。
    public static let defaultPrefixes = ["/opt/homebrew", "/usr/local"]
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter DaemonStatusTests`
Expected: PASS（10テスト）

- [ ] **Step 5: Commit**

```bash
git add Sources/OptTabCore/DaemonStatus.swift Tests/OptTabCoreTests/DaemonStatusTests.swift
git commit -m "feat: デーモン状態ファイルのモデルとパス解決を追加"
```

---

### Task 3: デーモンが状態ファイルを書く

Task 2のモデルを実際にディスクへ書く。5秒ごとのハートビート。

**Files:**
- Create: `Sources/OptTabCore/StatusWriter.swift`
- Modify: `Sources/OptTabCore/AppDelegate.swift`
- Test: `Tests/OptTabCoreTests/StatusWriterTests.swift`

**Interfaces:**
- Consumes: `DaemonStatus`, `StatusFile`, `OptTabVersion`, `Permissions`
- Produces:
  - `public struct StatusWriter { public init(path: String); public func write(_ status: DaemonStatus) throws; public static func currentStatus(executablePath: String, now: Date) -> DaemonStatus }`

- [ ] **Step 1: Write the failing test**

`Tests/OptTabCoreTests/StatusWriterTests.swift`:

```swift
import XCTest
@testable import OptTabCore

final class StatusWriterTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("opttab-statuswriter-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func sample() -> DaemonStatus {
        DaemonStatus(pid: 99,
                     version: "0.2.0",
                     executablePath: "/opt/homebrew/var/opttab/opttab",
                     accessibility: true,
                     screenRecording: false,
                     updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testWritesReadableFile() throws {
        let path = directory.appendingPathComponent("status.json").path
        try StatusWriter(path: path).write(sample())
        let decoded = try DaemonStatus.decode(
            try Data(contentsOf: URL(fileURLWithPath: path)))
        XCTAssertEqual(decoded, sample())
    }

    // 5秒ごとに上書きするので、2回目以降も壊れないこと
    func testOverwritesExistingFile() throws {
        let path = directory.appendingPathComponent("status.json").path
        let writer = StatusWriter(path: path)
        try writer.write(sample())
        let updated = DaemonStatus(pid: 99,
                                   version: "0.2.0",
                                   executablePath: "/opt/homebrew/var/opttab/opttab",
                                   accessibility: true,
                                   screenRecording: true,
                                   updatedAt: Date(timeIntervalSince1970: 1_700_000_005))
        try writer.write(updated)
        let decoded = try DaemonStatus.decode(
            try Data(contentsOf: URL(fileURLWithPath: path)))
        XCTAssertEqual(decoded, updated)
    }

    // 親ディレクトリが無ければ作る（開発環境で var/opttab が無い場合）
    func testCreatesParentDirectory() throws {
        let path = directory.appendingPathComponent("nested/deep/status.json").path
        try StatusWriter(path: path).write(sample())
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    }

    // currentStatus は実行時の権限を読むが、pidとpathは決定的に埋まる
    func testCurrentStatusFillsProcessFacts() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let status = StatusWriter.currentStatus(
            executablePath: "/opt/homebrew/var/opttab/opttab", now: now)
        XCTAssertEqual(status.pid, ProcessInfo.processInfo.processIdentifier)
        XCTAssertEqual(status.executablePath, "/opt/homebrew/var/opttab/opttab")
        XCTAssertEqual(status.updatedAt, now)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter StatusWriterTests`
Expected: FAIL — `cannot find 'StatusWriter' in scope`

- [ ] **Step 3: Write minimal implementation**

`Sources/OptTabCore/StatusWriter.swift`:

```swift
import Foundation

/// 状態ファイルへの書き込みだけを持つ薄いラッパ。
public struct StatusWriter {
    private let path: String

    public init(path: String) {
        self.path = path
    }

    public func write(_ status: DaemonStatus) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try DaemonStatus.encode(status).write(to: url, options: .atomic)
    }

    /// 実行中プロセスの現在値を集める。権限の読み取りはここだけに閉じる。
    public static func currentStatus(executablePath: String,
                                     now: Date) -> DaemonStatus {
        DaemonStatus(pid: ProcessInfo.processInfo.processIdentifier,
                     version: OptTabVersion.current,
                     executablePath: executablePath,
                     accessibility: Permissions.accessibilityTrusted,
                     screenRecording: Permissions.screenRecordingGranted,
                     updatedAt: now)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter StatusWriterTests`
Expected: PASS（4テスト）

- [ ] **Step 5: AppDelegateへ組み込む**

`Sources/OptTabCore/AppDelegate.swift` を全置換:

```swift
import AppKit
import Foundation

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var monitor: HotkeyMonitor?
    private var controller: SwitcherController?
    private var retryTimer: Timer?
    private var statusTimer: Timer?
    private var statusWriter: StatusWriter?

    /// 状態ファイルのハートビート間隔。doctor側の許容(30秒)と対で意味を持つ。
    private static let statusInterval: TimeInterval = 5.0

    public func applicationDidFinishLaunching(_ notification: Notification) {
        startStatusHeartbeat()

        // 画面収録は未許可でも動く（サムネイル無しの縮退運転）が、初回に要求はする
        if !Permissions.screenRecordingGranted {
            Permissions.requestScreenRecording()
        }

        let controller = SwitcherController()
        self.controller = controller
        let monitor = HotkeyMonitor()
        monitor.delegate = controller
        self.monitor = monitor

        if !startMonitor() {
            // アクセシビリティ未許可: ダイアログを出しつつ、許可されるまで3秒ごとに再試行
            Permissions.promptAccessibility()
            retryTimer = Timer.scheduledTimer(withTimeInterval: 3.0,
                                              repeats: true) { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if self.startMonitor() {
                        self.retryTimer?.invalidate()
                        self.retryTimer = nil
                    }
                }
            }
        }
    }

    /// 自分の権限状態を実行ファイルの隣の status.json に書き続ける。
    /// opttab doctor はこれを読む。
    private func startStatusHeartbeat() {
        let executablePath = URL(fileURLWithPath: CommandLine.arguments[0])
            .resolvingSymlinksInPath().path
        let writer = StatusWriter(
            path: StatusFile.path(forExecutable: executablePath))
        statusWriter = writer

        let publish = { [weak self] in
            guard self != nil else { return }
            let status = StatusWriter.currentStatus(
                executablePath: executablePath, now: Date())
            do {
                try writer.write(status)
            } catch {
                NSLog("status write failed: \(error)")
            }
        }
        publish()
        statusTimer = Timer.scheduledTimer(
            withTimeInterval: Self.statusInterval, repeats: true) { _ in
            publish()
        }
    }

    @discardableResult
    private func startMonitor() -> Bool {
        guard Permissions.accessibilityTrusted else { return false }
        return monitor?.start() ?? false
    }
}
```

- [ ] **Step 6: 実機で状態ファイルが書かれることを確認**

```bash
swift build -c release
launchctl bootout gui/$UID/dev.konaito.opttab 2>/dev/null || true
rm -f /opt/homebrew/var/opttab/opttab
cp .build/release/OptTab /opt/homebrew/var/opttab/opttab
codesign --force --options runtime -i dev.konaito.opttab \
  --sign "Developer ID Application: KOUTA NAITOU (T79674CM55)" \
  /opt/homebrew/var/opttab/opttab
launchctl bootstrap gui/$UID ~/Library/LaunchAgents/dev.konaito.opttab.plist
cat /opt/homebrew/var/opttab/status.json
```

Expected: `accessibility: true`, `screenRecording: true`、`executablePath` が
`/opt/homebrew/var/opttab/opttab`、`updatedAt` が現在時刻のJSONが出力される。
`⌥⇥` が引き続き動くことも確認する。

- [ ] **Step 7: Commit**

```bash
git add Sources/OptTabCore/StatusWriter.swift Sources/OptTabCore/AppDelegate.swift \
        Tests/OptTabCoreTests/StatusWriterTests.swift
git commit -m "feat: デーモンが権限状態をstatus.jsonへ5秒ごとに書き出す"
```

---

### Task 4: 旧インストールの検出とdoctorレポートの組み立て

`opttab doctor` の判断ロジックを純関数として作る。ファイルI/Oとプロセス起動はTask 5。

新旧が同時に走ると2つのCGEventTapが `⌥⇥` を奪い合うため、
旧`.app`と手作りLaunchAgentの残骸を検出して警告する。

**Files:**
- Create: `Sources/OptTabCore/DoctorReport.swift`
- Test: `Tests/OptTabCoreTests/DoctorReportTests.swift`

**Interfaces:**
- Consumes: `DaemonStatus`
- Produces:
  - `public enum LegacyInstall { public static let candidates: [LegacyInstall.Candidate]; public struct Candidate: Equatable { public let path: String; public let advice: String }; public static func warnings(existing: Set<String>) -> [String] }`
  - `public struct DoctorReport: Equatable { public enum Service: Equatable { case running(pid: Int32, version: String), notRunning, statusUnavailable }; public let service: Service; public let accessibility: Bool; public let screenRecording: Bool; public let warnings: [String]; public var exitCode: Int32; public func render() -> String }`
  - `public static func DoctorReport.build(status: DaemonStatus?, now: Date, legacyExisting: Set<String>) -> DoctorReport`

- [ ] **Step 1: Write the failing test**

`Tests/OptTabCoreTests/DoctorReportTests.swift`:

```swift
import XCTest
@testable import OptTabCore

final class DoctorReportTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func status(offset: TimeInterval = 0,
                        accessibility: Bool = true,
                        screenRecording: Bool = true) -> DaemonStatus {
        DaemonStatus(pid: 1234,
                     version: "0.2.0",
                     executablePath: "/opt/homebrew/var/opttab/opttab",
                     accessibility: accessibility,
                     screenRecording: screenRecording,
                     updatedAt: now.addingTimeInterval(offset))
    }

    // 状態ファイルが無い = サービスが一度も起動していない
    func testNoStatusFileMeansUnavailable() {
        let report = DoctorReport.build(status: nil, now: now, legacyExisting: [])
        XCTAssertEqual(report.service, .statusUnavailable)
        XCTAssertEqual(report.exitCode, 1)
    }

    // ハートビートが新しい = 動いている
    func testFreshStatusMeansRunning() {
        let report = DoctorReport.build(status: status(offset: -3),
                                        now: now, legacyExisting: [])
        XCTAssertEqual(report.service, .running(pid: 1234, version: "0.2.0"))
        XCTAssertEqual(report.exitCode, 0)
    }

    // ハートビートが途絶えた = 落ちている
    func testStaleStatusMeansNotRunning() {
        let report = DoctorReport.build(status: status(offset: -120),
                                        now: now, legacyExisting: [])
        XCTAssertEqual(report.service, .notRunning)
        XCTAssertEqual(report.exitCode, 1)
    }

    // アクセシビリティが無ければ異常終了（必須権限のため）
    func testMissingAccessibilityIsFailure() {
        let report = DoctorReport.build(status: status(accessibility: false),
                                        now: now, legacyExisting: [])
        XCTAssertFalse(report.accessibility)
        XCTAssertEqual(report.exitCode, 1)
    }

    // 画面収録は任意。無くても正常終了する（サムネイル無しで動く）
    func testMissingScreenRecordingIsNotFailure() {
        let report = DoctorReport.build(status: status(screenRecording: false),
                                        now: now, legacyExisting: [])
        XCTAssertFalse(report.screenRecording)
        XCTAssertEqual(report.exitCode, 0)
    }

    // 旧 .app が残っていたら警告する（イベントタップの奪い合いになる）
    func testLegacyAppProducesWarning() {
        let report = DoctorReport.build(
            status: status(), now: now,
            legacyExisting: ["/Applications/OptTab.app"])
        XCTAssertEqual(report.warnings.count, 1)
        XCTAssertTrue(report.warnings[0].contains("/Applications/OptTab.app"))
        XCTAssertTrue(report.warnings[0].contains("brew uninstall --cask opttab"))
    }

    // 手作りLaunchAgentが残っていたら警告する（brew servicesと二重起動になる）
    func testLegacyLaunchAgentProducesWarning() {
        let path = NSString(string: "~/Library/LaunchAgents/dev.konaito.opttab.plist")
            .expandingTildeInPath
        let report = DoctorReport.build(status: status(), now: now,
                                        legacyExisting: [path])
        XCTAssertEqual(report.warnings.count, 1)
        XCTAssertTrue(report.warnings[0].contains("launchctl bootout"))
    }

    // 警告があっても、サービス自体が健全なら終了コードは0のまま
    func testWarningsDoNotChangeExitCode() {
        let report = DoctorReport.build(
            status: status(), now: now,
            legacyExisting: ["/Applications/OptTab.app"])
        XCTAssertEqual(report.exitCode, 0)
    }

    func testLegacyCandidatesCoverKnownLeftovers() {
        let paths = LegacyInstall.candidates.map(\.path)
        XCTAssertTrue(paths.contains("/Applications/OptTab.app"))
        XCTAssertTrue(paths.contains(
            NSString(string: "~/Applications/OptTab.app").expandingTildeInPath))
        XCTAssertTrue(paths.contains(
            NSString(string: "~/Library/LaunchAgents/dev.konaito.opttab.plist")
                .expandingTildeInPath))
    }

    // 出力に権限とサービス状態が両方現れる
    func testRenderMentionsServiceAndPermissions() {
        let text = DoctorReport.build(status: status(), now: now,
                                      legacyExisting: []).render()
        XCTAssertTrue(text.contains("1234"))
        XCTAssertTrue(text.contains("Accessibility"))
        XCTAssertTrue(text.contains("Screen Recording"))
    }

    // 権限が欠けていたら設定パネルのURLを案内する（自動で開かない）
    func testRenderShowsSettingsURLWhenAccessibilityMissing() {
        let text = DoctorReport.build(status: status(accessibility: false),
                                      now: now, legacyExisting: []).render()
        XCTAssertTrue(text.contains("Privacy_Accessibility"))
    }

    // サービス未起動なら起動方法を案内する
    func testRenderShowsStartCommandWhenNotRunning() {
        let text = DoctorReport.build(status: nil, now: now,
                                      legacyExisting: []).render()
        XCTAssertTrue(text.contains("brew services start opttab"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter DoctorReportTests`
Expected: FAIL — `cannot find 'DoctorReport' in scope`

- [ ] **Step 3: Write minimal implementation**

`Sources/OptTabCore/DoctorReport.swift`:

```swift
import Foundation

/// 旧インストールの残骸。新デーモンと同時に走ると
/// 2つのCGEventTapが ⌥⇥ を奪い合うので検出して警告する。
/// 消すのは越権なのでコマンドを表示するだけにする。
public enum LegacyInstall {
    public struct Candidate: Equatable {
        public let path: String
        public let advice: String

        public init(path: String, advice: String) {
            self.path = path
            self.advice = advice
        }
    }

    public static let candidates: [Candidate] = [
        Candidate(path: "/Applications/OptTab.app",
                  advice: "brew uninstall --cask opttab"),
        Candidate(path: NSString(string: "~/Applications/OptTab.app")
                    .expandingTildeInPath,
                  advice: "rm -rf ~/Applications/OptTab.app"),
        Candidate(path: NSString(string: "~/Library/LaunchAgents/dev.konaito.opttab.plist")
                    .expandingTildeInPath,
                  advice: "launchctl bootout gui/$UID/dev.konaito.opttab && "
                        + "rm -f ~/Library/LaunchAgents/dev.konaito.opttab.plist"),
    ]

    public static func warnings(existing: Set<String>) -> [String] {
        candidates
            .filter { existing.contains($0.path) }
            .map { "leftover from the old install: \($0.path)\n    remove it: \($0.advice)" }
    }
}

public struct DoctorReport: Equatable {
    public enum Service: Equatable {
        case running(pid: Int32, version: String)
        /// 状態ファイルはあるがハートビートが途絶えている
        case notRunning
        /// 状態ファイルが無い（未起動、または別prefixにインストールされている）
        case statusUnavailable
    }

    /// デーモンのハートビートは5秒間隔。取りこぼしを見込んで30秒許容する。
    public static let freshnessTolerance: TimeInterval = 30

    public let service: Service
    public let accessibility: Bool
    public let screenRecording: Bool
    public let warnings: [String]

    public init(service: Service,
                accessibility: Bool,
                screenRecording: Bool,
                warnings: [String]) {
        self.service = service
        self.accessibility = accessibility
        self.screenRecording = screenRecording
        self.warnings = warnings
    }

    public static func build(status: DaemonStatus?,
                             now: Date,
                             legacyExisting: Set<String>) -> DoctorReport {
        let warnings = LegacyInstall.warnings(existing: legacyExisting)

        guard let status else {
            return DoctorReport(service: .statusUnavailable,
                                accessibility: false,
                                screenRecording: false,
                                warnings: warnings)
        }

        let fresh = DaemonStatus.isFresh(status, now: now,
                                         tolerance: freshnessTolerance)
        return DoctorReport(
            service: fresh ? .running(pid: status.pid, version: status.version)
                           : .notRunning,
            accessibility: status.accessibility,
            screenRecording: status.screenRecording,
            warnings: warnings)
    }

    /// アクセシビリティはホットキーに必須。画面収録はサムネイル用の任意権限。
    public var exitCode: Int32 {
        switch service {
        case .running:
            return accessibility ? 0 : 1
        case .notRunning, .statusUnavailable:
            return 1
        }
    }

    public func render() -> String {
        var lines: [String] = []

        switch service {
        case .running(let pid, let version):
            lines.append("service:          running (pid \(pid), version \(version))")
        case .notRunning:
            lines.append("service:          not running (heartbeat is stale)")
            lines.append("  start it:       brew services start opttab")
        case .statusUnavailable:
            lines.append("service:          not running (no status file)")
            lines.append("  start it:       brew services start opttab")
        }

        lines.append("Accessibility:    \(accessibility ? "granted" : "MISSING (required for the ⌥⇥ hotkey)")")
        if !accessibility {
            lines.append("  grant it:       System Settings > Privacy & Security > Accessibility")
            lines.append("  open directly:  open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'")
        }

        lines.append("Screen Recording: \(screenRecording ? "granted" : "missing (optional — thumbnails are replaced by icons)")")
        if !screenRecording {
            lines.append("  grant it:       System Settings > Privacy & Security > Screen Recording")
            lines.append("  open directly:  open 'x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture'")
        }

        for warning in warnings {
            lines.append("warning: \(warning)")
        }

        return lines.joined(separator: "\n")
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter DoctorReportTests`
Expected: PASS（12テスト）

- [ ] **Step 5: Commit**

```bash
git add Sources/OptTabCore/DoctorReport.swift Tests/OptTabCoreTests/DoctorReportTests.swift
git commit -m "feat: doctorの判定ロジックと旧インストール検出を追加"
```

---

### Task 5: `opttab doctor` の配線

Task 4の純ロジックに実際のファイルI/Oを繋いで、コマンドとして動くようにする。

**Files:**
- Create: `Sources/OptTabCore/Doctor.swift`
- Modify: `Sources/OptTab/main.swift`

**Interfaces:**
- Consumes: `DoctorReport`, `LegacyInstall`, `StatusFile`, `DaemonStatus`
- Produces:
  - `public enum Doctor { public static func run() -> Int32; public static func loadStatus(candidatePaths: [String], read: (String) -> Data?) -> DaemonStatus? }`

- [ ] **Step 1: Write the failing test**

`Tests/OptTabCoreTests/DoctorTests.swift`:

```swift
import XCTest
@testable import OptTabCore

final class DoctorTests: XCTestCase {
    private let sample = DaemonStatus(
        pid: 7,
        version: "0.2.0",
        executablePath: "/opt/homebrew/var/opttab/opttab",
        accessibility: true,
        screenRecording: true,
        updatedAt: Date(timeIntervalSince1970: 1_700_000_000))

    // 最初に見つかった候補パスを採用する
    func testLoadsFromFirstExistingCandidate() throws {
        let data = try DaemonStatus.encode(sample)
        let loaded = Doctor.loadStatus(
            candidatePaths: ["/opt/homebrew/var/opttab/status.json",
                             "/usr/local/var/opttab/status.json"],
            read: { $0 == "/opt/homebrew/var/opttab/status.json" ? data : nil })
        XCTAssertEqual(loaded, sample)
    }

    // 前段が無ければ次の候補へ進む（Intel Macのprefix）
    func testFallsBackToSecondCandidate() throws {
        let data = try DaemonStatus.encode(sample)
        let loaded = Doctor.loadStatus(
            candidatePaths: ["/opt/homebrew/var/opttab/status.json",
                             "/usr/local/var/opttab/status.json"],
            read: { $0 == "/usr/local/var/opttab/status.json" ? data : nil })
        XCTAssertEqual(loaded, sample)
    }

    func testReturnsNilWhenNoCandidateExists() {
        XCTAssertNil(Doctor.loadStatus(
            candidatePaths: ["/opt/homebrew/var/opttab/status.json"],
            read: { _ in nil }))
    }

    // 壊れたファイルはnil扱い（doctorが落ちない）
    func testCorruptFileIsTreatedAsMissing() {
        XCTAssertNil(Doctor.loadStatus(
            candidatePaths: ["/opt/homebrew/var/opttab/status.json"],
            read: { _ in Data("garbage".utf8) }))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter DoctorTests`
Expected: FAIL — `cannot find 'Doctor' in scope`

- [ ] **Step 3: Write minimal implementation**

`Sources/OptTabCore/Doctor.swift`:

```swift
import Foundation

/// `opttab doctor` の実体。ファイルI/Oだけを持ち、判定は DoctorReport に委ねる。
public enum Doctor {
    /// 候補パスを順に読み、最初に成功したものを返す。
    /// 読み取り関数を差し替えられるようにしてテスト可能にしている。
    public static func loadStatus(candidatePaths: [String],
                                  read: (String) -> Data?) -> DaemonStatus? {
        for path in candidatePaths {
            guard let data = read(path) else { continue }
            if let status = try? DaemonStatus.decode(data) { return status }
        }
        return nil
    }

    public static func run() -> Int32 {
        let status = loadStatus(
            candidatePaths: StatusFile.candidatePaths(
                prefixes: StatusFile.defaultPrefixes),
            read: { try? Data(contentsOf: URL(fileURLWithPath: $0)) })

        let existing = Set(
            LegacyInstall.candidates
                .map(\.path)
                .filter { FileManager.default.fileExists(atPath: $0) })

        let report = DoctorReport.build(status: status,
                                        now: Date(),
                                        legacyExisting: existing)
        print(report.render())
        return report.exitCode
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter DoctorTests`
Expected: PASS（4テスト）

- [ ] **Step 5: main.swift の仮実装を差し替える**

`Sources/OptTab/main.swift` の `case .doctor:` を置換:

```swift
case .doctor:
    exit(Doctor.run())
```

- [ ] **Step 6: 実機で3ケースを確認**

```bash
swift build -c release

# (a) サービス稼働中 + 旧.app残存 → 警告つきで exit 0
.build/release/OptTab doctor; echo "exit=$?"

# (b) サービス停止中 → exit 1
launchctl bootout gui/$UID/dev.konaito.opttab
sleep 35
.build/release/OptTab doctor; echo "exit=$?"

# (c) 復旧
launchctl bootstrap gui/$UID ~/Library/LaunchAgents/dev.konaito.opttab.plist
sleep 6
.build/release/OptTab doctor; echo "exit=$?"
```

Expected:
- (a) `service: running (pid …)` / `Accessibility: granted` / `/Applications/OptTab.app` と手作りplistの警告2件 / `exit=0`
- (b) `service: not running (heartbeat is stale)` / `exit=1`
- (c) `service: running` / `exit=0`

**重要**: ghostty等のターミナルにアクセシビリティ許可があっても、
`Accessibility:` の行はデーモンの状態を反映していること
（`launchctl bootout` した状態でも status.json の中身を読むだけなので、
呼び出し元ターミナルの権限に引きずられない）。

- [ ] **Step 7: Commit**

```bash
git add Sources/OptTabCore/Doctor.swift Sources/OptTab/main.swift \
        Tests/OptTabCoreTests/DoctorTests.swift
git commit -m "feat: opttab doctor を実装する"
```

---

### Task 6: ビルド・インストールスクリプトの置き換え

`.app` を作る `Scripts/bundle.sh` を廃止し、
「universalビルド → 署名 → 固定パスへ配置 → エージェント再起動」を行う
ローカル開発用スクリプトに置き換える。

**Files:**
- Delete: `Scripts/bundle.sh`
- Create: `Scripts/install-local.sh`

**Interfaces:**
- Consumes: `Support/Info.plist`（`Package.swift` の `linkerSettings` 経由で埋め込み済み）
- Produces: `$(brew --prefix)/var/opttab/opttab` に署名済みバイナリ

- [ ] **Step 1: 新スクリプトを書く**

`Scripts/install-local.sh`:

```bash
#!/bin/bash
# ローカル開発用: ビルド → 署名 → 固定パスへ配置 → LaunchAgent再起動
#
# launchd が起動する実体は $(brew --prefix)/var/opttab/opttab に固定する。
# TCC は非バンドルバイナリを実パスで識別するため、このパスを変えると
# アクセシビリティと画面収録の許可が失われる。
set -euo pipefail
cd "$(dirname "$0")/.."

PREFIX=$(brew --prefix)
DEST="$PREFIX/var/opttab"
LABEL=dev.konaito.opttab
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

swift build -c release
BIN=.build/release/OptTab

mkdir -p "$DEST"

# 実行中の Mach-O へ直接 cp すると ETXTBSY。先に止めて rm する。
# inode は変わるがパスは同じなので TCC の許可は維持される。
launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
rm -f "$DEST/opttab"
cp "$BIN" "$DEST/opttab"

# signing identifier を変えると TCC の csreq 検証に落ちて許可が飛ぶ。
# Developer ID が無い環境では ad-hoc に落とすが、その場合は
# リビルドのたびに再許可が必要になる。
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Developer ID Application/{print $2; exit}')
if [ -n "$IDENTITY" ]; then
    codesign --force --options runtime -i dev.konaito.opttab \
        --sign "$IDENTITY" "$DEST/opttab"
else
    echo "warning: Developer ID証明書が無いのでad-hoc署名にする。" >&2
    echo "         ビルドのたびにアクセシビリティの再許可が必要になる。" >&2
    codesign --force -i dev.konaito.opttab --sign - "$DEST/opttab"
fi

# brew services を使っていない開発環境向けに、無ければ plist を作る
if [ ! -f "$PLIST" ]; then
    cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key><array><string>$DEST/opttab</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>LimitLoadToSessionType</key><array><string>Aqua</string></array>
</dict>
</plist>
PLIST_EOF
    echo "created: $PLIST"
fi

launchctl bootstrap "gui/$UID" "$PLIST"
echo "installed: $DEST/opttab"
"$DEST/opttab" --version
```

- [ ] **Step 2: 実行権を付けて旧スクリプトを消す**

```bash
chmod +x Scripts/install-local.sh
git rm Scripts/bundle.sh
```

- [ ] **Step 3: 動作確認**

```bash
./Scripts/install-local.sh
sleep 6
/opt/homebrew/var/opttab/opttab doctor
```

Expected: `installed:` とバージョンが出力され、`doctor` が `service: running` を報告する。
`⌥⇥` が動くこと。**アクセシビリティの再許可を求められないこと**（同一パス・同一identifier署名のため）。

- [ ] **Step 4: Commit**

```bash
git add Scripts/install-local.sh
git commit -m "feat: bundle.shをinstall-local.shへ置き換える（.app廃止）"
```

---

### Task 7: リリーススクリプトのuniversalバイナリ対応

`.app` のzipを公証する形から、universal単体バイナリを公証してReleaseへ上げる形にする。

単体Mach-Oには `stapler staple` できない。Homebrewの `curl` は quarantine属性を
付けないためGatekeeperの実行時検証には引っかからないが、配布物が改竄されていない
ことの担保として公証自体は行う。

**Files:**
- Modify: `Scripts/notarize-release.sh`

**Interfaces:**
- Consumes: `Support/Info.plist` の `CFBundleShortVersionString`
- Produces: GitHub Release に `opttab-<version>-universal.tar.gz` と、そのsha256

- [ ] **Step 1: スクリプトを全置換**

`Scripts/notarize-release.sh`:

```bash
#!/bin/bash
# 公証済みuniversalバイナリを作ってGitHub Releaseに添付する
# 前提: xcrun notarytool store-credentials "AC_PASSWORD" --apple-id <id> \
#         --team-id T79674CM55 --password <app用パスワード> 済み
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=${1:?usage: notarize-release.sh <version e.g. 0.2.0>}

# Support/Info.plist のバージョンとタグを一致させる（doctorとformulaが同じ値を見る）
PLIST_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
    Support/Info.plist)
if [ "$PLIST_VERSION" != "$VERSION" ]; then
    echo "Support/Info.plist は $PLIST_VERSION だが引数は $VERSION。揃えること" >&2
    exit 1
fi

swift build -c release --arch arm64 --arch x86_64
BIN=.build/apple/Products/Release/OptTab
lipo -info "$BIN"

IDENTITY=$(security find-identity -v -p codesigning \
    | awk -F'"' '/Developer ID Application/{print $2; exit}')
[ -n "$IDENTITY" ] || { echo "Developer ID Application証明書が見つからない"; exit 1; }

STAGE=build/stage
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp "$BIN" "$STAGE/opttab"

# signing identifier は dev.konaito.opttab から変えてはならない。
# 変えるとTCCのcsreq検証に落ちて既存ユーザーの許可が飛ぶ。
codesign --force --options runtime -i dev.konaito.opttab \
    --sign "$IDENTITY" "$STAGE/opttab"
codesign --verify --strict --verbose=2 "$STAGE/opttab"

TARBALL="build/opttab-$VERSION-universal.tar.gz"
rm -f "$TARBALL"
tar -czf "$TARBALL" -C "$STAGE" opttab

# 単体Mach-Oはzipに入れて提出する（notarytoolはtar.gzを受け付けない）
ZIP="build/opttab-$VERSION-notarize.zip"
rm -f "$ZIP"
ditto -c -k "$STAGE/opttab" "$ZIP"

echo "notarizing (数分かかる)..."
xcrun notarytool submit "$ZIP" --keychain-profile AC_PASSWORD --wait

# 単体バイナリには stapler staple できないので貼らない。
# Homebrewのcurlはquarantineを付けないため実行時検証には影響しない。

echo "sha256:"
shasum -a 256 "$TARBALL"
gh release upload "v$VERSION" "$TARBALL" --clobber
echo "uploaded: v$VERSION"
```

- [ ] **Step 2: 公証まで通さずにビルド部分だけ検証する**

CIやリリース前に壊れていないことを、公証を待たずに確かめる。

```bash
bash -n Scripts/notarize-release.sh   # 構文チェック
swift build -c release --arch arm64 --arch x86_64
lipo -info .build/apple/Products/Release/OptTab
```

Expected: 構文エラー無し。`Architectures in the fat file: … are: x86_64 arm64`。

- [ ] **Step 3: バージョンを 0.2.0 に揃える**

`Support/Info.plist` の `CFBundleShortVersionString` が `0.2.0` であることを確認する
（Task 1で既に `0.2.0`）。

- [ ] **Step 4: Commit**

```bash
git add Scripts/notarize-release.sh
git commit -m "feat: リリーススクリプトをuniversal単体バイナリ配布へ移行"
```

---

### Task 8: Homebrew formula の作成とローカル実測

**別リポジトリ（`konaito/homebrew-tap`）の作業を含む。** 忘れないよう明示的に扱う。

**Files:**
- Modify: `$(brew --repository)/Library/Taps/konaito/homebrew-tap/Formula/opttab.rb`
- Delete: `$(brew --repository)/Library/Taps/konaito/homebrew-tap/Casks/opttab.rb`

**Interfaces:**
- Consumes: GitHub Release の `opttab-<version>-universal.tar.gz` と sha256
- Produces: `brew install konaito/tap/opttab` → `$(brew --prefix)/var/opttab/opttab`

- [ ] **Step 1: formula を書く**

`Formula/opttab.rb`:

```ruby
class Opttab < Formula
  desc "Option+Tab window switcher for macOS - reaches windows across Spaces"
  homepage "https://konaito.github.io/opttab/"
  url "https://github.com/konaito/opttab/releases/download/v0.2.0/opttab-0.2.0-universal.tar.gz"
  sha256 "PLACEHOLDER_REPLACE_WITH_ACTUAL_SHA256_FROM_RELEASE"
  license "MIT"
  version "0.2.0"

  depends_on macos: ">= :sonoma"

  def install
    bin.install "opttab"
  end

  # launchd が起動する実体は var/opttab/opttab に固定する。
  # TCC は非バンドルバイナリを「解決後の実パス」で識別するため、
  # Cellar のバージョン付きパスから起動すると brew upgrade のたびに
  # アクセシビリティと画面収録の許可が失われる。
  def post_install
    (var/"opttab").mkpath
    # 実行中の Mach-O への上書きは ETXTBSY になる。
    # rm してから cp すれば inode は変わるがパスは同じなので許可は維持される。
    rm_f var/"opttab/opttab"
    cp bin/"opttab", var/"opttab/opttab"
    chmod 0755, var/"opttab/opttab"
  end

  service do
    run var/"opttab/opttab"
    keep_alive true
    log_path var/"log/opttab.log"
    error_log_path var/"log/opttab.log"
  end

  def caveats
    <<~EOS
      Start the service:
        brew services start opttab

      On first start, OptTab asks for Accessibility (required for the #{"⌥⇥"} hotkey).
      Grant it in System Settings > Privacy & Security > Accessibility, for:
        #{var}/opttab/opttab

      Screen Recording is optional - without it, the HUD shows icons
      instead of live thumbnails.

      Check everything at once:
        opttab doctor

      After `brew upgrade opttab`, restart the service so the new binary runs:
        brew services restart opttab

      Migrating from the old menu bar app? Remove it, or two event taps
      will fight over #{"⌥⇥"}:
        brew uninstall --cask opttab
    EOS
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/opttab --version")
  end
end
```

- [ ] **Step 2: Release公開後にsha256を差し替える**

```bash
./Scripts/notarize-release.sh 0.2.0     # sha256を出力する
# 出力された値で formula の PLACEHOLDER_REPLACE_WITH_ACTUAL_SHA256_FROM_RELEASE を置換する
```

- [ ] **Step 3: caskを削除する**

```bash
cd "$(brew --repository)/Library/Taps/konaito/homebrew-tap"
git rm Casks/opttab.rb
```

- [ ] **Step 4: ローカルでインストールを実測する**

```bash
# 検証用に手で作った LaunchAgent を先に外す（brew services と二重起動になる）
launchctl bootout gui/$UID/dev.konaito.opttab 2>/dev/null || true
rm -f ~/Library/LaunchAgents/dev.konaito.opttab.plist

brew install --formula konaito/tap/opttab
brew services start opttab
sleep 6
opttab doctor; echo "exit=$?"
ls -l "$(brew --prefix)/var/opttab/"
```

Expected: `doctor` が `service: running` を報告し、`exit=0`。
`var/opttab/` に `opttab` と `status.json` がある。
**アクセシビリティの再許可を求められないこと**
（Phase 0で許可済みのパスと同じ `$(brew --prefix)/var/opttab/opttab` のため）。

- [ ] **Step 5: `brew upgrade` がサービスを再起動するか実測する**

**これは推測してはいけない。** 再起動しない場合、削除済みinodeの古いバイナリが
動き続けるため、caveatsの `brew services restart opttab` の案内が必須になる。

```bash
# バージョンを 0.2.1 に上げた formula を用意して:
OLD_PID=$(opttab doctor | sed -n 's/.*pid \([0-9]*\).*/\1/p')
brew upgrade konaito/tap/opttab
sleep 6
NEW_PID=$(opttab doctor | sed -n 's/.*pid \([0-9]*\).*/\1/p')
echo "old=$OLD_PID new=$NEW_PID"
opttab --version
```

Expected（どちらかを記録する）:
- PIDが変わっていれば `brew upgrade` がサービスを再起動している
- PIDが同じなら再起動していない → caveatsの `brew services restart opttab` の
  文言を「必須」として強調し、READMEにも書く

**加えて、アップグレード後も `doctor` が `Accessibility: granted` を報告すること。**
これがこの設計全体の要である。

- [ ] **Step 6: stop/start/restart を確認する**

```bash
brew services stop opttab
sleep 35
opttab doctor; echo "exit=$?"      # exit=1、not running を期待
brew services start opttab
sleep 6
opttab doctor; echo "exit=$?"      # exit=0 を期待
brew services restart opttab
sleep 6
opttab doctor; echo "exit=$?"      # exit=0 を期待
```

- [ ] **Step 7: tapリポジトリをコミットしてpushする**

```bash
cd "$(brew --repository)/Library/Taps/konaito/homebrew-tap"
git checkout -b feat/opttab-service
git add Formula/opttab.rb
git commit -m "feat(opttab): launchd常駐サービス化。caskを廃止しformula一本化"
git push -u origin feat/opttab-service
gh pr create --fill
```

**mainへ直接pushしないこと。**

---

### Task 9: ドキュメント更新

メニューバー前提の記述と `brew install --cask` の導線が全部残っているので直す。

**Files:**
- Modify: `README.md`（英語節 38-68行目付近、日本語節 105-116行目付近）
- Modify: `docs/index.html`

**Interfaces:**
- Consumes: Task 8で確定した `brew upgrade` の再起動挙動
- Produces: なし

- [ ] **Step 1: README英語節のInstallを書き換える**

`README.md` の `## Install` から `## How it works` の直前までを置換:

````markdown
## Install

```bash
brew install konaito/tap/opttab
brew services start opttab
```

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

### Migrating from the menu bar app (≤ 0.1.0)

The old `.app` and the new service both install a CGEventTap, and they will
fight over `⌥⇥`. Remove the old one:

```bash
brew uninstall --cask opttab
```

`opttab doctor` warns if it finds any leftovers.

### From source

```bash
git clone https://github.com/konaito/opttab.git
cd opttab
./Scripts/install-local.sh
```

Requirements: macOS 14+, Xcode Command Line Tools.
````

- [ ] **Step 2: README英語節の冒頭からメニューバーへの言及を消す**

`## Features` のリスト末尾に1項目を追加:

```markdown
- **No menu bar icon** — runs as a launchd service, managed by `brew services`
```

- [ ] **Step 3: README日本語節を書き換える**

`### インストール` から末尾の操作表の直前までを置換:

````markdown
### インストール

```bash
brew install konaito/tap/opttab
brew services start opttab
```

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

### メニューバー版（0.1.0以前）からの移行

旧`.app`と新サービスは両方ともCGEventTapを張るので `⌥⇥` を奪い合う。旧版を消すこと。

```bash
brew uninstall --cask opttab
```

残骸があれば `opttab doctor` が警告する。

### ソースから

```bash
git clone https://github.com/konaito/opttab.git
cd opttab
./Scripts/install-local.sh
```
````

- [ ] **Step 4: docs/index.html のインストールコマンドを直す**

```bash
grep -n "cask\|OptTab.app\|menu bar\|メニューバー\|Launch at Login" docs/index.html
```

見つかった箇所を、Step 1と同じ内容（`brew install konaito/tap/opttab` +
`brew services start opttab`）に書き換える。
「メニューバーから起動」「Launch at Login」の説明は `brew services` の説明に差し替える。

- [ ] **Step 5: Development節のビルド手順を確認する**

`README.md` の `## Development` にある `swift build && swift test` はそのままでよい。
`./Scripts/bundle.sh` への言及が残っていないか確認する。

```bash
grep -rn "bundle.sh" README.md docs/
```

Expected: ヒット無し。あれば `./Scripts/install-local.sh` に直す。

- [ ] **Step 6: Commit**

```bash
git add README.md docs/index.html
git commit -m "docs: launchd常駐サービス化に合わせてインストール手順を更新"
```

---

### Task 10: このマシンの後片付けとPR

Phase 0で手作りした検証用の残骸を消し、正規の経路に一本化する。

**Files:** なし（マシン操作とgit操作）

- [ ] **Step 1: 手作りLaunchAgentを外す**

```bash
launchctl bootout gui/$UID/dev.konaito.opttab 2>/dev/null || true
rm -f ~/Library/LaunchAgents/dev.konaito.opttab.plist
sfltool dumpbtm | grep -A6 "dev.konaito.opttab" || echo "BTMから消えた"
```

- [ ] **Step 2: 旧caskを削除する**

```bash
brew uninstall --cask opttab
ls -ld /Applications/OptTab.app 2>&1     # No such file を期待
```

- [ ] **Step 3: brew services 経由の一本化を確認する**

```bash
brew services list | grep opttab
sleep 6
opttab doctor; echo "exit=$?"
```

Expected: `opttab started konaito ~/Library/LaunchAgents/homebrew.mxcl.opttab.plist`。
`doctor` は `exit=0`、**警告ゼロ**（旧`.app`も手作りplistも消えたため）。

- [ ] **Step 4: 孤児化したTCCエントリを掃除する**

Phase 0の検証で作られた不要なエントリを消す。

```bash
sqlite3 /Library/Application\ Support/com.apple.TCC/TCC.db \
  "select service, client, auth_value from access where client like '%opttab%';"
```

`opttabspike` を含む行、および `dev.konaito.opttab`（旧`.app`のbundle ID）の行は
不要。システム設定の各リストから `−` ボタンで削除する
（TCC.dbはSIPで保護されており直接削除できない）。

残すのは `/opt/homebrew/var/opttab/opttab` の2行のみ。

- [ ] **Step 5: 全テストとビルドを通す**

```bash
swift build -c release
swift build -c release --arch arm64 --arch x86_64
swift test
```

Expected: すべて成功。テストは既存46件 + 本計画で追加した37件。

- [ ] **Step 6: PRを出す**

```bash
git push -u origin feat/launchd-service
gh pr create --title "feat: メニューバー常駐をやめてlaunchd常駐サービス化する" --body "$(cat <<'EOF'
## 概要

OptTabをメニューバー常駐の`.app`から、`brew services`で管理するlaunchd常駐の
単体バイナリへ移行する。

## 設計の要点

TCCは非バンドルバイナリを**解決後の実パス**で識別する（`client_type=1`）。
埋め込みInfo.plistのCFBundleIdentifierでもDeveloper ID署名でも、bundle ID識別には
ならない。実測結果:

| 操作 | 結果 |
|---|---|
| 同一パスでバイナリ差し替え（同identity・同identifier） | 権限維持 |
| パス変更 | 権限消滅 |

そのためlaunchdが起動する実体は`$(brew --prefix)/var/opttab/opttab`という
バージョン非依存の固定パスに置き、formulaの`post_install`がCellarからコピーする。
Cellar直下から起動すると`brew upgrade`のたびに再許可が必要になる。

詳細は `docs/superpowers/specs/2026-08-15-opttab-launchd-service-design.md`。

## 変更

- `MenuBarController` と `SMAppService` によるログイン項目管理を削除
- Info.plistを `__TEXT,__info_plist` セクションへ埋め込み（`.app`廃止）
- `opttab doctor` / `--version` / `--help` を追加
- デーモンが権限状態を `status.json` へ5秒ごとに書く
  （doctorが自プロセスの権限を見ると呼び出し元ターミナルの権限が返るため）
- `Scripts/bundle.sh` → `Scripts/install-local.sh`
- リリースをuniversal単体バイナリの公証配布へ移行
- cask廃止、formula一本化（tapは別PR）

## 移行

旧`.app`と新サービスは両方CGEventTapを張るため`⌥⇥`を奪い合う。
`brew uninstall --cask opttab` が必要。`opttab doctor` が残骸を検出して警告する。

EOF
)"
```

**mainへ直接pushしないこと。** ブランチは `feat/launchd-service`。

---

## Self-Review

**1. Spec coverage**

| specの節 | 実装するTask |
|---|---|
| バイナリ形態（Info.plist埋め込み、`.accessory`維持） | 済（このブランチの先行コミット `d377e5c`）+ Task 7でuniversal化 |
| 配置（`var/opttab/opttab` 固定パス） | Task 6, Task 8 |
| launchd / brew services（`service`ブロック） | Task 8 |
| CLI（`--version` / `doctor`） | Task 1, Task 5 |
| doctorが自プロセスの権限を見ない（status.json方式） | Task 2, Task 3, Task 5 |
| 権限の初回付与フロー（caveats） | Task 8 |
| 移行（二重起動対策、doctorの検出） | Task 4, Task 8, Task 10 |
| 配布（notarize-release.sh、cask廃止） | Task 7, Task 8 |
| アーキテクチャ（universal） | Task 7（specの「ビルドを通してから判断」は解決済み。universalビルドが通ったので`depends_on arch:`は不要） |
| ドキュメント（README×2言語、docs/index.html、tap） | Task 9, Task 8 Step 7 |
| `brew upgrade`がサービスを再起動するかの実測 | Task 8 Step 5 |

**2. Placeholder scan**

`Formula/opttab.rb` の `sha256` のみ意図的なプレースホルダで、Task 8 Step 2で
実際のRelease公開後の値に差し替える手順を明記している。他に未解決の記述は無い。

**3. Type consistency**

- `DaemonStatus` のプロパティ名（`pid`, `version`, `executablePath`,
  `accessibility`, `screenRecording`, `updatedAt`）はTask 2〜5で一貫している
- `StatusFile.path(forExecutable:)` はTask 2で定義、Task 3で使用
- `StatusFile.candidatePaths(prefixes:)` / `defaultPrefixes` はTask 2で定義、Task 5で使用
- `DaemonStatus.isFresh(_:now:tolerance:)` はTask 2で定義、Task 4で使用
- `DoctorReport.build(status:now:legacyExisting:)` はTask 4で定義、Task 5で使用
- `LegacyInstall.candidates` / `warnings(existing:)` はTask 4で定義、Task 5で使用
- `CLICommand.parse(_:)` / `helpText` はTask 1で定義、main.swiftで使用
- `OptTabVersion.current` はTask 1で定義、Task 3で使用

---

## 実行結果と積み残し（2026-08-15 追記）

Task 1〜7 と 9 を実行済み。**Task 8（Homebrew formula）と Task 10（マシンの後片付けとPR）は未実行。**
いずれも GitHub Release の公開物、`brew install`/`brew uninstall`、別リポジトリへの push を伴い、
ワークツリー外への副作用にあたるため保留した。

最終ブランチレビュー後の修正ウェーブで以下を追加で入れた（計画には無かった項目）。

- `Scripts/notarize-release.sh`: **ビルド済みバイナリ自身に `--version` を聞く検証**。
  `Support/Info.plist` は `unsafeFlags` の `-sectcreate` 経由なので llbuild のリンク入力として
  宣言されておらず（`.build/release.yaml` で確認済み）、バージョンだけ上げるとリンクがキャッシュ
  され、古い埋め込みバージョンのまま署名・公証・配布されうる
- `Scripts/install-local.sh`: `homebrew.mxcl.opttab` も bootout する。開発者が `brew services` も
  使っていると同じパスのエージェントが2つ走り、CGEventTap が二重になる
- `DaemonLaunchCheck`: `<prefix>/var/opttab/opttab` 以外のパスからの常駐を exit 3 で拒否する。
  formula が `bin.install` する以上 `$(brew --prefix)/bin/opttab` が PATH に載るため、
  素で `opttab` と打つと TCC 未登録の Cellar パスで2つ目のデーモンが立つ。
  開発用に `OPTTAB_ALLOW_ANY_PATH=1` で迂回できる
- `doctor`: 開発用 LaunchAgent を「旧インストールの残骸」と誤検出しなくなった
  （plist の `ProgramArguments[0]` が固定サービスパスなら正常とみなす）。
  加えて `kill(pid, 0)` による生存確認と、未起動時の権限を `unknown` 表示にする修正

### Task 8 に追加すべき検証（レビューで挙がった未計測リスク）

- **`post_install` の後に署名が保たれているか。** Homebrew は変更した arm64 バイナリを
  ad-hoc 再署名することがある。そうなると signing identifier が `opttab` になり、
  TCC 許可を発行したときの code requirement と一致しなくなって権限が飛ぶ。
  **この設計全体で最も価値の高い未計測項目。** ダウンロード直後ではなく
  `post_install` の後に確認すること。

  ```bash
  codesign -dv "$(brew --prefix)/var/opttab/opttab" 2>&1 \
    | grep -E 'Identifier=dev\.konaito\.opttab'
  ```

- cask を tap から削除した後、素の `brew install konaito/tap/opttab` が formula に
  解決されるか（計画の Step 4 は `--formula` を明示している）
- `brew upgrade` がサービスを自動再起動するか（計画 Task 8 Step 5。未計測のまま）

### 保留した項目

- **`doctor` は仕様が定めた3つのシグナルのうち1つしか見ていない。** 仕様（設計docの
  「CLI」節）は状態ファイルに加えて `launchctl print` の実行状態と、動作中の
  `OptTab.app` プロセスの検出を求めているが、実装は状態ファイルのみ。
  計画の Task 4/5 の時点で落ちており、実装は計画に忠実。
  影響: `keep_alive true` のクラッシュループは再起動のたびに新しい pid で
  新鮮な `status.json` を書くため、`doctor` は毎回 `running` と報告して異常を示さない。
  また、確認対象の2ディレクトリ外に置かれた旧 `.app` が動いていても警告が出ない。
  プロセス起動を伴うため `Doctor` の形とテスト戦略が変わる。Task 8 で実サービス相手に
  `doctor` を動かす場面があるので、そこで一緒に入れるのが安い
