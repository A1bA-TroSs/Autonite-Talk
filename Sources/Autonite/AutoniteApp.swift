#if os(iOS)
import SwiftUI

@main
struct AutoniteApp: App {
    @State private var model = FeasibilityModel()

    var body: some Scene {
        WindowGroup {
            FeasibilityView(model: model)
                .task {
                    if SelfTest.isRequested { await SelfTest.run(model) }
                }
        }
    }
}
#endif
