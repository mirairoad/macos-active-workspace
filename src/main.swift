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

@_silgen_name("CGSCopyActiveMenuBarDisplayIdentifier")
public func CGSCopyActiveMenuBarDisplayIdentifier(_ connection: Int32) -> CFString

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

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var updateTimer: Timer?
    private var lastActiveSpace: Int32 = 0  // Add this to track the last space
    private var currentNumber = 1
    // The pre-Workit label, kept so settings carry over from earlier installs
    private let defaults = UserDefaults(suiteName: "com.workspace.monitor") ?? .standard
    private let colorMenu = NSMenu()
    private let sizeMenu = NSMenu()
    private let fontMenu = NSMenu()
    private let backgroundAlpha: CGFloat = 0.8
    private let cornerRadius: CGFloat = 3
    private let horizontalPadding: CGFloat = 6  // 3 points on each side

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
        updateButtonAppearance(number: 1)
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
        updateButtonAppearance(number: currentNumber)
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
        
        // Separate observer for accent color changes
        distributedCenter.addObserver(
            self,
            selector: #selector(updateAccentColor),
            name: NSNotification.Name("AppleColorPreferencesChangedNotification"),
            object: nil
        )
    }
    
    private func updateButtonAppearance(number: Int) {
        guard let button = statusItem.button else { return }
        currentNumber = number
        button.image = indicatorImage(number: number)
    }

    // Draw at a fixed point size so the indicator looks the same on every display,
    // instead of stretching to the menu bar height
    private func indicatorImage(number: Int) -> NSImage {
        let size = indicatorSize
        let fill = indicatorColor.fill
        let height = min(size.height, NSStatusBar.system.thickness - 2)
        let font = indicatorFont.font(ofSize: round(height * textSize.scale), weight: isBold ? .bold : .regular)
        // Template images only use alpha, so the color is irrelevant without a fill
        let textColor = fill.map { contrastingTextColor(for: $0) } ?? .black
        let text = NSAttributedString(string: "\(number)", attributes: [.font: font, .foregroundColor: textColor])
        let textWidth = ceil(text.size().width)
        let width = max(height, textWidth + horizontalPadding)
        let radius = cornerRadius
        let alpha = backgroundAlpha

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            if let fill = fill {
                fill.withAlphaComponent(alpha).setFill()
                NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            }
            // Center the digits (cap height), not the whole line box
            let baseline = (rect.height - font.capHeight) / 2
            text.draw(at: NSPoint(x: (rect.width - textWidth) / 2, y: baseline + font.descender))
            return true
        }
        // Lets macOS tint the bare number for light and dark menu bars
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
        
        // Only print if the space has changed
        if activeSpace != lastActiveSpace {
            let displays = CGSCopyManagedDisplaySpaces(conn) as! [NSDictionary]
            let activeDisplay = CGSCopyActiveMenuBarDisplayIdentifier(conn) as String
            let allSpaces: NSMutableArray = []
            var activeSpaceID = -1
            
            // Find active space ID and collect non-fullscreen spaces
            for display in displays {
                guard
                    let current = display["Current Space"] as? [String: Any],
                    let spaces = display["Spaces"] as? [[String: Any]],
                    let dispID = display["Display Identifier"] as? String
                else {
                    continue
                }
                
                // Get active space ID from main/active display
                if dispID == "Main" || dispID == activeDisplay {
                    activeSpaceID = current["ManagedSpaceID"] as! Int
                }
                
                // Collect only non-fullscreen spaces
                for space in spaces {
                    let isFullscreen = space["TileLayoutManager"] as? [String: Any] != nil
                    if !isFullscreen {
                        allSpaces.add(space)
                    }
                }
            }
            
            // Find and update space number
            for (index, space) in allSpaces.enumerated() {
                let spaceID = (space as! NSDictionary)["ManagedSpaceID"] as! Int
                if spaceID == activeSpaceID {
                    let spaceNumber = index + 1
                    print("Switched to Space Number: \(spaceNumber)")
                    DispatchQueue.main.async { [weak self] in
                        self?.updateButtonAppearance(number: spaceNumber)
                    }
                    break
                }
            }
            
            lastActiveSpace = activeSpace
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
            self.updateButtonAppearance(number: self.currentNumber)
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