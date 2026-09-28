import Carbon
import Foundation

/// Uses Carbon registration so a conflict is reported instead of silently losing the shortcut.
final class GlobalHotKeyManager {
    private static let signature: OSType = 0x4F544154 // OTAT
    private static let identifier: UInt32 = 1

    private let action: @MainActor () -> Void
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    init(action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32) -> Bool {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        if handler == nil {
            var eventType = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            )
            let status = InstallEventHandler(
                GetApplicationEventTarget(),
                Self.handleEvent,
                1,
                &eventType,
                Unmanaged.passUnretained(self).toOpaque(),
                &handler
            )
            guard status == noErr else { return false }
        }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.identifier)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive),
            &hotKey
        )
        if status != noErr { hotKey = nil }
        return status == noErr
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }

    private static let handleEvent: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else { return OSStatus(eventNotHandledErr) }
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr,
              hotKeyID.signature == signature,
              hotKeyID.id == identifier else {
            return OSStatus(eventNotHandledErr)
        }
        let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
        let action = manager.action
        DispatchQueue.main.async { action() }
        return noErr
    }
}
