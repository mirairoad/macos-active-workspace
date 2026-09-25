import Cocoa

// Add workspace management imports
import CoreGraphics
import ApplicationServices

// CGSInternal declarations
private let kCGSAllSpacesMask: Int32 = 0xFF

private struct CGSSpace {
    static let kCGSSpaceAll: Int32 = 0
    static let kCGSSpaceUser: Int32 = 1
    static let kCGSSpaceFullscreen: Int32 = 2
}

// Private API declarations with proper types
private let _CGSDefaultConnection: () -> Int32 = {
    unsafeBitCast(dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_CGSDefaultConnection"),
                  to: (@convention(c) () -> Int32).self)
}()

private let CGSGetActiveSpace: (Int32) -> Int32 = {
    unsafeBitCast(dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGSGetActiveSpace"),
                  to: (@convention(c) (Int32) -> Int32).self)
}()

private let CGSCopySpaces: (Int32, Int32) -> CFArray? = {
    unsafeBitCast(dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGSCopySpaces"),
                  to: (@convention(c) (Int32, Int32) -> CFArray?).self)
}()

private let CGSSpaceCopyName: (Int32, Int32) -> CFString? = {
    unsafeBitCast(dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGSSpaceCopyName"),
                  to: (@convention(c) (Int32, Int32) -> CFString?).self)
}()

@_silgen_name("CGSCopyManagedDisplaySpaces") 
public func CGSCopyManagedDisplaySpaces(_ connection: Int32) -> CFArray

// Indicator appearance options, selectable from the status item menu
private enum IndicatorColor: String, CaseIterable {
    case accent, transparent, gray, red, orange, yellow, green, blue, purple, pink

    var title: String { rawValue.capitalized }

    // nil means no background: only the number is drawn, tinted by the menu bar
    var fill: NSColor? {
        switch self {
        case .accent:
            if #available(macOS 10.14, *) { return .controlAccentColor }
            return .systemBlue
        case .transparent: return nil
        case .gray: return .systemGray
        case .red: return .systemRed
        case .orange: return .systemOrange
        case .yellow: return .systemYellow
        case .green: return .systemGreen
        case .blue: return .systemBlue
        case .purple: return .systemPurple
        case .pink: return .systemPink
        }
    }
}

private enum IndicatorSize: String, CaseIterable {
    case small, medium, large

    var title: String { rawValue.capitalized }

    var height: CGFloat {
        switch self {
        case .small: return 14
        case .medium: return 17
        case .large: return 20
        }
    }
}

private enum IndicatorFont: String, CaseIterable {
    case system, rounded, monospaced, serif

    var title: String { rawValue.capitalized }

    func font(ofSize size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let system = NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
        guard #available(macOS 10.15, *) else { return system }
        let design: NSFontDescriptor.SystemDesign
        switch self {
        case .system: return system
        case .rounded: design = .rounded
        case .monospaced: design = .monospaced
        case .serif: design = .serif
        }
        guard let descriptor = system.fontDescriptor.withDesign(design) else { return system }
        return NSFont(descriptor: descriptor, size: size) ?? system
    }
}

// Relative to the indicator height, so the number fits whichever size is picked
private enum TextSize: String, CaseIterable {
    case small, medium, large

    var title: String { rawValue.capitalized }

    var scale: CGFloat {
        switch self {
        case .small: return 0.6
        case .medium: return 0.7
        case .large: return 0.82
        }
    }
}

// What one display is showing: its current desktop number, or "F" for a full-screen app
private struct DisplayState {
    let label: String
    let isFocused: Bool
}

// One label in its box: as wide as it is tall, or wider when the label needs it
private struct Label {
    let text: NSAttributedString
    let font: NSFont
    let textWidth: CGFloat
    let width: CGFloat

