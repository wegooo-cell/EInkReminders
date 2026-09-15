import SwiftUI

@main
struct EInkRemindersApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(model)
        }
        .windowResizability(.contentSize)

        MenuBarExtra("墨水屏提醒事项", systemImage: "rectangle.and.pencil.and.ellipsis") {
            Text(model.statusText)
            Button("立即同步") { Task { await model.sync(force: true) } }
            Divider()
            Button("退出") { NSApplication.shared.terminate(nil) }
        }
    }
}
