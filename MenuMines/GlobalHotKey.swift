import AppKit
import Carbon.HIToolbox

/// A key combination the player chose to open and close the game from any app.
struct GlobalShortcut: Codable, Equatable {
    /// The hardware key code, which is what the system matches.
    let keyCode: UInt16
    /// `NSEvent.ModifierFlags` raw value, limited to Command, Option, Control and Shift.
    let modifiers: UInt
    /// How the key is written, captured from the keyboard layout when it was recorded.
    let key: String

    static let allowedModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiers).intersection(Self.allowedModifiers)
    }

    init(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifierFlags.intersection(Self.allowedModifiers).rawValue
        self.key = key
    }

    /// The shortcut a key press asks for, or nil if it can't be one. A shortcut needs
    /// Command, Option or Control, so that it can't swallow ordinary typing in other apps,
    /// except for the function keys, which nothing types.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(Self.allowedModifiers)
        let isFunctionKey = Self.functionKeyNames[Int(event.keyCode)] != nil
        guard isFunctionKey || !flags.isDisjoint(with: [.command, .option, .control]) else { return nil }
        guard let key = Self.keyName(for: event) else { return nil }
        self.init(keyCode: event.keyCode, modifierFlags: flags, key: key)
    }

    /// Whether this is a shortcut the system or nearly every app already uses, such as ⌘Q,
    /// ⌘W, ⌘C or the game's own ⌘R. Taken globally, it would stop working in every app.
    var isStandardShortcut: Bool {
        let flags = modifierFlags
        let code = Int(keyCode)
        switch flags {
        case .command:
            return Self.commandEquivalents.contains(code)
        case [.command, .shift]:
            return Self.shiftCommandEquivalents.contains(code)
        case [.command, .option]:
            return [kVK_ANSI_H, kVK_ANSI_M, kVK_ANSI_W, kVK_Escape, kVK_Space].contains(code)
        case [.command, .control]:
            return [kVK_ANSI_Q, kVK_ANSI_F, kVK_Space].contains(code)
        case .control:
            // Switching input sources.
            return code == kVK_Space
        default:
            return false
        }
    }

    /// Command and a key: editing, windows, files, the app menu, the game's reset, Spotlight
    /// and switching apps and windows.
    private static let commandEquivalents: Set<Int> = [
        kVK_ANSI_A, kVK_ANSI_C, kVK_ANSI_F, kVK_ANSI_G, kVK_ANSI_H, kVK_ANSI_M, kVK_ANSI_N,
        kVK_ANSI_O, kVK_ANSI_P, kVK_ANSI_Q, kVK_ANSI_R, kVK_ANSI_S, kVK_ANSI_T, kVK_ANSI_V,
        kVK_ANSI_W, kVK_ANSI_X, kVK_ANSI_Z, kVK_ANSI_Comma, kVK_ANSI_Grave, kVK_Tab, kVK_Space
    ]

    /// Shift-Command and a key: redo, find previous, save as, log out, help and the
    /// screenshot shortcuts.
    private static let shiftCommandEquivalents: Set<Int> = [
        kVK_ANSI_Z, kVK_ANSI_G, kVK_ANSI_S, kVK_ANSI_Q, kVK_ANSI_Slash,
        kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_Tab
    ]

    /// Written the way menus write shortcuts, such as ⌃⌥M.
    var displayString: String {
        let flags = modifierFlags
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        return text + key
    }

    /// Written out in words, since VoiceOver doesn't always read the modifier symbols.
    var spokenDescription: String {
        let flags = modifierFlags
        var words: [String] = []
        if flags.contains(.control) { words.append(String(localized: "shortcut_modifier_control")) }
        if flags.contains(.option) { words.append(String(localized: "shortcut_modifier_option")) }
        if flags.contains(.shift) { words.append(String(localized: "shortcut_modifier_shift")) }
        if flags.contains(.command) { words.append(String(localized: "shortcut_modifier_command")) }
        words.append(Self.spokenKeyNames[Int(keyCode)] ?? key)
        return words.joined(separator: " ")
    }

    /// Carbon's modifier mask for `RegisterEventHotKey`.
    var carbonModifiers: UInt32 {
        let flags = modifierFlags
        var mask: Int = 0
        if flags.contains(.command) { mask |= cmdKey }
        if flags.contains(.option) { mask |= optionKey }
        if flags.contains(.control) { mask |= controlKey }
        if flags.contains(.shift) { mask |= shiftKey }
        return UInt32(mask)
    }

    // MARK: - Key names

    private static let functionKeyNames: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
        kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20"
    ]

    private static let symbolKeyNames: [Int: String] = [
        kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟"
    ]

    private static var spokenKeyNames: [Int: String] {
        [
            kVK_Space: String(localized: "shortcut_key_space"),
            kVK_Return: String(localized: "shortcut_key_return"),
            kVK_Tab: String(localized: "shortcut_key_tab"),
            kVK_Delete: String(localized: "shortcut_key_delete"),
            kVK_ForwardDelete: String(localized: "shortcut_key_forward_delete"),
            kVK_LeftArrow: String(localized: "shortcut_key_left_arrow"),
            kVK_RightArrow: String(localized: "shortcut_key_right_arrow"),
            kVK_UpArrow: String(localized: "shortcut_key_up_arrow"),
            kVK_DownArrow: String(localized: "shortcut_key_down_arrow")
        ]
    }

    private static func keyName(for event: NSEvent) -> String? {
        let code = Int(event.keyCode)
        if let name = functionKeyNames[code] ?? symbolKeyNames[code] {
            return name
        }
        if code == kVK_Space {
            return String(localized: "shortcut_key_space")
        }
        // The key as the layout writes it without Shift or Option, so ⌥⇧2 shows as 2.
        guard let characters = event.characters(byApplyingModifiers: []),
              let scalar = characters.unicodeScalars.first,
              !CharacterSet.controlCharacters.contains(scalar) else { return nil }
        return characters.uppercased()
    }

    // MARK: - Storage

    static func load(from defaults: UserDefaults = .standard) -> GlobalShortcut? {
        guard let data = defaults.data(forKey: Constants.SettingsKeys.globalShortcut) else { return nil }
        return try? JSONDecoder().decode(GlobalShortcut.self, from: data)
    }

    static func save(_ shortcut: GlobalShortcut?, to defaults: UserDefaults = .standard) {
        guard let shortcut, let data = try? JSONEncoder().encode(shortcut) else {
            defaults.removeObject(forKey: Constants.SettingsKeys.globalShortcut)
            return
        }
        defaults.set(data, forKey: Constants.SettingsKeys.globalShortcut)
    }
}

