import Foundation
import Carbon
import AppKit

@MainActor
public final class GlobalHotKeyManager {
    public static let shared = GlobalHotKeyManager()

    private var hudHotKeyRef: EventHotKeyRef?
    private var scrollCaptureHotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    public var onHUDHotKeyPressed: (@MainActor () -> Void)?
    public var onScrollingCaptureHotKeyPressed: (@MainActor () -> Void)?

    private init() {}

    /// Registers global hotkeys:
    /// - Cmd + Shift + V (HUD)
    /// - Cmd + Option + S (Capture Défilante)
    public func registerAll() {
        unregister()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handler: EventHandlerUPP = { (_, inEvent, _) -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                inEvent,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )

            if status == noErr {
                DispatchQueue.main.async {
                    if hotKeyID.id == 1 {
                        GlobalHotKeyManager.shared.onHUDHotKeyPressed?()
                    } else if hotKeyID.id == 2 {
                        GlobalHotKeyManager.shared.onScrollingCaptureHotKeyPressed?()
                    }
                }
            }
            return noErr
        }

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventType,
            nil,
            &eventHandler
        )

        if status != noErr {
            print("[GlobalHotKeyManager] Failed to install event handler: \(status)")
        }

        // 1. Hotkey for HUD: Cmd + Shift + V (Carbon keyCode 9)
        let hudID = EventHotKeyID(signature: OSType(0x5354434B), id: 1) // 'STCK'
        let regStatusHUD = RegisterEventHotKey(
            9, // 'V'
            UInt32(cmdKey | shiftKey),
            hudID,
            GetApplicationEventTarget(),
            0,
            &hudHotKeyRef
        )
        if regStatusHUD != noErr {
            print("[GlobalHotKeyManager] Failed to register HUD hotkey: \(regStatusHUD)")
        }

        // 2. Hotkey for Scrolling Capture: Cmd + Option + S (Carbon keyCode 1)
        let scrollID = EventHotKeyID(signature: OSType(0x5354434B), id: 2)
        let regStatusScroll = RegisterEventHotKey(
            1, // 'S'
            UInt32(cmdKey | optionKey),
            scrollID,
            GetApplicationEventTarget(),
            0,
            &scrollCaptureHotKeyRef
        )
        if regStatusScroll != noErr {
            print("[GlobalHotKeyManager] Failed to register Scroll Capture hotkey: \(regStatusScroll)")
        }
    }

    public func unregister() {
        if let ref = hudHotKeyRef {
            UnregisterEventHotKey(ref)
            self.hudHotKeyRef = nil
        }
        if let ref = scrollCaptureHotKeyRef {
            UnregisterEventHotKey(ref)
            self.scrollCaptureHotKeyRef = nil
        }
        if let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }
}
