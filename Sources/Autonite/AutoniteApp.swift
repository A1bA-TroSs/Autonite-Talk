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
            // The Pass 0 harness (Lab) opens from the gear on the Autunite header, for evidence runs.
            Pass1RootView(model: pass1)
            .task {
                if SelfTest.isRequested { await SelfTest.run(lab) }
            }
        }
    }
}
#endif
