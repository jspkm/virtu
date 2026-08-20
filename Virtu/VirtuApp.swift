import SwiftUI
import SwiftData

@main
struct VirtuApp: App {
    @State private var appState = AppState()

    let container: ModelContainer = {
        let schema = Schema([Work.self, Part.self, AnnotationLayer.self, Program.self, ProgramItem.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: false)
        return try! ModelContainer(for: schema, configurations: [config])
    }()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(appState)
                .environment(\.theme, appState.theme)
                .modelContainer(container)
                .onAppear {
                    SeedData.seedIfNeeded(context: container.mainContext)
                }
        }
    }
}
