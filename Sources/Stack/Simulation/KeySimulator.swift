import Foundation
import AppKit
import CoreGraphics
import ApplicationServices

@MainActor
public final class KeySimulator {
    public static let shared = KeySimulator()

    private init() {}

    /// Checks if Accessibility privileges are enabled
    public static func isAccessibilityEnabled() -> Bool {
        return AXIsProcessTrusted()
    }

    /// Requests Accessibility privileges (prompts system alert if not granted)
    @discardableResult
    public static func promptAccessibilityPermission() -> Bool {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let options = [key: kCFBooleanTrue] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Opens macOS System Settings directly to Accessibility page
    public static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Reveals Stack.app in Finder and opens Accessibility settings so user can easily drag & drop
    public static func revealInFinderForDragAndDrop() {
        promptAccessibilityPermission()
        let appUrl = URL(fileURLWithPath: "/Applications/Stack.app")
        if FileManager.default.fileExists(atPath: appUrl.path) {
            NSWorkspace.shared.activateFileViewerSelecting([appUrl])
        } else {
            let bundleUrl = Bundle.main.bundleURL
            NSWorkspace.shared.activateFileViewerSelecting([bundleUrl])
        }
        openAccessibilitySettings()
    }

    /// Copies the given item to NSPasteboard.general with robust watcher synchronization
    public static func copyToPasteboard(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general

        // Pause watcher so it doesn't process Stack's own clipboard update
        ClipboardWatcher.shared.pause()
        pasteboard.clearContents()

        switch item.contentType {
        case .image:
            if let fileName = item.imageFileName,
               let image = ClipboardStorage.shared.loadImage(fileName: fileName) {
                // Write multiple image representations for maximum compatibility across all apps
                if let tiffData = image.tiffRepresentation {
                    pasteboard.setData(tiffData, forType: .tiff)
                    if let rep = NSBitmapImageRep(data: tiffData),
                       let pngData = rep.representation(using: .png, properties: [:]) {
                        pasteboard.setData(pngData, forType: .png)
                    }
                }
                pasteboard.writeObjects([image])
            }

        case .url:
            if let text = item.textContent {
                // Set both plain string and URL types
                pasteboard.setString(text, forType: .string)
                pasteboard.setString(text, forType: .URL)
                if let url = URL(string: text) {
                    pasteboard.writeObjects([url as NSURL])
                }
            }

        case .text, .code, .color, .all:
            if let text = item.textContent {
                pasteboard.setString(text, forType: .string)
            }
        }

        // Align watcher to current pasteboard generation and resume
        ClipboardWatcher.shared.updateLastChangeCount(to: pasteboard.changeCount)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            ClipboardWatcher.shared.resume()
        }
    }

    /// Simulates Cmd + V key combination via CGEvent with AppleScript fallback
    public static func simulatePaste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKeyCode: CGKeyCode = 0x09 // Virtual key code for 'V'

        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
           let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) {
            keyDown.flags = .maskCommand
            keyUp.flags = .maskCommand

            // Post to the session event tap (for regular focused apps)
            keyDown.post(tap: .cgAnnotatedSessionEventTap)
            keyUp.post(tap: .cgAnnotatedSessionEventTap)
        }

        // If accessibility is not granted or as extra resilience, trigger System Events
        if !AXIsProcessTrusted() {
            fallbackAppleScriptPaste()
        }
    }

    public static func fallbackAppleScriptPaste() {
        let script = "tell application \"System Events\" to keystroke \"v\" using command down"
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if let err = error {
                print("[KeySimulator] Fallback AppleScript notice: \(err)")
            }
        }
    }

    /// Performs the complete paste action:
    /// 1. Copy item to pasteboard
    /// 2. Reactivate previous application
    /// 3. Simulate Cmd + V
    public static func executePaste(item: ClipboardItem, targetApp: NSRunningApplication?, completion: (() -> Void)? = nil) {
        // 1. Copy item to pasteboard
        copyToPasteboard(item)

        // 2. Focus previous application if available
        if let app = targetApp, !app.isTerminated {
            app.activate(options: [.activateIgnoringOtherApps])
        }

        // 3. Wait 200ms for target app to regain window & text cursor focus before posting Cmd + V
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
            simulatePaste()
            completion?()
        }
    }
}
