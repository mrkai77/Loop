//
//  WindowAction+Geometry.swift
//  Loop
//
//  Created by Kai Azim on 2026-11-14.
//

import Foundation

extension WindowAction {
    var size: ActionSize? {
        get {
            switch kind {
            case let .custom(payload): payload.size
            case let .stash(payload): payload.size
            default: nil
            }
        }
        set {
            guard let newValue else { return }
            switch kind {
            case var .custom(payload): payload.size = newValue; kind = .custom(payload)
            case var .stash(payload): payload.size = newValue; kind = .stash(payload)
            default: break
            }
        }
    }

    /// Includes the no-window preview fallback of `preserve` and `initial` sizes.
    var customDimensions: ActionDimensions? {
        get {
            if case let .custom(width, height) = size { return .init(width: width, height: height) }
            switch kind {
            case let .custom(payload): return payload.fallbackSize
            case let .stash(payload): return payload.fallbackSize
            default: return nil
            }
        }
        set {
            guard let newValue else { return }
            if case .custom = size {
                size = .custom(width: newValue.width, height: newValue.height)
                return
            }
            switch kind {
            case var .custom(payload): payload.fallbackSize = newValue; kind = .custom(payload)
            case var .stash(payload): payload.fallbackSize = newValue; kind = .stash(payload)
            default: break
            }
        }
    }

    var position: ActionPosition? {
        get {
            switch kind {
            case let .custom(payload): payload.position
            case let .stash(payload): payload.position
            default: nil
            }
        }
        set {
            guard let newValue else { return }
            switch kind {
            case var .custom(payload): payload.position = newValue; kind = .custom(payload)
            case var .stash(payload): payload.position = newValue; kind = .stash(payload)
            default: break
            }
        }
    }
}
