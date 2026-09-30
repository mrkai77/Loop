//
//  CycleProgressStore.swift
//  Loop
//
//  Created by Kai Azim on 2026-08-28.
//

import CoreGraphics
import Foundation

/// Tracks cycle progress by target window and parent cycle
struct CycleProgressStore {
    enum Direction {
        case forward
        case backward
    }

    struct Selection {
        let action: WindowAction
        let index: Int

        fileprivate let key: Key

        fileprivate init(action: WindowAction, index: Int, key: Key) {
            self.action = action
            self.index = index
            self.key = key
        }
    }

    fileprivate struct Key: Hashable {
        let targetWindowID: CGWindowID
        let parentCycleActionID: UUID
    }

    /// Keeps the selected occurrence when a cycle contains duplicate children
    private struct Cursor {
        let childActionID: UUID
        let lastKnownIndex: Int
    }

    private var cursors: [Key: Cursor] = [:]

    enum Origin {
        /// This session's last selection, which also tells duplicate children apart, or `fallback` without one
        case sessionProgress(fallback: WindowAction?)
        /// `action`, or before the first child if it's `nil` or not part of the cycle
        case action(WindowAction?)
    }

    /// Returns the child `direction` moves to from `origin`, or `origin` itself without a direction.
    /// Doesn't update progress until the selection is committed.
    mutating func proposeSelection(
        for targetWindowID: CGWindowID,
        in cycleAction: WindowAction,
        from origin: Origin,
        moving direction: Direction?
    ) -> Selection? {
        let key = Key(
            targetWindowID: targetWindowID,
            parentCycleActionID: cycleAction.id
        )

        guard cycleAction.direction == .cycle,
              let children = cycleAction.cycle,
              !children.isEmpty
        else {
            cursors[key] = nil
            return nil
        }

        let originIndex: Int? = switch origin {
        case let .sessionProgress(fallback):
            sessionIndex(for: key, in: children, matching: fallback) ?? index(of: fallback, in: children)
        case let .action(action):
            index(of: action, in: children)
        }

        let index = if let originIndex, let direction {
            nextIndex(after: originIndex, count: children.count, direction: direction)
        } else {
            originIndex ?? 0
        }

        return Selection(action: children[index], index: index, key: key)
    }

    /// Records and returns a selection only if it still matches the current cycle
    mutating func commit(
        _ selection: Selection,
        for targetWindowID: CGWindowID,
        in cycleAction: WindowAction
    ) -> WindowAction? {
        let key = Key(
            targetWindowID: targetWindowID,
            parentCycleActionID: cycleAction.id
        )

        guard key == selection.key else {
            return nil
        }

        guard cycleAction.direction == .cycle,
              let children = cycleAction.cycle,
              !children.isEmpty
        else {
            cursors[key] = nil
            return nil
        }

        let acceptedIndex: Int? = if children.indices.contains(selection.index),
                                     children[selection.index].id == selection.action.id {
            selection.index
        } else {
            children.firstIndex(where: { $0.id == selection.action.id })
        }

        guard let acceptedIndex else {
            cursors[key] = nil
            return nil
        }

        let acceptedAction = children[acceptedIndex]
        cursors[key] = Cursor(
            childActionID: acceptedAction.id,
            lastKnownIndex: acceptedIndex
        )
        return acceptedAction
    }

    /// The session's last selection, if it's still in the cycle and is `action` (when given)
    private func sessionIndex(for key: Key, in children: [WindowAction], matching action: WindowAction?) -> Int? {
        guard let cursor = cursors[key],
              action == nil || cursor.childActionID == action?.id
        else {
            return nil
        }

        return validatedIndex(for: cursor, in: children)
    }

    private func index(of action: WindowAction?, in children: [WindowAction]) -> Int? {
        guard let action else { return nil }
        return children.firstIndex { $0.id == action.id }
    }

    private func validatedIndex(for cursor: Cursor, in children: [WindowAction]) -> Int? {
        if children.indices.contains(cursor.lastKnownIndex),
           children[cursor.lastKnownIndex].id == cursor.childActionID {
            return cursor.lastKnownIndex
        }

        return children.firstIndex(where: { $0.id == cursor.childActionID })
    }

    private func nextIndex(after index: Int, count: Int, direction: Direction) -> Int {
        switch direction {
        case .forward:
            (index + 1) % count
        case .backward:
            index == 0 ? count - 1 : index - 1
        }
    }
}
