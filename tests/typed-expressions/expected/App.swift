import SwiftUI

@main
struct TestTypedExpressionsApp: App {
    init() {
        HaxeBridgeC.registerCallbacks()
        HaxeRuntime.initialize()
    }


    var body: some Scene {
        WindowGroup("TestTypedExpr", id: "sui-primary") {
            ContentView()
        }
    }
}
