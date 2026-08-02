import CoreGraphics

public enum WindowOrdering {
    /// レイヤー0以外と、タイトル空かつ極小のウィンドウ（ツールチップ・パネル類）を除外
    public static func eligible(_ windows: [WindowInfo]) -> [WindowInfo] {
        windows.filter { w in
            guard w.layer == 0 else { return false }
            if w.title.isEmpty && (w.frame.width < 200 || w.frame.height < 150) {
                return false
            }
            return true
        }
    }

    /// frontOrder（前面→背面のCGWindowID列）にあるものはその順で先頭に、
    /// 無いもの（別Space・最小化）は後ろにタイトル昇順で並べる
    public static func sortedByFrontOrder(_ windows: [WindowInfo],
                                          frontOrder: [UInt32]) -> [WindowInfo] {
        let rank = Dictionary(uniqueKeysWithValues:
            frontOrder.enumerated().map { ($1, $0) })
        return windows.sorted { a, b in
            switch (rank[a.id], rank[b.id]) {
            case let (ra?, rb?): return ra < rb
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return a.title < b.title
            }
        }
    }

    /// frontID のウィンドウを先頭へ移動（他の相対順は維持）
    public static func ordered(_ windows: [WindowInfo],
                               frontID: UInt32?) -> [WindowInfo] {
        guard let frontID,
              let idx = windows.firstIndex(where: { $0.id == frontID }),
              idx != 0 else { return windows }
        var result = windows
        let front = result.remove(at: idx)
        result.insert(front, at: 0)
        return result
    }
}
