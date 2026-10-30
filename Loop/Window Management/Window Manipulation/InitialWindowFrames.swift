import SwiftUI

/// Pure policy for initial placement; no action history or last-used action is involved.
enum InitialWindowFrames {
    static func defaultAction(name: String) -> WindowAction {
        WindowAction(
            .custom,
            keybind: [],
            name: name,
            unit: .percentage,
            anchor: .center,
            width: 75,
            height: 75,
            positionMode: .generic,
            sizeMode: .custom
        )
    }

    static func frame(for action: WindowAction, bounds: CGRect, currentSize: CGSize, resizedSize: CGSize? = nil) -> CGRect? {
        guard action.direction == .custom, action.sizeMode == .custom,
              bounds.width > 0, bounds.height > 0 else { return nil }
        var geometry = action
        if resizedSize != nil { geometry.sizeMode = .preserveSize }
        var frame = WindowFrameResolver.customFrame(for: geometry, bounds: bounds, currentSize: resizedSize ?? currentSize)
        guard [frame.minX, frame.minY, frame.width, frame.height, bounds.minX, bounds.minY, bounds.width, bounds.height].allSatisfy(\.isFinite),
              frame.width > 0, frame.height > 0 else { return nil }
        // Respect the size an app actually accepted, even if its minimum exceeds the display.
        if resizedSize == nil {
            frame.size.width = min(frame.width, bounds.width)
            frame.size.height = min(frame.height, bounds.height)
        }
        frame.origin.x = max(bounds.minX, min(frame.minX, bounds.maxX - frame.width))
        frame.origin.y = max(bounds.minY, min(frame.minY, bounds.maxY - frame.height))
        return frame
    }
}

/// AX can report a launch window both in its initial enumeration and in a notification.
/// Keep identities for the observer's lifetime, forgetting them when windows are destroyed.
struct InitialWindowTracker<Element: Equatable> {
    private var seen: [Element]

    init(existing: [Element] = []) { self.seen = existing }

    mutating func insert(_ element: Element) -> Bool {
        guard !seen.contains(element) else { return false }
        seen.append(element)
        return true
    }

    mutating func remove(_ element: Element) { seen.removeAll { $0 == element } }
}
