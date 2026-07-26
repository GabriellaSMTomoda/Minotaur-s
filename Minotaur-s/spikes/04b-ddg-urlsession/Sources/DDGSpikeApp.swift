import SwiftUI

// App de medição do Spike 4b (NÃO é o app principal). Ver RESULTADO.md.
@main
struct DDGSpikeApp: App {
    init() {
        // stdout sem buffer: garante que os prints cheguem ao console
        // capturado (devicectl --console) mesmo se o processo terminar
        // logo após o run.
        setbuf(stdout, nil)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
