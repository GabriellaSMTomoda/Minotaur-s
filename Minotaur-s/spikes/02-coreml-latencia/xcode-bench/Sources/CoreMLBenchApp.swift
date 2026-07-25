import SwiftUI

// App de medição do Spike 2 (NÃO é o app principal). Ver README.md.
@main
struct CoreMLBenchApp: App {
    init() {
        // stdout sem buffer: garante que os prints do benchmark cheguem ao
        // console capturado (simctl/devicectl) mesmo se o processo for
        // finalizado abruptamente antes de um flush natural.
        setbuf(stdout, nil)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