/// Registers the player's shortcut with the system, so that it reaches the app whichever app
/// is in front.
///
/// Carbon's `RegisterEventHotKey` is used because it needs no Accessibility permission and
/// works in the sandbox, where watching every key press would not.
@MainActor
enum GlobalHotKey {
    /// What the shortcut does. Set by the app delegate, which owns the panel.
    static var onPress: (() -> Void)?

    private static var hotKeyRef: EventHotKeyRef?
    private static var handlerRef: EventHandlerRef?
    private static let hotKeyID = EventHotKeyID(signature: 0x4D4D_686B, id: 1) // "MMhk"

    /// The saved shortcut, if the player set one.
    static var current: GlobalShortcut? { GlobalShortcut.load() }

    /// Whether a shortcut is registered right now.
    static var isRegistered: Bool { hotKeyRef != nil }

    /// Whether the saved shortcut couldn't be registered, because another app has it. It
    /// stays saved, and Settings says so rather than showing it as working.
    private(set) static var isSavedShortcutUnavailable = false

    /// Listens for the saved shortcut. Called once the app is up.
    static func start() {
        installHandler()
        registerSaved()
    }

    /// Saves a new shortcut, or clears it with nil, and listens for it.
    /// - Returns: False, leaving the old shortcut in place, if the system won't give it to us.
    @discardableResult
    static func set(_ shortcut: GlobalShortcut?) -> Bool {
        installHandler()
        let previous = current
        unregister()

        guard let shortcut else {
            GlobalShortcut.save(nil)
            isSavedShortcutUnavailable = false
            return true
        }
        guard register(shortcut) else {
            if previous != nil {
                registerSaved()
            }
            return false
        }
        GlobalShortcut.save(shortcut)
        isSavedShortcutUnavailable = false
        return true
    }

    /// Stops listening while a new shortcut is recorded, so pressing the old one records it
    /// instead of opening the game.
    static func suspend() {
        unregister()
    }

    static func resume() {
        guard hotKeyRef == nil else { return }
        registerSaved()
    }

    private static func registerSaved() {
        guard let current else {
            isSavedShortcutUnavailable = false
            return
        }
        isSavedShortcutUnavailable = !register(current)
    }

    private static func register(_ shortcut: GlobalShortcut) -> Bool {
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else { return false }
        hotKeyRef = ref
        return true
    }

    private static func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
    }

    private static func installHandler() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var pressedID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &pressedID
            )
            guard status == noErr, pressedID.signature == 0x4D4D_686B, pressedID.id == 1 else {
                return OSStatus(eventNotHandledErr)
            }
            // Carbon calls this on the main thread, from the event loop.
            MainActor.assumeIsolated { GlobalHotKey.onPress?() }
            return noErr
        }, 1, &eventType, nil, &handlerRef)
    }
}
