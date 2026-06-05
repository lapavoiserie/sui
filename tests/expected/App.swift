import SwiftUI

@main
struct TestSwiftGenApp: App {
    init() {
        HaxeBridgeC.registerCallbacks()
        HaxeRuntime.initialize()
    }


    var body: some Scene {
        WindowGroup("TestApp") {
            ContentView()
        }
    }
}
