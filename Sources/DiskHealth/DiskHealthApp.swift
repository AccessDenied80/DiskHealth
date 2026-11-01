import DiskHealthCore
import SwiftUI

@main
struct DiskHealthApp: App {
    @StateObject private var settings: AppSettings
    @StateObject private var model: AppModel

    init() {
        let settings = AppSettings()
        let model = AppModel(settings: settings)
        _settings = StateObject(wrappedValue: settings)
        _model = StateObject(wrappedValue: model)
        #if DEBUG
        if let dir = Snapshot.outputDir {
            Snapshot.run(model: model, settings: settings, to: dir)
            return
        }
        #endif
        model.start()
    }

    var body: some Scene {
        MenuBarExtra {
            DiskListView()
                .environmentObject(model)
                .environmentObject(settings)
        } label: {
            Image(systemName: model.overall.menuBarSymbol)
                .symbolRenderingMode(.palette)
                .foregroundStyle(model.overall >= .warning ? model.overall.color : .primary)
        }
        .menuBarExtraStyle(.window)
    }
}
