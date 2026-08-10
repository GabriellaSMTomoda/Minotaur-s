import SwiftUI
import UIKit

@main
struct ArchitectureGateApp: App {
    init() { setbuf(stdout, nil) }

    var body: some Scene {
        WindowGroup { GateView() }
    }
}

struct GateView: View {
    @State private var running = false
    @State private var summary = "Aguardando"

    var body: some View {
        VStack(spacing: 12) {
            Text("Spike 9 · Gate de arquitetura").font(.headline)
            Text("iPhone físico · .cpuOnly").font(.caption)
            Text(summary).font(.caption).multilineTextAlignment(.center)
        }
        .padding()
        .onAppear {
            guard !running else { return }
            running = true
            let env = ProcessInfo.processInfo.environment
            let scenario = env["GATE_SCENARIO"] ?? "real"
            let variant = env["GATE_VARIANT"] ?? "bertimbau_base_dynamic512"
            let fixed = Int(env["GATE_FIXED_LENGTH"] ?? "")
            DispatchQueue.global(qos: .userInitiated).async {
                print("=== SPIKE 9 ETAPA 2 · \(variant) · \(scenario) ===")
                print("\(UIDevice.current.model) · iOS \(UIDevice.current.systemVersion)")
                let result = ArchitectureGate.run(
                    scenario: scenario, variant: variant, fixedLength: fixed
                ) { print($0) }
                print("=== FIM SPIKE 9 ETAPA 2 ===")
                DispatchQueue.main.async {
                    summary = result
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { exit(0) }
                }
            }
        }
    }
}
