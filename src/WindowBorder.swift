import Cocoa

// A border around the focused window, drawn in a window of our own that the window server keeps
// ordered just below it.
//
// The window server work goes through private SkyLight functions, looked up at runtime. They are
// what tools like yabai and JankyBorders build on: they deliver move and resize notifications in
// step with the window server, so the border keeps up with drags, and need no Accessibility
// permission. Which window has focus is worked out from public APIs where possible.

private enum SkyLight {
    typealias NotifyProc = @convention(c) (UInt32, UnsafeMutableRawPointer?, Int, UnsafeMutableRawPointer?) -> Void

    private static let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

    private static func load<T>(_ name: String, _ type: T.Type) -> T? {
        let symbol = handle.flatMap { dlsym($0, name) } ?? dlsym(UnsafeMutableRawPointer(bitPattern: -2), name)
        return symbol.map { unsafeBitCast($0, to: type) }
    }

    static let mainConnectionID = load("SLSMainConnectionID", (@convention(c) () -> Int32).self)
    static let newConnection = load("SLSNewConnection", (@convention(c) (Int32, UnsafeMutablePointer<Int32>) -> CGError).self)
    static let registerNotifyProc = load("SLSRegisterNotifyProc", (@convention(c) (NotifyProc, UInt32, UnsafeMutableRawPointer?) -> CGError).self)
    static let requestNotificationsForWindows = load("SLSRequestNotificationsForWindows", (@convention(c) (Int32, UnsafePointer<UInt32>?, Int32) -> CGError).self)
    static let getActiveSpace = load("CGSGetActiveSpace", (@convention(c) (Int32) -> UInt64).self)
    static let copySpacesForWindows = load("SLSCopySpacesForWindows", (@convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?).self)
    static let getWindowBounds = load("SLSGetWindowBounds", (@convention(c) (Int32, UInt32, UnsafeMutablePointer<CGRect>) -> CGError).self)
    static let windowIsOrderedIn = load("SLSWindowIsOrderedIn", (@convention(c) (Int32, UInt32, UnsafeMutablePointer<Bool>) -> CGError).self)

    static let newRegionWithRect = load("CGSNewRegionWithRect", (@convention(c) (UnsafePointer<CGRect>, UnsafeMutablePointer<Unmanaged<CFTypeRef>?>) -> CGError).self)
    static let newWindow = load("SLSNewWindow", (@convention(c) (Int32, Int32, Float, Float, CFTypeRef, UnsafeMutablePointer<UInt32>) -> CGError).self)
    static let releaseWindow = load("SLSReleaseWindow", (@convention(c) (Int32, UInt32) -> CGError).self)
    static let setWindowTags = load("SLSSetWindowTags", (@convention(c) (Int32, UInt32, UnsafePointer<UInt64>, Int32) -> CGError).self)
    static let setWindowShape = load("SLSSetWindowShape", (@convention(c) (Int32, UInt32, Float, Float, CFTypeRef) -> CGError).self)
    static let setWindowResolution = load("SLSSetWindowResolution", (@convention(c) (Int32, UInt32, Double) -> CGError).self)
    static let setWindowOpacity = load("SLSSetWindowOpacity", (@convention(c) (Int32, UInt32, Bool) -> CGError).self)
    static let setWindowShadowProperties = load("SLSWindowSetShadowProperties", (@convention(c) (UInt32, CFDictionary) -> CGError).self)
    static let windowContextCreate = load("SLWindowContextCreate", (@convention(c) (Int32, UInt32, CFDictionary?) -> Unmanaged<CGContext>?).self)
    static let flushWindowContentRegion = load("SLSFlushWindowContentRegion", (@convention(c) (Int32, UInt32, UnsafeMutableRawPointer?) -> CGError).self)
    static let windowFreeze = load("SLSWindowFreezeWithOptions", (@convention(c) (Int32, UInt32, CFTypeRef?) -> CGError).self)
    static let windowThaw = load("SLSWindowThaw", (@convention(c) (Int32, UInt32) -> CGError).self)
    static let disableUpdate = load("SLSDisableUpdate", (@convention(c) (Int32) -> CGError).self)
    static let reenableUpdate = load("SLSReenableUpdate", (@convention(c) (Int32) -> CGError).self)
    static let moveWindowsToManagedSpace = load("SLSMoveWindowsToManagedSpace", (@convention(c) (Int32, CFArray, UInt64) -> CGError).self)

