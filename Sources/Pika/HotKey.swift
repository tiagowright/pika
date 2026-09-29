import Carbon.HIToolbox
import AppKit
import os

private let log = Logger(subsystem: "io.github.tiagowright.pika", category: "hotkey")

/// A global hotkey via Carbon's `RegisterEventHotKey` — kernel-dispatched,
/// not a `CGEventTap`, so it needs no Input Monitoring permission and
/// costs <1ms to fire (TECHNICAL.md §1/§6).
final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let signature: OSType = OSType(0x5049_4B41) // 'PIKA'
    private let id: UInt32 = 1
    var onPressed: (() -> Void)?

    /// The result of the last `register`. Anything but `noErr` usually
    /// means another app already registered it (SHIPPING.md §4.2). macOS's
    /// own shortcuts don't show up here — see `SystemShortcuts`.
    private(set) var status: OSStatus = noErr
    private(set) var hasAttempted = false
    var isRegistered: Bool { hotKeyRef != nil }

    /// Replaces any previously registered hotkey. Safe to call again
    /// when the config changes.
    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32) -> OSStatus {
        installHandlerIfNeeded()
        hasAttempted = true
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        var ref: EventHotKeyRef?
        status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr {
            hotKeyRef = ref
        } else {
            log.error("RegisterEventHotKey failed with \(self.status) — another app likely owns this hotkey")
        }
        return status
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, eventRef, userData in
            guard let userData, let eventRef else { return noErr }
            var hkID = EventHotKeyID()
            GetEventParameter(eventRef, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            if hkID.id == manager.id { manager.onPressed?() }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        hotKeyRef = nil
        eventHandler = nil
    }
}