    init(_ string: String, font: NSFont, color: NSColor, height: CGFloat, padding: CGFloat) {
        self.font = font
        text = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color])
        textWidth = ceil(text.size().width)
        width = max(height, textWidth + padding)
    }

    func draw(in box: NSRect) {
        // Center the digits (cap height), not the whole line box
        let baseline = box.minY + (box.height - font.capHeight) / 2
        text.draw(at: NSPoint(x: box.midX - textWidth / 2, y: baseline + font.descender))
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var updateTimer: Timer?
    private var lastActiveSpace: Int32 = 0  // Add this to track the last space
    private var currentDisplays = [DisplayState(label: "1", isFocused: true)]
    // The pre-Workit label, kept so settings carry over from earlier installs
    private let defaults = UserDefaults(suiteName: "com.workspace.monitor") ?? .standard
    private let colorMenu = NSMenu()
    private let sizeMenu = NSMenu()
    private let fontMenu = NSMenu()
    private let backgroundAlpha: CGFloat = 0.8
    private let cornerRadius: CGFloat = 3
    private let horizontalPadding: CGFloat = 6  // 3 points on each side
    private let gap: CGFloat = 3  // Between the boxes of different displays
    private let borderWidth: CGFloat = 1.25

    private var indicatorColor: IndicatorColor {
        get { setting("color", default: .accent) }
        set { defaults.set(newValue.rawValue, forKey: "color") }
    }

    private var indicatorSize: IndicatorSize {
        get { setting("size", default: .large) }
        set { defaults.set(newValue.rawValue, forKey: "size") }
    }

    private var indicatorFont: IndicatorFont {
        get { setting("font", default: .system) }
        set { defaults.set(newValue.rawValue, forKey: "font") }
    }

    private var textSize: TextSize {
        get { setting("textSize", default: .medium) }
        set { defaults.set(newValue.rawValue, forKey: "textSize") }
    }

    private var isBold: Bool {
        get { defaults.bool(forKey: "bold") }
        set { defaults.set(newValue, forKey: "bold") }
    }

    private func setting<T: RawRepresentable>(_ key: String, default fallback: T) -> T where T.RawValue == String {
        return defaults.string(forKey: key).flatMap(T.init(rawValue:)) ?? fallback
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Opening the app while it already runs (at login, or from Spotlight) must not add a second number
        if let bundleID = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains(where: { $0 != .current }) {
            NSApp.terminate(nil)
            return
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // Configure the status item
        statusItem.isVisible = true
        statusItem.button?.imagePosition = .imageOnly

        setupMenu()
        redraw()
        updateWorkspaceInfo()
        setupNotifications()

        // More frequent updates for testing
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.updateWorkspaceInfo()
        }
    }

    private func setupMenu() {
        let menu = NSMenu()

        for color in IndicatorColor.allCases {
            // Separate accent/transparent from the plain colors
            if color == .gray { colorMenu.addItem(.separator()) }
            colorMenu.addItem(optionItem(title: color.title, value: color.rawValue, action: #selector(selectColor(_:))))
        }
        for size in IndicatorSize.allCases {
            sizeMenu.addItem(optionItem(title: size.title, value: size.rawValue, action: #selector(selectSize(_:))))
        }

        fontMenu.addItem(sectionHeader("Typeface"))
        for font in IndicatorFont.allCases {
            let item = optionItem(title: font.title, value: font.rawValue, action: #selector(selectFont(_:)))
            // Preview each typeface in itself
            item.attributedTitle = NSAttributedString(string: font.title, attributes: [
                .font: font.font(ofSize: NSFont.systemFontSize, weight: .regular)
            ])
            fontMenu.addItem(item)
        }
        fontMenu.addItem(.separator())
        fontMenu.addItem(sectionHeader("Text Size"))
        for size in TextSize.allCases {
            fontMenu.addItem(optionItem(title: size.title, value: size.rawValue, action: #selector(selectTextSize(_:))))
        }
        fontMenu.addItem(.separator())
        fontMenu.addItem(optionItem(title: "Bold", value: "bold", action: #selector(toggleBold(_:))))

        let colorItem = NSMenuItem(title: "Color", action: nil, keyEquivalent: "")
        colorItem.submenu = colorMenu
        menu.addItem(colorItem)

        let sizeItem = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
        sizeItem.submenu = sizeMenu
        menu.addItem(sizeItem)

        let fontItem = NSMenuItem(title: "Font", action: nil, keyEquivalent: "")
        fontItem.submenu = fontMenu
        menu.addItem(fontItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Workit", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
        refreshMenu()
    }

    private func optionItem(title: String, value: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = value
        return item
    }

    private func sectionHeader(_ title: String) -> NSMenuItem {
        if #available(macOS 14.0, *) { return .sectionHeader(title: title) }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    // Sync checkmarks and color swatches with the saved settings
    private func refreshMenu() {
        for item in colorMenu.items {
            guard let value = item.representedObject as? String,
                  let color = IndicatorColor(rawValue: value) else { continue }
            item.state = color == indicatorColor ? .on : .off
            item.image = swatch(for: color)
        }
        for item in sizeMenu.items {
            item.state = (item.representedObject as? String) == indicatorSize.rawValue ? .on : .off
        }
        for item in fontMenu.items {
            let value = item.representedObject as? String
            if item.action == #selector(selectFont(_:)) {
                item.state = value == indicatorFont.rawValue ? .on : .off
            } else if item.action == #selector(selectTextSize(_:)) {
                item.state = value == textSize.rawValue ? .on : .off
            } else if item.action == #selector(toggleBold(_:)) {
                item.state = isBold ? .on : .off
            }
        }
    }

    private func swatch(for color: IndicatorColor) -> NSImage {
        return NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
            if let fill = color.fill {
                fill.setFill()
                circle.fill()
            } else {
                NSColor.secondaryLabelColor.setStroke()
                circle.stroke()
            }
            return true
        }
    }

    @objc private func selectColor(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String,
              let color = IndicatorColor(rawValue: value) else { return }
        indicatorColor = color
        settingsChanged()
    }

    @objc private func selectSize(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String,
              let size = IndicatorSize(rawValue: value) else { return }
        indicatorSize = size
        settingsChanged()
    }

    @objc private func selectFont(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String,
              let font = IndicatorFont(rawValue: value) else { return }
        indicatorFont = font
        settingsChanged()
    }

    @objc private func selectTextSize(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String,
              let size = TextSize(rawValue: value) else { return }
        textSize = size
        settingsChanged()
    }

    @objc private func toggleBold(_ sender: NSMenuItem) {
        isBold.toggle()
        settingsChanged()
    }

    private func settingsChanged() {
        refreshMenu()
        redraw()
    }
    
    private func setupNotifications() {
        let notificationCenter = NSWorkspace.shared.notificationCenter
        let distributedCenter = DistributedNotificationCenter.default()
        
        // Workspace notifications
        let workspaceNotifications: [(NotificationCenter, NSNotification.Name)] = [
            (notificationCenter, NSWorkspace.activeSpaceDidChangeNotification),
            (notificationCenter, NSWorkspace.didActivateApplicationNotification),
            (notificationCenter, NSWorkspace.didLaunchApplicationNotification),
            (notificationCenter, NSWorkspace.didTerminateApplicationNotification),
            (distributedCenter, NSNotification.Name("com.apple.spaces.switchedSpaces")),
            (distributedCenter, NSNotification.Name("com.apple.screenIsChanged"))
        ]
        
        // Add observers for workspace changes
        for (center, notification) in workspaceNotifications {
            center.addObserver(
                self,
                selector: #selector(updateWorkspaceInfo),
                name: notification,
                object: nil
            )
        }
        
        // Plugging a display in or out renumbers desktops without changing the active one
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        // Separate observer for accent color changes
        distributedCenter.addObserver(
            self,
            selector: #selector(updateAccentColor),
            name: NSNotification.Name("AppleColorPreferencesChangedNotification"),
            object: nil
        )
    }
    
    private func updateButtonAppearance(displays: [DisplayState]) {
        currentDisplays = displays
        redraw()
    }

    private func redraw() {
        statusItem.button?.image = indicatorImage(displays: currentDisplays)
    }

    // Draw at a fixed point size so the indicator looks the same on every display,
    // instead of stretching to the menu bar height.
    //
    // macOS draws a status item once and mirrors that image onto every display's menu bar, so
    // each display cannot show its own desktop. Instead every display gets a box, main display
    // first: the focused one filled, the others outlined. That reads the same on every menu bar.
    private func indicatorImage(displays: [DisplayState]) -> NSImage {
        let fill = indicatorColor.fill
        let height = min(indicatorSize.height, NSStatusBar.system.thickness - 2)
        let font = indicatorFont.font(ofSize: round(height * textSize.scale), weight: isBold ? .bold : .regular)
        // Template images only use alpha, so black stands in for whatever the menu bar needs
        let ink = fill ?? .black
        let filledText = fill.map { contrastingTextColor(for: $0) } ?? .black
        // With a single display there is nothing to tell apart, so it keeps the plain look
        let showFocus = displays.count > 1
        let boxes = displays.map { display -> (filled: Bool, label: Label) in
            let filled = display.isFocused || !showFocus
            let label = Label(display.label, font: font, color: filled ? filledText : ink,
                              height: height, padding: horizontalPadding)
            return (filled, label)
        }
        let width = boxes.map { $0.label.width }.reduce(0, +) + gap * CGFloat(max(boxes.count - 1, 0))
        let radius = cornerRadius
        let alpha = backgroundAlpha
        let lineWidth = borderWidth
        let spacing = gap

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            var x: CGFloat = 0
            for (filled, label) in boxes {
                let box = NSRect(x: x, y: 0, width: label.width, height: height)
                let shape = NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius)
                if !filled {
                    let border = NSBezierPath(roundedRect: box.insetBy(dx: lineWidth / 2, dy: lineWidth / 2),
                                              xRadius: radius, yRadius: radius)
                    border.lineWidth = lineWidth
                    ink.setStroke()
                    border.stroke()
                    label.draw(in: box)
                } else if let fill = fill {
                    fill.withAlphaComponent(alpha).setFill()
                    shape.fill()
                    label.draw(in: box)
                } else if showFocus {
                    // Transparent: a solid box with the number cut out of it
                    NSColor.black.setFill()
                    shape.fill()
                    NSGraphicsContext.current?.compositingOperation = .destinationOut
                    label.draw(in: box)
                    NSGraphicsContext.current?.compositingOperation = .sourceOver
                } else {
                    label.draw(in: box)
                }
                x += label.width + spacing
            }
            return true
        }
        // Lets macOS tint template drawing for light and dark menu bars
        image.isTemplate = fill == nil
        return image
    }

    // White text, unless the background is too light for it (e.g. yellow)
    private func contrastingTextColor(for fill: NSColor) -> NSColor {
        guard let rgb = fill.usingColorSpace(.sRGB) else { return .white }
        let luminance = 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
        return luminance > 0.7 ? .black : .white
    }
    
    @objc internal func updateWorkspaceInfo() {
        let conn = _CGSDefaultConnection()
        let activeSpace = CGSGetActiveSpace(conn)
        guard activeSpace != lastActiveSpace else { return }
        lastActiveSpace = activeSpace

        // Desktops are numbered per display, as Mission Control does, with displays in the order
        // macOS lists them (main display first). Full-screen apps get spaces of their own, which
        // are not desktops: they are skipped in the numbering and shown as "F".
        let displays = CGSCopyManagedDisplaySpaces(conn) as! [NSDictionary]
        let states = displays.compactMap { display -> DisplayState? in
            guard let current = (display["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? Int,
                  let spaces = display["Spaces"] as? [[String: Any]] else { return nil }
            let desktops = spaces.filter { $0["TileLayoutManager"] == nil }
            let index = desktops.firstIndex { ($0["ManagedSpaceID"] as? Int) == current }
            return DisplayState(label: index.map { "\($0 + 1)" } ?? "F", isFocused: current == Int(activeSpace))
        }
        guard !states.isEmpty else { return }

        print("Desktops: " + states.map { $0.isFocused ? "[\($0.label)]" : $0.label }.joined(separator: " "))
        DispatchQueue.main.async { [weak self] in
            self?.updateButtonAppearance(displays: states)
        }
    }

    // Spaces can settle a moment after the notification, so look again shortly after
    @objc private func screensChanged() {
        for delay in [0.0, 1.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.lastActiveSpace = 0
                self?.updateWorkspaceInfo()
            }
        }
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    @objc private func updateAccentColor() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // Accent swatch and indicator both depend on the system accent color
            self.refreshMenu()
            self.redraw()
        }
    }
}

func main() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}

main()