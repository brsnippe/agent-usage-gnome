import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var status: StatusController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Assets.registerFonts()

        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--snapshot") {
            let folder = index + 1 < arguments.count ? arguments[index + 1] : "snapshots"
            do {
                try Snapshot.run(into: folder)
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("snapshot failed: \(error)\n".utf8))
                exit(1)
            }
        }

        let model = AppModel()
        status = StatusController(model: model)
        self.model = model
        model.start()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// A menu bar app: no Dock icon, no menu bar of its own.
app.setActivationPolicy(.accessory)
app.run()
