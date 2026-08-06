import SwiftUI
import UIKit

/// App de medição do Spike 8 (NÃO é o app principal). Ver RESULTADO.md.
@main
struct RAMGateApp: App {
    init() {
        // stdout sem buffer: se o processo morrer por jetsam no meio do gate — que é
        // um desfecho possível e informativo aqui — as linhas já impressas precisam
        // ter chegado ao console do devicectl.
        setbuf(stdout, nil)
    }

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ContentView: View {
    @State private var results: [GateRun.StageResult] = []
    @State private var running = false
    @State private var device = ""

    var body: some View {
        NavigationView {
            List {
                Section("Dispositivo") {
                    Text(device).font(.caption)
                    Text("Teto NF-06: 1024 MB").font(.caption).foregroundColor(.secondary)
                }
                Section(running ? "Rodando…" : "Etapas") {
                    ForEach(results.indices, id: \.self) { index in
                        let r = results[index]
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.stage).font(.headline)
                            Text(r.detail).font(.caption2).foregroundColor(.secondary)
                            Text(String(format: "pico footprint %.0f MB · pico resident %.0f MB",
                                        r.peakFootprintMB, r.peakResidentMB))
                                .font(.caption)
                                .foregroundColor(r.peakFootprintMB > 1024 ? .red : .primary)
                            if r.predictions > 0 {
                                Text(String(format: "%d predições · mediana %.1f ms",
                                            r.predictions, r.medianPredictionMs))
                                    .font(.caption2).foregroundColor(.secondary)
                            }
                        }.padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("Gate de RAM")
            .onAppear {
                device = "\(UIDevice.current.model) · iOS \(UIDevice.current.systemVersion)"
                guard !running, results.isEmpty else { return }
                running = true
                let scenario = ProcessInfo.processInfo.environment["GATE_SCENARIO"] ?? "real"
                DispatchQueue.global(qos: .userInitiated).async {
                    print("=== INICIO GATE DE RAM (Spike 8) — cenário \(scenario) ===")
                    print(device)
                    let produced = GateRun.run(scenario: scenario) { print($0) }
                    print("=== FIM GATE DE RAM ===")
                    DispatchQueue.main.async {
                        results = produced
                        running = false
                        // O harness existe para o console; sair sozinho fecha o
                        // `devicectl process launch --console` sem intervenção manual.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { exit(0) }
                    }
                }
            }
        }
    }
}