    static let transactionCreate = load("SLSTransactionCreate", (@convention(c) (Int32) -> Unmanaged<CFTypeRef>?).self)
    static let transactionCommit = load("SLSTransactionCommit", (@convention(c) (CFTypeRef, Int32) -> CGError).self)
    static let transactionMoveWindowWithGroup = load("SLSTransactionMoveWindowWithGroup", (@convention(c) (CFTypeRef, UInt32, CGPoint) -> CGError).self)
    static let transactionOrderWindow = load("SLSTransactionOrderWindow", (@convention(c) (CFTypeRef, UInt32, Int32, UInt32) -> CGError).self)
    static let transactionSetWindowLevel = load("SLSTransactionSetWindowLevel", (@convention(c) (CFTypeRef, UInt32, Int32) -> CGError).self)

    static let windowQueryWindows = load("SLSWindowQueryWindows", (@convention(c) (Int32, CFArray, UInt32) -> Unmanaged<CFTypeRef>?).self)
    static let windowQueryResultCopyWindows = load("SLSWindowQueryResultCopyWindows", (@convention(c) (CFTypeRef) -> Unmanaged<CFTypeRef>?).self)
    static let windowIteratorAdvance = load("SLSWindowIteratorAdvance", (@convention(c) (CFTypeRef) -> Bool).self)
    static let windowIteratorGetLevel = load("SLSWindowIteratorGetLevel", (@convention(c) (CFTypeRef) -> Int32).self)
    static let windowIteratorGetWindowID = load("SLSWindowIteratorGetWindowID", (@convention(c) (CFTypeRef) -> UInt32).self)
    static let windowIteratorGetParentID = load("SLSWindowIteratorGetParentID", (@convention(c) (CFTypeRef) -> UInt32).self)
    static let windowIteratorGetTags = load("SLSWindowIteratorGetTags", (@convention(c) (CFTypeRef) -> UInt64).self)
    static let windowIteratorGetAttributes = load("SLSWindowIteratorGetAttributes", (@convention(c) (CFTypeRef) -> UInt64).self)
    // macOS 26 and later only: windows there have different corner radii by kind
    static let windowIteratorGetCornerRadii = load("SLSWindowIteratorGetCornerRadii", (@convention(c) (CFTypeRef) -> Unmanaged<CFArray>?).self)

    // Everything the border needs to work; the corner radius lookup has a fallback
    static var isAvailable: Bool {
        let required: [Any?] = [
            mainConnectionID, newConnection, registerNotifyProc, requestNotificationsForWindows, getActiveSpace,
            copySpacesForWindows, getWindowBounds, windowIsOrderedIn, newRegionWithRect, newWindow, releaseWindow,
            setWindowTags, setWindowShape, setWindowResolution, setWindowOpacity, setWindowShadowProperties,
            windowContextCreate, flushWindowContentRegion, windowFreeze, windowThaw, disableUpdate, reenableUpdate,
            moveWindowsToManagedSpace,
            transactionCreate, transactionCommit, transactionMoveWindowWithGroup, transactionOrderWindow,
            transactionSetWindowLevel, windowQueryWindows, windowQueryResultCopyWindows, windowIteratorAdvance,
            windowIteratorGetLevel, windowIteratorGetWindowID, windowIteratorGetParentID, windowIteratorGetTags,
            windowIteratorGetAttributes,
        ]
        return required.allSatisfy { $0 != nil }
    }
}

