//
//  SkyLightSymbolLoader.swift
//  Loop
//
//  Created by Kai Azim on 2025-11-27.
//

import CoreGraphics
import Darwin
import Scribe

@Loggable(style: .static)
enum SkyLightSymbolLoader {
    private static let frameworkPath = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"

    private static let handle: UnsafeMutableRawPointer? = {
        guard let handle = dlopen(frameworkPath, RTLD_LAZY) else {
            log.error("failed to open \(frameworkPath)")
            return nil
        }
        return handle
    }()

    private static func loadSymbol<T>(_ name: StaticString) -> T? {
        guard let handle else {
            log.error("no handle; cannot load symbol \(name)")
            return nil
        }

        // Clear any prior error
        dlerror()

        guard let sym = dlsym(handle, name.description) else {
            if let err = dlerror() {
                log.error("failed to load symbol \(name): \(String(cString: err))")
            } else {
                log.error("failed to load symbol \(name)")
            }
            return nil
        }

        return unsafeBitCast(sym, to: T.self)
    }
}

extension SkyLightSymbolLoader {
    typealias SLSMainConnectionIDFunc = @convention(c) () -> SLSConnectionID
    static let SLSMainConnectionID: SLSMainConnectionIDFunc? = loadSymbol("SLSMainConnectionID")

    typealias SLSDefaultConnectionForThreadFunc = @convention(c) () -> SLSConnectionID
    static let SLSDefaultConnectionForThread: SLSDefaultConnectionForThreadFunc? = loadSymbol("SLSDefaultConnectionForThread")

    typealias SLSWindowQueryWindowsFunc = @convention(c) (_ cid: SLSConnectionID, _ windows: CFArray?, _ count: UInt32) -> CFTypeRef
    static let SLSWindowQueryWindows: SLSWindowQueryWindowsFunc? = loadSymbol("SLSWindowQueryWindows")

    typealias SLSWindowQueryResultCopyWindowsFunc = @convention(c) (_ query: CFTypeRef) -> CFTypeRef
    static let SLSWindowQueryResultCopyWindows: SLSWindowQueryResultCopyWindowsFunc? = loadSymbol("SLSWindowQueryResultCopyWindows")

    typealias SLSWindowIteratorGetCountFunc = @convention(c) (_ iterator: CFTypeRef) -> UInt32
    static let SLSWindowIteratorGetCount: SLSWindowIteratorGetCountFunc? = loadSymbol("SLSWindowIteratorGetCount")

    typealias SLSWindowIteratorAdvanceFunc = @convention(c) (_ iterator: CFTypeRef) -> Bool
    static let SLSWindowIteratorAdvance: SLSWindowIteratorAdvanceFunc? = loadSymbol("SLSWindowIteratorAdvance")

    typealias SLSWindowIteratorGetWindowIDFunc = @convention(c) (_ iterator: CFTypeRef) -> CGWindowID
    static let SLSWindowIteratorGetWindowID: SLSWindowIteratorGetWindowIDFunc? = loadSymbol("SLSWindowIteratorGetWindowID")

    typealias SLSWindowIteratorGetParentIDFunc = @convention(c) (_ iterator: CFTypeRef) -> CGWindowID
    static let SLSWindowIteratorGetParentID: SLSWindowIteratorGetParentIDFunc? = loadSymbol("SLSWindowIteratorGetParentID")

    /// Returned value can be converted into `SLSWindowTags`.
    typealias SLSWindowIteratorGetTagsFunc = @convention(c) (_ iterator: CFTypeRef) -> UInt64
    static let SLSWindowIteratorGetTags: SLSWindowIteratorGetTagsFunc? = loadSymbol("SLSWindowIteratorGetTags")

    // We just use `SLSGetWindowLevel` directly instead
//    typealias SLSWindowIteratorGetLevelFunc = @convention(c) (_ iterator: CFTypeRef) -> CGWindowLevel
//    static let SLSWindowIteratorGetLevel: SLSWindowIteratorGetLevelFunc? = loadSymbol("SLSWindowIteratorGetLevel")

    // As of macOS 26.3, `SLSWindowIteratorGetAttributes` will always return `0` based on disassembly
//    typealias SLSWindowIteratorGetAttributesFunc = @convention(c) (_ iterator: CFTypeRef) -> UInt64
//    static let SLSWindowIteratorGetAttributes: SLSWindowIteratorGetAttributesFunc? = loadSymbol("SLSWindowIteratorGetAttributes")

