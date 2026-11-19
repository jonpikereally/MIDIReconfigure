import AppKit
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

    func applicationDidFinishLaunching(_ notification: Notification) {
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

        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarPanel(model: model, openWorkspace: { [weak self] in self?.showWorkspace($0) })
        )
        makeMainMenu()
        model.start()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showWorkspace(model.workspaceSection)
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
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
                contentRect: NSRect(x: 0, y: 0, width: 920, height: 630),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false
            )
            window.title = "MIDI Reconfigure"
            window.titleVisibility = .hidden
            window.minSize = NSSize(width: 760, height: 500)
            window.isReleasedWhenClosed = false
            window.tabbingMode = .disallowed
            window.contentViewController = NSHostingController(rootView: WorkspaceHost(model: model))
            window.center()
            window.setFrameAutosaveName("MIDIReconfigure.Workspace")
            workspace = window
        }
        NSApp.activate()
        workspace?.deminiaturize(nil)
        workspace?.makeKeyAndOrderFront(nil)
    }

    private func makeMainMenu() {
        let main = NSMenu()
        let application = NSMenuItem()
        let applicationMenu = NSMenu(title: "MIDI Reconfigure")
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
        NSApp.mainMenu = main
    }
}

private struct WorkspaceHost: View {
    @ObservedObject var model: AppModel

    var body: some View {
        WorkspaceView(model: model, selection: $model.workspaceSection)
    }
}
