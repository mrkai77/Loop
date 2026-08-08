//
//  ResizeContext.swift
//  Loop
//
//  Created by Kai Azim on 2026-01-19.
//

import Scribe
import SwiftUI

// MARK: - ResizeContext

/// Holds transient state for a window resize operation.
/// This context tracks the target frame and which edges to adjust during grow/shrink actions,
/// along with the window, screen, and bounds information needed to compute frames.
@Loggable
final class ResizeContext {
    struct PreparedWindowTarget {
        fileprivate let window: Window?
        fileprivate let resolvedWindowProperties: Window.ResolvedProperties?
        fileprivate let resolvedRecord: WindowRecords.ResolvedRecord?
    }

    private(set) var window: Window?

    private(set) var screen: NSScreen?
    private(set) var bounds: CGRect

    private(set) var padding: PaddingConfiguration = .zero
    private(set) var paddedBounds: CGRect

    private(set) var action: WindowAction = .init(.noSelection)
    private(set) var parentAction: WindowAction?

    /// Used for larger/smaller actions where the sides to adjust need to persist across frame calculations
    var sidesToAdjust: Edge.Set?

    /// Used to open radial menu at the correct position.
    private(set) var initialMousePosition: CGPoint = .zero

    var resolvedWindowProperties: Window.ResolvedProperties?
    var resolvedRecord: WindowRecords.ResolvedRecord?

    private(set) var cachedTargetFrame: ComputedFrame = .zero
    private var needsRecompute: Bool = false
    private var cycleActionCoordinator = CycleActionCoordinator()
    var lastAppliedFrame: CGRect?

    init(
        window: Window? = nil,
        initialFrame: CGRect? = nil,
        screen: NSScreen? = nil,
        bounds: CGRect? = nil,
        padding: PaddingConfiguration? = nil,
        action: WindowAction = .init(.noSelection),
        parentAction: WindowAction? = nil,
        initialMousePosition: CGPoint = .zero
    ) {
        let frame = initialFrame ?? window?.frame ?? .zero
        let bounds = bounds ?? screen?.cgSafeScreenFrame ?? .zero
        let padding = padding ?? PaddingConfiguration.getConfiguredPadding(for: screen)

        self.window = window
        self.cachedTargetFrame = ComputedFrame(raw: frame, normalized: .zero, padded: frame)
        self.screen = screen
        self.bounds = bounds
        self.padding = padding
        self.paddedBounds = padding.applyToBounds(bounds, screen: screen)
        self.action = action
        self.parentAction = parentAction
        self.initialMousePosition = initialMousePosition
        self.needsRecompute = !action.direction.isNoOp
    }

    func setScreen(to screen: NSScreen?) {
        self.screen = screen
        bounds = screen?.cgSafeScreenFrame ?? .zero
        padding = PaddingConfiguration.getConfiguredPadding(for: screen)
        paddedBounds = padding.applyToBounds(bounds, screen: screen)
        lastAppliedFrame = nil
        needsRecompute = true
    }

    /// Resolves the state needed before switching target windows
    @concurrent
    static func prepareWindowTarget(_ window: Window?) async -> PreparedWindowTarget {
        let resolvedWindowProperties = window.map(Window.ResolvedProperties.init(from:))
        let resolvedRecord: WindowRecords.ResolvedRecord? = if let window {
            await WindowRecords.ResolvedRecord(for: window)
        } else {
            nil
        }

        return PreparedWindowTarget(
            window: window,
            resolvedWindowProperties: resolvedWindowProperties,
            resolvedRecord: resolvedRecord
        )
    }

    /// Switches to a prepared target window and its resolved state
    func commitWindowTarget(_ target: PreparedWindowTarget) {
        let window = target.window

        self.window = window
        resolvedWindowProperties = target.resolvedWindowProperties
        resolvedRecord = target.resolvedRecord
        lastAppliedFrame = nil

        // Reset the cached base frame to the new window's actual frame. Otherwise a sequence
        // like `focus to another window > grow` would resize the newly-focused window using
        // the *previous* window's cached frame — grow/shrink/move read `cachedTargetFrame.raw`
        // as their base until a frame has been applied.
        if let window {
            let frame = window.frame
            cachedTargetFrame = ComputedFrame(raw: frame, normalized: .zero, padded: frame)
        }

        needsRecompute = true

        log.info("Set window to \(window?.description ?? "nil")")
    }

