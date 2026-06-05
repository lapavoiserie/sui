import SwiftUI

struct ContentView: View {
    @Bindable var appState = AppState.shared

    var body: some View {
        VStack {
            Text("Hello")
                .font(.largeTitle)
                .padding()
            Text("Value: \(appState.count)")
                .bold()
            HStack(spacing: 10) {
                Button("-") {
                    Task.detached { HaxeBridgeC.invokeAction(457868577) }
                }
                Button("+") {
                    Task.detached { HaxeBridgeC.invokeAction(1479726225) }
                }
            }
            Spacer()
        }
    }
}
