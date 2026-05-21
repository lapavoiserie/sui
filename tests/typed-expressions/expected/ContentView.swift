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
            }
            ForEach(appState.todos, id: \.self) { item in
                Text("\(item)")
            }
            Button("Inc") {
                appState.count += 1
            }
            Button("Reset") {
                appState.count = 0
            }
            Button("Toggle") {
                appState.isVisible.toggle()
            }
        }
            .sheet(isPresented: $appState.sheetOpen) {
                Text("Modal")
            }
    }
}
