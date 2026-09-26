import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // No dock icon

// Must be a global to prevent ARC from releasing the delegate
// (NSApplication.delegate is a weak reference).
let appDelegate = AppDelegate()
app.delegate = appDelegate

app.run()
