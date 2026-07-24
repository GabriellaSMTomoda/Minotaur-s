import CoreML
import SwiftUI

struct ContentView: View {
    @State private var results: [BenchResult] = []
    @State private var running = false
    @State private var deviceInfo = ""

    var body: some View {
        NavigationView {
            List {
                Section("Dispositivo") {
                    Text(deviceInfo).font(.caption).textSelection(.enabled)
                }
                Section {
                    Button(running ? "Rodando…" : "Rodar benchmark") { runAll() }
                        .disabled(running)
                }
                Section("Resultados") {
                    if results.isEmpty {
                        Text("Toque em “Rodar benchmark”.").foregroundColor(.secondary)
                    }
                    ForEach(results) { r in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(r.name).font(.headline)
                            if r.loaded {
                                Text(String(format: "mediana %.1f ms · média %.1f ms",
                                            r.medianMs, r.meanMs))
                                Text(String(format: "min %.1f · max %.1f · seq %d · %d runs",
                                            r.minMs, r.maxMs, r.seqLen, r.runs))
                                    .font(.caption).foregroundColor(.secondary)
                                Text("compute units: \(r.computeUnits)")
                                    .font(.caption).foregroundColor(.secondary)
                            } else {
                                Text("ERRO: \(r.error ?? "?")")
                                    .font(.caption).foregroundColor(.red)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("CoreML Bench")
            .onAppear {
                deviceInfo = "\(UIDevice.current.model) · iOS \(UIDevice.current.systemVersion)"
            }
        }
    }

    private func runAll() {
        running = true
        results = []
        DispatchQueue.global(qos: .userInitiated).async {
            var out: [BenchResult] = []
            // NF-01: embeddings de um chunk < 150 ms (alvo).
            out.append(Benchmark.run(
                name: "Embeddings (chunk ~200 tok)", baseName: "Embeddings_int8",
                seqLen: 200, runs: 50, warmup: 5,
                computeUnits: .all, computeUnitsLabel: ".all"))
            // NF-02: NLI de um par < 1 s (alvo).
            out.append(Benchmark.run(
                name: "NLI (par ~256 tok)", baseName: "NLI_int8",
                seqLen: 256, runs: 50, warmup: 5,
                computeUnits: .all, computeUnitsLabel: ".all"))
            let snapshot = out
            DispatchQueue.main.async {
                results = snapshot
                running = false
                snapshot.forEach { print($0) }
            }
        }
    }
}
