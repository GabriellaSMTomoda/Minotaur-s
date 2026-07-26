import SwiftUI

struct ContentView: View {
    @State private var status = "aguardando"
    @State private var deviceInfo = ""
    @State private var started = false

    var body: some View {
        NavigationView {
            List {
                Section("Dispositivo") {
                    Text(deviceInfo).font(.caption).textSelection(.enabled)
                }
                Section("Status") {
                    Text(status).font(.caption).foregroundColor(.secondary)
                    Text("Acompanhe o progresso pelo console (devicectl --console).")
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
            .navigationTitle("Spike 4b — DDG/URLSession")
            .onAppear {
                deviceInfo = "\(UIDevice.current.model) · iOS \(UIDevice.current.systemVersion)"
                guard !started else { return }
                started = true
                status = "rodando…"
                Task {
                    print(deviceInfo)
                    let json = await DDGSpike.mainFlow()
                    print("RESULTJSON_BEGIN")
                    print(json)
                    print("RESULTJSON_END")
                    status = "concluído — ver console"
                    // Folga para o stdout escoar antes de sair (harness descartável).
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    exit(EXIT_SUCCESS)
                }
            }
        }
    }
}
