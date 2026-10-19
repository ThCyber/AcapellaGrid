import SwiftUI

@main
struct AcapellaGridApp: App {
    @StateObject private var project: Project
    @StateObject private var transport: Transport

    init() {
        let project = Project()
        _project = StateObject(wrappedValue: project)
        _transport = StateObject(wrappedValue: Transport(project: project))
    }

    var body: some Scene {
        WindowGroup("Acapella Grid") {
            ContentView()
                .environmentObject(project)
                .environmentObject(transport)
                .frame(minWidth: 980, minHeight: 700)
                .task { await transport.setup() }
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