// Window server event numbers, as observed by the projects above
private enum WindowEvent: UInt32, CaseIterable {
    case close = 804
    case move = 806
    case resize = 807
    case reorder = 808
    case level = 811
    case unhide = 815
    case hide = 816
    case title = 1322
    case create = 1325
    case destroy = 1326
    case spaceChange = 1401
    case frontAppChange = 1508
}

// A plain C function, as SkyLight requires; everything is handed to the one border on the main thread
private let windowEventHandler: SkyLight.NotifyProc = { rawEvent, data, length, _ in
    guard let event = WindowEvent(rawValue: rawEvent) else { return }
    var windowID: UInt32 = 0
    if let data = data {
        switch event {
        case .create, .destroy:
            // { space id: UInt64, window id: UInt32 }
            if length >= 12 { windowID = data.loadUnaligned(fromByteOffset: 8, as: UInt32.self) }
        case .spaceChange, .frontAppChange:
            break
        default:
            if length >= 4 { windowID = data.loadUnaligned(as: UInt32.self) }
        }
    }
    let id = windowID
    if Thread.isMainThread {
        WindowBorder.shared.handle(event, windowID: id)
    } else {
        DispatchQueue.main.async { WindowBorder.shared.handle(event, windowID: id) }
    }
}

final class WindowBorder {
    static let shared = WindowBorder()

    static var isAvailable: Bool { SkyLight.isAvailable }

    // In points, 0 turns the border off
    var width: CGFloat = 0 {
        didSet { if width != oldValue { needsRedraw = true; refocus() } }
    }

    var color: NSColor = .controlAccentColor {
        didSet { needsRedraw = true; update() }
    }

    // Room around the ring so antialiasing is not cut off at the window's edge
    private let padding: CGFloat = 2
    private let fallbackRadius: CGFloat = 9

    private var mainConnection: Int32 = 0
    private var connection: Int32 = 0  // Our own, so AppKit never sees events for the border window
    private var borderID: UInt32 = 0
    private var context: CGContext?
    private var frame = CGRect.null  // Of the border window, in global top-left coordinates
    private var space: UInt64 = 0
    private var isShown = false
    private var needsRedraw = true

    private var target: UInt32 = 0
    private var targetSpace: UInt64?  // Looked up on focus changes, not on every resize
    private var targetRadius: CGFloat = 9
    private var targetLevel: Int32 = 0

    private var isRegistered = false
    private var focusCheckPending = false

    private init() {}

    // MARK: Events

    private let debug = ProcessInfo.processInfo.environment["WORKIT_DEBUG"] != nil

    fileprivate func handle(_ event: WindowEvent, windowID: UInt32) {
        if debug { print("event \(event) window \(windowID) target \(target)") }
        guard width > 0, windowID == 0 || windowID != borderID else { return }

        if target != 0, windowID == target {
            switch event {
            case .move:
                move()
                return
            case .resize, .level, .unhide:
                scheduleUpdate()
                return
            case .hide, .close, .destroy:
                hide()
                target = 0
                scheduleFocusCheck()
                return
            default:
                break
            }
        }

        switch event {
        case .spaceChange:
            // Not every window has settled on its new space when this arrives
            scheduleFocusCheck(after: 0.02)
        case .move, .resize, .level, .unhide, .hide, .close:
            // Other windows changing shape or visibility does not move focus
            break
        default:
            // Front app, window order, titles and new windows can all mean focus moved
            scheduleFocusCheck()
        }
    }

    private func register() {
        guard !isRegistered, let mainConnectionID = SkyLight.mainConnectionID, let registerNotifyProc = SkyLight.registerNotifyProc,
              let newConnection = SkyLight.newConnection else { return }
        mainConnection = mainConnectionID()
        _ = newConnection(0, &connection)
        for event in WindowEvent.allCases {
            _ = registerNotifyProc(windowEventHandler, event.rawValue, nil)
        }
        isRegistered = true
    }

