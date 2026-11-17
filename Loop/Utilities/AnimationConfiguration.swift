//
//  AnimationConfiguration.swift
//  Loop
//
//  Created by Kai Azim on 2023-10-27.
//

import SwiftUI
import Tome

enum AnimationConfiguration: String, Codable, CaseIterable, Identifiable, Tome.Serializable {
    var id: Self { self }

    case fluid
    case relaxed
    case snappy
    case brisk
    case instant

    var name: LocalizedStringKey {
        switch self {
        case .fluid:
            "Fluid"
        case .relaxed:
            "Relaxed"
        case .snappy:
            "Snappy"
        case .brisk:
            "Brisk"
        case .instant:
            "Instant"
        }
    }

    // MARK: Preview Window

    var previewWindow: Animation? {
        switch self {
        case .fluid:
            .timingCurve(0, 0.26, 0.45, 1, duration: 0.325)
        case .relaxed:
            .timingCurve(0.15, 0.8, 0.46, 1, duration: 0.3)
        case .snappy:
            .timingCurve(0.22, 1, 0.47, 1, duration: 0.25)
        case .brisk:
            .timingCurve(0.25, 1, 0.48, 1, duration: 0.15)
        default:
            nil
        }
    }

    // MARK: Radial Menu

    var radialMenuSize: Animation {
        switch self {
        case .fluid:
            .easeOut(duration: 0.2)
        case .relaxed:
            .easeOut(duration: 0.2)
        case .snappy:
            .easeOut(duration: 0.2)
        case .brisk:
            .easeOut(duration: 0.15)
        case .instant:
            .easeOut(duration: 0.1)
        }
    }

    var radialMenuAngle: Animation {
        if self == .instant {
            .linear(duration: 0)
        } else {
            .timingCurve(0.22, 1, 0.36, 1, duration: 0.2)
        }
    }

    var animateRadialMenuAppearance: Bool {
        self != .instant
    }
}
