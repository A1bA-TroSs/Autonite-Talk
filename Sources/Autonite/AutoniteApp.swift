#if os(iOS)
import SwiftUI

@main
struct AutoniteApp: App {
    @State private var lab: FeasibilityModel
    @State private var pass1: Pass1Model

    init() {
        let lab = FeasibilityModel()
        _lab = State(initialValue: lab)
        _pass1 = State(initialValue: Pass1Model(lab: lab))
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                Pass1RootView(model: pass1)
                    .tabItem { Label("Autunite", systemImage: "waveform.circle") }
                // The Pass 0 harness stays available for evidence runs.
                FeasibilityView(model: lab)
                    .tabItem { Label("Lab", systemImage: "testtube.2") }
            }
            .task {
                if SelfTest.isRequested { await SelfTest.run(lab) }
            }
        }
    }
}
#endif