    // A live resize sends events faster than the border can be redrawn at full size. Handling
    // them all would leave it working through stale sizes; this jumps to the latest one.
    private var updatePending = false

    private func scheduleUpdate() {
        guard !updatePending else { return }
        updatePending = true
        DispatchQueue.main.async { [weak self] in
            self?.updatePending = false
            self?.update()
        }
    }

    // Focus events come in bursts, and the window list lags them slightly
    private func scheduleFocusCheck(after delay: TimeInterval = 0.05) {
        guard !focusCheckPending else { return }
        focusCheckPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.focusCheckPending = false
            self?.refocus()
        }
    }

    // MARK: Focus

    func refocus() {
        guard width > 0, SkyLight.isAvailable else {
            hide()
            return
        }
        register()

        let listed = normalWindowsOnScreen()
        let topLevel = topLevelWindows(among: listed.map { $0.id })
        let windows = listed.filter { topLevel.contains($0.id) }
        // Asking for notifications on every visible window, not just the focused one, is what
        // reveals focus moving between two windows of the same app
        watch(windows.map { $0.id })

        guard let focused = focusedWindow(among: windows) else {
            hide()
            target = 0
            return
        }
        if focused != target {
            if debug { print("focus \(target) -> \(focused)") }
            target = focused
            readTargetDetails()
            needsRedraw = true
        }
        targetSpace = spaceOf(target)
        update()
    }

    private struct ListedWindow {
        let id: UInt32
        let pid: pid_t
    }

    // Front to back, as the window server lists them
    private func normalWindowsOnScreen() -> [ListedWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        let ownPID = getpid()
        return info.compactMap { window in
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  let id = window[kCGWindowNumber as String] as? UInt32,
                  let pid = window[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let boundsInfo = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo),
                  bounds.width >= 40, bounds.height >= 40 else { return nil }
            return ListedWindow(id: id, pid: pid)
        }
    }

    // Real windows, as opposed to the popups, dropdowns and tooltips apps attach to them (such as
    // a browser's address bar suggestions): no parent, not attached, not left out of window
    // cycling, and a document window or a modal panel. The same test yabai and JankyBorders use.
    private func topLevelWindows(among ids: [UInt32]) -> Set<UInt32> {
        guard !ids.isEmpty,
              let query = SkyLight.windowQueryWindows?(mainConnection, ids.map { NSNumber(value: $0) } as CFArray, 0)?.takeRetainedValue(),
              let iterator = SkyLight.windowQueryResultCopyWindows?(query)?.takeRetainedValue() else { return [] }

        let document: UInt64 = 1 << 0, floating: UInt64 = 1 << 1, attached: UInt64 = 1 << 7
        let ignoresCycle: UInt64 = 1 << 18, modal: UInt64 = 1 << 31, visibleTag: UInt64 = 1 << 58
        var result = Set<UInt32>()
        while SkyLight.windowIteratorAdvance?(iterator) == true {
            let tags = SkyLight.windowIteratorGetTags?(iterator) ?? 0
            let attributes = SkyLight.windowIteratorGetAttributes?(iterator) ?? 0
            guard SkyLight.windowIteratorGetParentID?(iterator) == 0,
                  attributes & 0x2 != 0 || tags & visibleTag != 0,
                  tags & (attached | ignoresCycle) == 0,
                  tags & document != 0 || tags & (floating | modal) == floating | modal,
                  let id = SkyLight.windowIteratorGetWindowID?(iterator) else { continue }
            result.insert(id)
        }
        return result
    }

    // The front app's frontmost window on the active space
    private func focusedWindow(among windows: [ListedWindow]) -> UInt32? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let activeSpace = SkyLight.getActiveSpace?(mainConnection) else { return nil }
        return windows.first { $0.pid == pid && spaceOf($0.id) == activeSpace }?.id
    }

    private var watched: [UInt32] = []

    private func watch(_ windows: [UInt32]) {
        guard windows != watched else { return }
        watched = windows
        windows.withUnsafeBufferPointer { buffer in
            _ = SkyLight.requestNotificationsForWindows?(mainConnection, buffer.baseAddress, Int32(buffer.count))
        }
    }

    private func spaceOf(_ window: UInt32) -> UInt64? {
        let list = [NSNumber(value: window)] as CFArray
        // 0x7: every space the window is on
        guard let spaces = SkyLight.copySpacesForWindows?(mainConnection, 0x7, list)?.takeRetainedValue() as? [NSNumber] else {
            return nil
        }
        return spaces.first?.uint64Value
    }

    // Level, and the corner radius on systems that report it
    private func readTargetDetails() {
        targetRadius = fallbackRadius
        targetLevel = 0
        let list = [NSNumber(value: target)] as CFArray
        guard let query = SkyLight.windowQueryWindows?(mainConnection, list, 0)?.takeRetainedValue(),
              let iterator = SkyLight.windowQueryResultCopyWindows?(query)?.takeRetainedValue(),
              SkyLight.windowIteratorAdvance?(iterator) == true else { return }
        targetLevel = SkyLight.windowIteratorGetLevel?(iterator) ?? 0
        if let radii = SkyLight.windowIteratorGetCornerRadii?(iterator)?.takeRetainedValue() as? [NSNumber],
           let radius = radii.first?.doubleValue, radius > 0 {
            targetRadius = CGFloat(radius)
        }
    }

    // MARK: Border window

    private func targetBounds() -> CGRect? {
        var bounds = CGRect.zero
        guard target != 0, SkyLight.getWindowBounds?(mainConnection, target, &bounds) == .success else { return nil }
        return bounds
    }

    private func borderFrame(around bounds: CGRect) -> CGRect {
        bounds.insetBy(dx: -(width + padding), dy: -(width + padding))
    }

    private func update() {
        let started = debug ? CACurrentMediaTime() : 0
        defer { if debug { print(String(format: "update %.2f ms", (CACurrentMediaTime() - started) * 1000)) } }
        guard width > 0, target != 0, let bounds = targetBounds() else {
            hide()
            return
        }
        var orderedIn = false
        _ = SkyLight.windowIsOrderedIn?(mainConnection, target, &orderedIn)
        guard orderedIn, bounds.width > 2 * targetRadius, bounds.height > 2 * targetRadius else {
            hide()
            return
        }

        let newFrame = borderFrame(around: bounds)
        if borderID == 0 {
            createWindow(size: newFrame.size)
            guard borderID != 0 else { return }
            frame = CGRect(origin: CGPoint(x: -9999, y: -9999), size: newFrame.size)
        }

        // Shape, drawing and position have to reach the screen together. Shown one at a time, the
        // border flashes at its new size in the wrong place, plain to see when a window is resized
        // from its left edge.
        _ = SkyLight.disableUpdate?(connection)
        if newFrame.size != frame.size, let region = region(of: newFrame.size) {
            // Frozen, so the reshaped window is not shown until it has been redrawn
            _ = SkyLight.windowFreeze?(connection, borderID, nil)
            // The offset is where the reshaped window goes; 0, 0 would be the screen's corner
            _ = SkyLight.setWindowShape?(connection, borderID, Float(newFrame.minX), Float(newFrame.minY), region)
            needsRedraw = true
        }
        frame = newFrame
        if needsRedraw { draw() }

        if let targetSpace = targetSpace, targetSpace != space {
            _ = SkyLight.moveWindowsToManagedSpace?(connection, [NSNumber(value: borderID)] as CFArray, targetSpace)
            space = targetSpace
        }

        commit { transaction in
            _ = SkyLight.transactionMoveWindowWithGroup?(transaction, borderID, frame.origin)
            _ = SkyLight.transactionSetWindowLevel?(transaction, borderID, targetLevel)
            // -1: directly below the target, so only the part outside the window shows
            _ = SkyLight.transactionOrderWindow?(transaction, borderID, -1, target)
        }
        _ = SkyLight.reenableUpdate?(connection)
        isShown = true
    }

    // The common case while dragging: same size, new place, no redraw
    private func move() {
        guard isShown, let bounds = targetBounds() else { return }
        let newFrame = borderFrame(around: bounds)
        guard newFrame.size == frame.size else {
            update()
            return
        }
        frame = newFrame
        commit { transaction in
            _ = SkyLight.transactionMoveWindowWithGroup?(transaction, borderID, frame.origin)
        }
    }

    private func hide() {
        guard isShown, borderID != 0 else { return }
        commit { transaction in
            _ = SkyLight.transactionOrderWindow?(transaction, borderID, 0, target)
        }
        isShown = false
    }

    private func commit(_ build: (CFTypeRef) -> Void) {
        guard let transaction = SkyLight.transactionCreate?(connection)?.takeRetainedValue() else { return }
        build(transaction)
        _ = SkyLight.transactionCommit?(transaction, 0)
    }

    private func region(of size: CGSize) -> CFTypeRef? {
        var rect = CGRect(origin: .zero, size: size)
        var region: Unmanaged<CFTypeRef>?
        guard SkyLight.newRegionWithRect?(&rect, &region) == .success else { return nil }
        return region?.takeRetainedValue()
    }

    private func createWindow(size: CGSize) {
        guard let region = region(of: size) else { return }
        var id: UInt32 = 0
        // 2: kCGBackingStoreBuffered. Created off screen; update() moves it into place.
        guard SkyLight.newWindow?(connection, 2, -9999, -9999, region, &id) == .success, id != 0 else { return }
        borderID = id

        // One border window only, so it can afford to be sharp on Retina displays
        let scale = NSScreen.screens.map { $0.backingScaleFactor }.max() ?? 2
        _ = SkyLight.setWindowResolution?(connection, id, Double(scale))
        // The tags JankyBorders and yabai give their border windows: floating, and ignored for
        // mouse events, so clicks reach whatever is beneath
        var tags: UInt64 = (1 << 1) | (1 << 9)
        _ = SkyLight.setWindowTags?(connection, id, &tags, 64)
        _ = SkyLight.setWindowOpacity?(connection, id, false)
        _ = SkyLight.setWindowShadowProperties?(id, ["com.apple.WindowShadowDensity": 0] as CFDictionary)

        context = SkyLight.windowContextCreate?(connection, id, nil)?.takeRetainedValue()
        context?.interpolationQuality = .none
        space = 0
        needsRedraw = true
    }

    private func draw() {
        guard let context = context else { return }
        needsRedraw = false
        let bounds = CGRect(origin: .zero, size: frame.size)
        let window = bounds.insetBy(dx: width + padding, dy: width + padding)
        // A ring from 1pt inside the window's edge, hidden beneath it, to `width` outside it,
        // following the window's own corner rounding
        let offset = (width - 1) / 2
        let ring = window.insetBy(dx: -offset, dy: -offset)
        let radius = targetRadius + offset

        context.saveGState()
        context.clear(bounds)
        context.setStrokeColor(resolvedColor().cgColor)
        context.setLineWidth(width + 1)
        context.addPath(CGPath(roundedRect: ring, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.strokePath()
        context.restoreGState()
        context.flush()
        _ = SkyLight.flushWindowContentRegion?(connection, borderID, nil)
        _ = SkyLight.windowThaw?(connection, borderID)
    }

    // Dynamic colors such as the accent color need resolving before they reach Core Graphics
    private func resolvedColor() -> NSColor {
        var resolved = color
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.sRGB) ?? color
        }
        return resolved
    }
}
