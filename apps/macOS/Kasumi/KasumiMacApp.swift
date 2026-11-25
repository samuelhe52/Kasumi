import AppKit
import SwiftUI

@main
enum KasumiMacApp {
    @MainActor
    static func main() {
        let app = MacApplication.shared
        let delegate = MacAppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class MacApplication: NSApplication {
    override func terminate(_ sender: Any?) {
        // AppKit reviews documents before consulting the application delegate.
        for case let document as MacDocument in NSDocumentController.shared.documents {
            document.finishPendingEdits()
        }
        super.terminate(sender)
    }
}

@MainActor
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    // Install the custom controller before SwiftUI can create the default one.
    private let documents = MacDocumentController()
    private var tabShortcutMonitor: Any?
    private lazy var settingsScene = NSHostingSceneRepresentation { Settings { MacSettings() } }
    private lazy var licensesWindow = MacLicensesWindowController()

    func applicationWillFinishLaunching(_ notification: Notification) {
        _ = FontStore.shared
        NSWindow.allowsAutomaticWindowTabbing = true
        NSApp.addSceneRepresentation(settingsScene)
        NSApp.mainMenu = MacMenu.make(appDelegate: self)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        tabShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let window = NSApp.keyWindow, window.windowController?.document is MacDocument,
                (window.tabGroup?.windows.count ?? 0) > 1, window.attachedSheet == nil
            else { return event }

            let modifiers = event.modifierFlags.intersection([.command, .option, .shift, .control])
            switch (modifiers, event.charactersIgnoringModifiers) {
            case ([.command, .shift], "["), ([.command, .shift], "{"):
                window.selectPreviousTab(nil)
            case ([.command, .shift], "]"), ([.command, .shift], "}"):
                window.selectNextTab(nil)
            case ([.command, .option], _) where event.keyCode == 123,
                ([.control, .shift], _) where event.keyCode == 48:
                window.selectPreviousTab(nil)
            case ([.command, .option], _) where event.keyCode == 124,
                ([.control], _) where event.keyCode == 48:
                window.selectNextTab(nil)
            default:
                return event
            }
            return nil
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let tabShortcutMonitor { NSEvent.removeMonitor(tabShortcutMonitor) }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    @objc func showSettings(_ sender: Any?) {
        settingsScene.environment.openSettings()
    }

    @objc func showLicenses(_ sender: Any?) {
        licensesWindow.showWindow(sender)
    }
}