    func proposeCycleAction(
        in cycleAction: WindowAction,
        restartAtBeginningWhenInterrupted: Bool,
        mode: CycleActionCoordinator.SelectionMode
    ) -> CycleActionCoordinator.Proposal? {
        cycleActionCoordinator.proposeAction(
            for: window?.cgWindowID ?? 0,
            in: cycleAction,
            currentAction: action,
            currentParentAction: parentAction,
            recordedAction: resolvedRecord?.currentAction,
            restartAtBeginningWhenInterrupted: restartAtBeginningWhenInterrupted,
            mode: mode
        )
    }

    func commitCycleAction(
        _ proposal: CycleActionCoordinator.Proposal,
        in cycleAction: WindowAction
    ) -> WindowAction? {
        cycleActionCoordinator.commit(
            proposal,
            for: window?.cgWindowID ?? 0,
            in: cycleAction
        )
    }

    func setAction(
        to newAction: WindowAction,
        parent newParentAction: WindowAction?
    ) {
        cycleActionCoordinator.recordActionTransition(
            from: action,
            currentParentAction: parentAction,
            to: newAction,
            newParentAction: newParentAction
        )

        action = newAction
        parentAction = newParentAction
        needsRecompute = true
    }

    /// Re-fetches the window's AX properties and record snapshot from the actor.
    func refreshResolvedState() async {
        guard let window else {
            resolvedWindowProperties = nil
            resolvedRecord = nil
            return
        }

        resolvedWindowProperties = Window.ResolvedProperties(from: window)
        resolvedRecord = await WindowRecords.ResolvedRecord(for: window)
    }

    /// Creates a lightweight child context that shares this context's resolved state but uses a different action and bounds.
    /// Used for recursive frame resolution (e.g. undo) without additional AX calls.
    func derivedContext(action newAction: WindowAction, bounds newBounds: CGRect) -> ResizeContext {
        // Pass window: nil to skip eager AX resolution in init; we overwrite with the parent's (the currently stored) snapshot.
        let context = ResizeContext(
            initialFrame: resolvedWindowProperties?.frame,
            screen: screen,
            bounds: newBounds,
            padding: .zero,
            action: newAction,
            initialMousePosition: initialMousePosition
        )
        context.window = window
        context.resolvedWindowProperties = resolvedWindowProperties
        context.resolvedRecord = resolvedRecord
        context.sidesToAdjust = sidesToAdjust
        return context
    }

    func getTargetFrame() -> ComputedFrame {
        if needsRecompute {
            recomputeTargetFrame()
        }

        return cachedTargetFrame
    }

    private func recomputeTargetFrame() {
        // Clear the recompute guard *before* resolving so this method is re-entrancy safe:
        // if `WindowFrameResolver.getFrame` ever reads `getTargetFrame()` on this same
        // context while it is still being computed, the guard is already clear and the
        // re-entrant call returns the cached frame instead of recomputing and recursing
        // until the stack overflows.
        needsRecompute = false

        // Actions with no target frame return a zero-size sentinel from `getFrame`; caching it
        // would clobber the base frame that a later grow/shrink/move reads. Keep the real cached
        // frame. (Uses `WindowDirection.hasTargetFrame`, shared with `WindowFrameResolver`.)
        guard action.direction.hasTargetFrame else {
            return
        }

        let result = WindowFrameResolver.getFrame(resizeContext: self)

        let normalized = CGRect(
            x: (result.frame.minX - bounds.minX) / bounds.width,
            y: (result.frame.minY - bounds.minY) / bounds.height,
            width: result.frame.width / bounds.width,
            height: result.frame.height / bounds.height
        )

        let paddedFrame = padding.applyToWindow(
            frame: result.frame,
            paddedBounds: paddedBounds,
            action: action,
            resolvedWindowProperties: resolvedWindowProperties
        )

        cachedTargetFrame = ComputedFrame(
            raw: result.frame,
            normalized: normalized,
            padded: paddedFrame
        )

        log.info("Computed target frame - raw: \(cachedTargetFrame.raw), normalized: \(cachedTargetFrame.normalized) padded: \(cachedTargetFrame.padded), for action: \(action)")
    }
}

// MARK: - ComputedFrame

extension ResizeContext {
    /// Holds both the raw (non-padded) and padded target frames for a resize operation.
    struct ComputedFrame: Equatable {
        /// The frame calculated without any padding applied.
        let raw: CGRect

        /// The frame inside a 1x1 frame, used for radial menu angle calculations.
        let normalized: CGRect

        /// The frame with padding applied (outer bounds padding + inner window padding).
        /// When no padding is configured, this equals `raw`.
        var padded: CGRect

        static let zero = ComputedFrame(raw: .zero, normalized: .zero, padded: .zero)

        init(raw: CGRect, normalized: CGRect, padded: CGRect) {
            self.raw = raw
            self.normalized = normalized
            self.padded = padded
        }
    }
}
