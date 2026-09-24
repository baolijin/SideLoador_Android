import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    RegisterGeneratedPlugins(registry: flutterViewController)
    super.awakeFromNib()

    // Desktop-sized window, centered on the main screen (not phone ratio).
    let preferred = NSSize(width: 1280, height: 860)
    if let screen = NSScreen.main {
      let visible = screen.visibleFrame
      let w = min(preferred.width, max(640, visible.width - 40))
      let h = min(preferred.height, max(480, visible.height - 40))
      let origin = NSPoint(
        x: visible.midX - w / 2,
        y: visible.midY - h / 2
      )
      self.setFrame(
        NSRect(origin: origin, size: NSSize(width: w, height: h)),
        display: true,
        animate: false
      )
    } else {
      self.setContentSize(preferred)
      self.center()
    }

    self.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
}
