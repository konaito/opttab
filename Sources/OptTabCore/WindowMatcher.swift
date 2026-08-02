import CoreGraphics

public struct AXWindowDescriptor: Equatable {
    public let title: String
    public let frame: CGRect
    public let isMinimized: Bool

    public init(title: String, frame: CGRect, isMinimized: Bool) {
        self.title = title
        self.frame = frame
        self.isMinimized = isMinimized
    }
}

public enum WindowMatcher {
    /// CGウィンドウ列とAXウィンドウ列を突き合わせて windowID → AX index を返す。
    /// 1) タイトル完全一致 → 2) フレーム近似 → 3) 残りを前面順で割り当て
    public static func match(cg: [WindowInfo],
                             ax: [AXWindowDescriptor]) -> [UInt32: Int] {
        var result: [UInt32: Int] = [:]
        var usedAX = Set<Int>()

        // pass 1: タイトル完全一致（タイトルが空でないもののみ、フレームが近い候補を優先）
        for w in cg where !w.title.isEmpty {
            let candidates = ax.indices.filter {
                !usedAX.contains($0) && ax[$0].title == w.title
            }
            let best = candidates.min { a, b in
                distance(ax[a].frame, w.frame) < distance(ax[b].frame, w.frame)
            }
            if let i = best {
                result[w.id] = i
                usedAX.insert(i)
            }
        }
        // pass 2: フレーム近似一致
        for w in cg where result[w.id] == nil {
            if let i = ax.indices.first(where: {
                !usedAX.contains($0) && approxEqual(ax[$0].frame, w.frame)
            }) {
                result[w.id] = i
                usedAX.insert(i)
            }
        }
        // pass 3: 残り物を前面順で割り当て
        for w in cg where result[w.id] == nil {
            if let i = ax.indices.first(where: { !usedAX.contains($0) }) {
                result[w.id] = i
                usedAX.insert(i)
            }
        }
        return result
    }

    static func approxEqual(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.midX - b.midX) < 20 && abs(a.midY - b.midY) < 20 &&
        abs(a.width - b.width) < 20 && abs(a.height - b.height) < 20
    }

    static func distance(_ a: CGRect, _ b: CGRect) -> CGFloat {
        abs(a.midX - b.midX) + abs(a.midY - b.midY)
    }
}
