import AppKit
import SwiftUI

@MainActor
final class OverlayController {
    private var panel: OverlayPanel?
    private var dismissTimer: Timer?
    private var keyMonitor: Any?
    private var onDone: (() -> Void)?

    func show<Content: View>(
        screen: NSScreen,
        autoDismiss: TimeInterval,
        onDone: @escaping () -> Void,
        content: Content
    ) {
        dismiss()
        self.onDone = onDone

        let panel = OverlayPanel(contentRect: screen.frame)
        let host = NSHostingView(rootView: content)
        host.sizingOptions = []
        host.translatesAutoresizingMaskIntoConstraints = true
        host.autoresizingMask = [.width, .height]
        let container = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
        host.frame = container.bounds
        container.addSubview(host)
        panel.contentView = container
        panel.setFrame(screen.frame, display: true)
        container.frame = CGRect(origin: .zero, size: panel.frame.size)
        host.frame = container.bounds

        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
        Log.info(
            "panel visible=\(panel.isVisible) level=\(panel.level.rawValue) frame=\(NSStringFromRect(panel.frame)) windows=\(NSApp.windows.count)"
        )

        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                Task { @MainActor in
                    self?.onDone?()
                }
                return nil
            }
            return event
        }
        keyMonitor = monitor

        let timer = Timer(timeInterval: autoDismiss, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onDone?()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        dismissTimer = timer
    }

    func dismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        onDone = nil
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }

    static func screenContainingMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
    }
}
