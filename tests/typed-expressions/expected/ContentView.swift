import SwiftUI

struct ContentView: View {
    @Bindable var appState = AppState.shared

    var body: some View {
        VStack {
            Text("\(appState.name)")
            Text("Count: \(appState.count)")
            Text("\((appState.isVisible ? "shown" : "hidden"))")
            ForEach(0..<appState.todos.count, id: \.self) { i in
                HStack(spacing: 8) {
                    Image(systemName: "circle.fill")
                        .foregroundStyle(Color(suiHex: appState.colors[i]) ?? Color.primary)
                    Text("\(appState.todos[i])")
                }
                    .onTapGesture { Task.detached { HaxeBridgeC.invokeIndexedAction(337946475, i, -1) } }
            }
            let __arr0 = appState.todos
            ForEach(0..<__arr0.count, id: \.self) { __i0 in
                let item = __arr0[__i0]
                Text("\(item)")
                    .onTapGesture { Task.detached { HaxeBridgeC.invokeIndexedAction(838190797, __i0, -1) } }
            }
            Button {
                Task.detached { HaxeBridgeC.invokeAction(1850389800) }
            } label: {
                    Image(systemName: "gear")
                        .foregroundStyle(.secondary)
            }
            Button("Inc") {
                Task.detached { HaxeBridgeC.invokeAction(1463985449) }
            }
            Button("Reset") {
                Task.detached { HaxeBridgeC.invokeAction(1867167419) }
            }
            Button("Toggle") {
                Task.detached { HaxeBridgeC.invokeAction(1397807425) }
            }
        }
            .sheet(isPresented: $appState.sheetOpen) {
                Text("Modal")
            }
    }
}