    /// All four corner radii values returned in the array will be identical to each other, as seen in: https://gist.github.com/MrKai77/654975cc2a35cfa5328a7c0a90a01fde
    @available(macOS 26.0, *)
    typealias SLSWindowIteratorGetResolvedCornerRadiiFunc = @convention(c) (_ iterator: CFTypeRef, _ wid: UInt32) -> Unmanaged<CFArray>
    @available(macOS 26.0, *)
    static let SLSWindowIteratorGetResolvedCornerRadii: SLSWindowIteratorGetResolvedCornerRadiiFunc? = loadSymbol("SLSWindowIteratorGetResolvedCornerRadii")

    typealias SLSFindWindowByGeometryFunc = @convention(c) (
        _ cid: SLSConnectionID,
        _ filterWindowID: CGWindowID,
        _ flags: Int32,
        _ reserved: Int32,
        _ screenPoint: UnsafePointer<CGPoint>,
        _ outWindowPoint: UnsafeMutablePointer<CGPoint>,
        _ outWindowID: UnsafeMutablePointer<CGWindowID>,
        _ outWindowCID: UnsafeMutablePointer<Int32>
    ) -> CGError
    static let SLSFindWindowByGeometry: SLSFindWindowByGeometryFunc? = loadSymbol("SLSFindWindowByGeometry")

    /// Returns the UUID (`CFString`) of the display containing `point`, using the same
    /// tie-breaking WindowServer uses internally. `nil` if no managed display contains it.
    typealias SLSCopyBestManagedDisplayForPointFunc = @convention(c) (
        _ cid: SLSConnectionID,
        _ point: CGPoint
    ) -> Unmanaged<CFString>?
    static let SLSCopyBestManagedDisplayForPoint: SLSCopyBestManagedDisplayForPointFunc? = loadSymbol("SLSCopyBestManagedDisplayForPoint")

    typealias SLSSetWindowBackgroundBlurRadiusFunc = @convention(c) (_ connection: SLSConnectionID, _ wid: CGWindowID, _ radius: Int) -> OSStatus
    static let SLSSetWindowBackgroundBlurRadius: SLSSetWindowBackgroundBlurRadiusFunc? = loadSymbol("SLSSetWindowBackgroundBlurRadius")

    typealias SLSGetWindowLevelFunc = @convention(c) (_ cid: SLSConnectionID, _ wid: CGWindowID, _ outLevel: UnsafeMutablePointer<Int32>) -> CGError
    static let SLSGetWindowLevel: SLSGetWindowLevelFunc? = loadSymbol("SLSGetWindowLevel")

    /// Options are described by `SLSWindowCaptureOptions`
    typealias SLSHWCaptureWindowListFunc = @convention(c) (_ cid: SLSConnectionID, _ windowList: UnsafeMutablePointer<CGWindowID>, _ windowCount: Int, _ options: UInt32) -> Unmanaged<CFArray>
    static let SLSHWCaptureWindowList: SLSHWCaptureWindowListFunc? = loadSymbol("SLSHWCaptureWindowList")

    /// For mode, pass in `kCPSUserGenerated` (defined further down).
    typealias SLPSSetFrontProcessWithOptionsFunc = @convention(c) (_ psn: UnsafeMutablePointer<ProcessSerialNumber>, _ wid: UInt32, _ mode: UInt32) -> CGError
    static let SLPSSetFrontProcessWithOptions: SLPSSetFrontProcessWithOptionsFunc? = loadSymbol("_SLPSSetFrontProcessWithOptions")

    typealias SLPSPostEventRecordToFunc = @convention(c) (_ psn: UnsafeMutablePointer<ProcessSerialNumber>, _ bytes: UnsafeMutablePointer<UInt8>) -> CGError
    static let SLPSPostEventRecordTo: SLPSPostEventRecordToFunc? = loadSymbol("SLPSPostEventRecordTo")
}

typealias SLSConnectionID = UInt32

struct SLSWindowCaptureOptions: OptionSet {
    let rawValue: UInt32

    static let ignoreGlobalClipShape = Self(rawValue: 1 << 11)

    /// On a retina display, this captures at 1 pt : 4 px
    static let nominalResolution = Self(rawValue: 1 << 9)

    /// Captures at 1 pt : 1px
    static let bestResolution = Self(rawValue: 1 << 8)

    /// When Stage Manager is enabled, screenshots can become skewed. This param gets us full-size screenshots regardless
    static let fullSize = Self(rawValue: 1 << 19)
}

enum SLSSpaceMask: Int32 {
    case onScreenManaged = 5
    case offScreenManaged = 6
    case allManaged = 7
}

let kCPSUserGenerated: UInt32 = 0x200
