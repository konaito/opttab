import AppKit
import CoreGraphics

@MainActor
public final class SwitcherController: HotkeyMonitorDelegate {
    private var state: SwitcherState?
    private var snapshot: WindowSnapshot?
    private var activating = false
    private var generation = 0
    private var thumbnailTasks: [Task<Void, Never>] = []

    private let provider = WindowProvider()
    private let thumbnails = ThumbnailService()
    private let model = SwitcherViewModel()
    private lazy var panel = SwitcherPanel(model: model)

    public init() {
        model.onSelect = { [weak self] index in
            guard let self else { return }
            self.state?.select(index)
            self.commit()
        }
    }

    public var isSessionActive: Bool { state != nil || activating }

    public func handle(_ action: HotkeyAction) {
        switch action {
        case .activate(let reverse):
            activate(reverse: reverse)
        case .cycle(let reverse):
            if reverse { state?.selectPrevious() } else { state?.selectNext() }
            syncSelection()
        case .commit:
            commit()
        case .cancel:
            cancel()
        case .passthrough:
            break
        }
    }

    private func activate(reverse: Bool) {
        guard state == nil, !activating else { return }
        activating = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.activating = false }

            let snap: WindowSnapshot?
            do {
                snap = try await self.provider.snapshot()
            } catch {
                NSLog("OptTab: snapshot failed: \(error)")
                return
            }
            guard let snap, let st = SwitcherState(windows: snap.windows, reverse: reverse)
            else { return }  // ウィンドウ2枚未満 → 何もしない

            self.snapshot = snap
            self.state = st
            self.model.cards = snap.windows.map { w in
                SwitcherViewModel.Card(id: w.id, title: w.title,
                                       thumbnail: nil, appIcon: snap.appIcon,
                                       isMinimized: w.isMinimized)
            }
            self.model.selectedIndex = st.selectedIndex
            self.panel.show()
            self.loadThumbnails(snap, generation: self.generation)

            // スナップショット取得中にOptionが離されていたら即確定（即離しトグル）
            if !CGEventSource.flagsState(.combinedSessionState)
                .contains(.maskAlternate) {
                self.commit()
            }
        }
    }

    private func loadThumbnails(_ snap: WindowSnapshot, generation: Int) {
        for window in snap.windows {
            guard let scWindow = snap.scWindows[window.id] else { continue }
            let task = Task { @MainActor [weak self] in
                guard let self else { return }
                // キャッシュを先に出し、新しいスクショで差し替え
                if let cached = await self.thumbnails.cached(for: window.id) {
                    guard !Task.isCancelled, generation == self.generation else { return }
                    self.setThumbnail(cached, for: window.id)
                }
                if let fresh = await self.thumbnails.capture(scWindow) {
                    guard !Task.isCancelled, generation == self.generation else { return }
                    self.setThumbnail(fresh, for: window.id)
                }
            }
            thumbnailTasks.append(task)
        }
    }

    private func setThumbnail(_ image: CGImage, for id: UInt32) {
        guard let idx = model.cards.firstIndex(where: { $0.id == id }) else { return }
        model.cards[idx].thumbnail = image
    }

    private func syncSelection() {
        if let st = state { model.selectedIndex = st.selectedIndex }
    }

    private func commit() {
        guard let st = state, let snap = snapshot else { return }
        panel.hide()
        generation += 1
        thumbnailTasks.forEach { $0.cancel() }
        thumbnailTasks.removeAll()
        state = nil
        snapshot = nil
        FocusService.focus(windowID: st.selected.id, snapshot: snap)
    }

    private func cancel() {
        panel.hide()
        generation += 1
        thumbnailTasks.forEach { $0.cancel() }
        thumbnailTasks.removeAll()
        state = nil
        snapshot = nil
    }
}
