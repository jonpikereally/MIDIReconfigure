import AppKit
import Combine
import SwiftUI

@main
enum MIDIReconfigureApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private var workspace: NSWindow?
    private var observers: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarPanel(model: model, openWorkspace: { [weak self] in self?.showWorkspace($0) })
        )
        makeMainMenu()

        // @Published sinks receive the new value before the property changes.
        model.$showInMenuBar.removeDuplicates().sink { [weak self] in self?.setMenuBarIcon(visible: $0) }
            .store(in: &observers)
        model.$showInDock.removeDuplicates().dropFirst().sink { [weak self] in self?.setDockIcon(visible: $0) }
            .store(in: &observers)
        setDockIcon(visible: model.showInDock)

        model.start()
        model.updater.start()
        if model.showInDock { showWorkspace(model.workspaceSection) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showWorkspace(model.workspaceSection)
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }

    private func setMenuBarIcon(visible: Bool) {
        if !visible {
            popover.performClose(nil)
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
            return
        }
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "MIDIReconfigure"
        if let button = item.button {
            let image = NSImage(systemSymbolName: "arrow.triangle.branch",
                                accessibilityDescription: "MIDI Reconfigure")
                ?? NSImage(systemSymbolName: "arrow.left.arrow.right", accessibilityDescription: "MIDI Reconfigure")
            image?.isTemplate = true
            button.image = image
            button.target = self
            button.action = #selector(togglePopover)
            button.setAccessibilityLabel("MIDI Reconfigure")
            button.toolTip = "MIDI Reconfigure"
        }
        statusItem = item
    }

    private func setDockIcon(visible: Bool) {
        let windowWasVisible = workspace?.isVisible == true
        NSApp.setActivationPolicy(visible ? .regular : .accessory)
        if windowWasVisible {
            // Changing the policy can hide the app's windows; bring the main window back.
            DispatchQueue.main.async { [weak self] in self?.showWorkspace(self?.model.workspaceSection ?? .settings) }
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showWorkspace(_ section: WorkspaceSection) {
        popover.performClose(nil)
        model.workspaceSection = section
        if workspace == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1080, height: 680),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false
            )
            window.title = "MIDI Reconfigure"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.minSize = NSSize(width: 920, height: 540)
            window.isReleasedWhenClosed = false
            window.tabbingMode = .disallowed
            window.contentViewController = NSHostingController(rootView: WorkspaceHost(model: model))
            window.center()
            window.setFrameAutosaveName("MIDIReconfigure.MainWindow")
            workspace = window
        }
        NSApp.activate()
        workspace?.deminiaturize(nil)
        workspace?.makeKeyAndOrderFront(nil)
    }

    @objc private func showMainWindow() { showWorkspace(model.workspaceSection) }
    @objc private func showRouting() { showWorkspace(.routing) }
    @objc private func showFunctions() { showWorkspace(.functions) }
    @objc private func showActivity() { showWorkspace(.activity) }
    @objc private func showSettings() { showWorkspace(.settings) }
    @objc private func showErrors() { showWorkspace(.errors) }

    @objc private func checkForUpdates() {
        showWorkspace(.settings)
        model.updater.check()
    }

    private func makeMainMenu() {
        let main = NSMenu()
        let application = NSMenuItem()
        let applicationMenu = NSMenu(title: "MIDI Reconfigure")
        applicationMenu.addItem(withTitle: "About MIDI Reconfigure",
                                action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        applicationMenu.addItem(item("Check for Updates…", #selector(checkForUpdates)))
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(item("Settings…", #selector(showSettings), key: ","))
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: "Hide MIDI Reconfigure", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: "Quit MIDI Reconfigure", action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q")
        application.submenu = applicationMenu
        main.addItem(application)

        let edit = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.submenu = editMenu
        main.addItem(edit)

        let view = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(item("Routing", #selector(showRouting), key: "1"))
        viewMenu.addItem(item("Functions", #selector(showFunctions), key: "2"))
        viewMenu.addItem(item("Activity", #selector(showActivity), key: "3"))
        viewMenu.addItem(item("Settings", #selector(showSettings), key: "4"))
        viewMenu.addItem(item("Errors", #selector(showErrors), key: "5"))
        view.submenu = viewMenu
        main.addItem(view)

        let window = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(item("Main Window", #selector(showMainWindow), key: "0"))
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.submenu = windowMenu
        main.addItem(window)
        NSApp.windowsMenu = windowMenu
        NSApp.mainMenu = main
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }
}

private struct WorkspaceHost: View {
    @ObservedObject var model: AppModel

    var body: some View {
        WorkspaceView(model: model, selection: $model.workspaceSection)
    }
}
