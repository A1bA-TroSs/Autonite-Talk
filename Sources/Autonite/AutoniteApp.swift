import SwiftUI

@main
struct AutoniteApp: App {
    @State private var model = FeasibilityModel()

    var body: some Scene {
        WindowGroup {
            FeasibilityView(model: model)
        }
    }
}
