import AppKit
import SwiftUI

@MainActor
public final class SwitcherViewModel: ObservableObject {
    public struct Card: Identifiable {
        public let id: UInt32
        public let title: String
        public var thumbnail: CGImage?
        public let appIcon: NSImage?
        public let isMinimized: Bool

        public init(id: UInt32, title: String, thumbnail: CGImage?,
                    appIcon: NSImage?, isMinimized: Bool) {
            self.id = id
            self.title = title
            self.thumbnail = thumbnail
            self.appIcon = appIcon
            self.isMinimized = isMinimized
        }
    }

    @Published public var cards: [Card] = []
    @Published public var selectedIndex: Int = 0
    public var onSelect: ((Int) -> Void)?

    public init() {}
}

struct SwitcherView: View {
    @ObservedObject var model: SwitcherViewModel

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(model.cards.enumerated()), id: \.element.id) { index, card in
                VStack(spacing: 6) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .underPageBackgroundColor))
                        if let thumb = card.thumbnail {
                            Image(decorative: thumb, scale: 2)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .padding(4)
                        } else if let icon = card.appIcon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 56, height: 56)
                        }
                        if card.isMinimized {
                            Image(systemName: "arrow.down.right.square")
                                .font(.system(size: 18))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity,
                                       alignment: .bottomTrailing)
                                .padding(8)
                        }
                    }
                    .frame(width: 220, height: 148)

                    Text(card.title.isEmpty ? "(無題)" : card.title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 220)
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(index == model.selectedIndex
                              ? Color.accentColor.opacity(0.22) : .clear))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(index == model.selectedIndex
                                ? Color.accentColor : .clear, lineWidth: 2))
                .onTapGesture { model.onSelect?(index) }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .padding(24)
    }
}

@MainActor
public final class SwitcherPanel: NSPanel {
    public init(model: SwitcherViewModel) {
        super.init(contentRect: .zero,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false  // Material側の影に任せる
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        contentView = NSHostingView(rootView: SwitcherView(model: model))
    }

    /// マウスのあるスクリーンの中央に表示（フォーカスは奪わない）
    public func show() {
        guard let screen = NSScreen.screens.first(where: {
            NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
        }) ?? NSScreen.main else { return }
        let size = contentView?.fittingSize ?? NSSize(width: 400, height: 220)
        setContentSize(size)
        setFrameOrigin(NSPoint(x: screen.frame.midX - size.width / 2,
                               y: screen.frame.midY - size.height / 2))
        orderFrontRegardless()
    }

    public func hide() {
        orderOut(nil)
    }
}
