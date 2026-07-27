import CoreML
import SwiftUI

struct ContentView: View {
    @State private var results: [BenchResult] = []
    @State private var running = false
    @State private var deviceInfo = ""
    @State private var status = ""

    var body: some View {
        NavigationView {
            List {
                Section("Dispositivo") {
                    Text(deviceInfo).font(.caption).textSelection(.enabled)
                    Text(status).font(.caption).foregroundColor(.secondary)
                }
                Section {
                    Button(running ? "Rodando…" : "Rodar benchmark") { runAll() }
                        .disabled(running)
                }
                Section("Resultados (Filtro 2 — execução NLI)") {
                    if results.isEmpty {
                        Text("Toque em “Rodar benchmark”.").foregroundColor(.secondary)
                    }
                    ForEach(results) { r in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(r.model) · \(r.units)").font(.headline)
                            if r.ran {
                                Text(r.argmaxMatch
                                     ? String(format: "✅ logits OK (cos %.4f)", r.cosVsRef)
                                     : String(format: "⚠️ logits DIVERGEM (cos %.4f, argmax %d≠%d)",
                                              r.cosVsRef, r.gotArgmax, r.expectedArgmax))
                                    .font(.caption)
                                Text(String(format: "mediana %.1f ms · seq %d · RAM pico %.0f MB",
                                            r.medianMs, r.seqLen, r.ramPeakMB))
                                    .font(.caption).foregroundColor(.secondary)
                            } else {
                                Text("❌ NÃO EXECUTOU\n\(r.error ?? "?")")
                                    .font(.caption).foregroundColor(.red)
                            }
                        }.padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("CoreML Bench 2c")
            .onAppear {
                deviceInfo = "\(UIDevice.current.model) · iOS \(UIDevice.current.systemVersion)"
                if !running && results.isEmpty { runAll() }
            }
        }
    }

    private func runAll() {
        running = true
        results = []
        DispatchQueue.global(qos: .userInitiated).async {
            print("=== INICIO COREML BENCH 2c ===")
            print(deviceInfo)

            guard let manifest = Benchmark.loadManifest() else {
                print("ERRO: manifest.json ausente no bundle")
                DispatchQueue.main.async { status = "manifest ausente"; running = false }
                return
            }
            let specs = manifest.models.filter { $0.converts }

            // Filtros opcionais por env: isola crashes (uma execução por combo).
            let env = ProcessInfo.processInfo.environment
            let onlyModel = env["BENCH_MODEL"]          // ex.: "L6"
            let onlyUnits = env["BENCH_UNITS"]          // "all" | "cpuOnly"

            // .cpuOnly ANTES de .all: se .all crashar o processo, os dados de
            // .cpuOnly já foram impressos (achado do Spike 2: .all crashou o NLI).
            var unitPlan: [(MLComputeUnits, String)] = [(.cpuOnly, "cpuOnly"), (.all, "all")]
            if let u = onlyUnits {
                unitPlan = unitPlan.filter { $0.1 == u }
            }

            for (units, label) in unitPlan {
                for spec in specs {
                    if let om = onlyModel, om != spec.short { continue }
                    DispatchQueue.main.async { status = "rodando \(spec.short) · \(label)…" }
                    print(">>> RUN \(spec.short) units=\(label)")
                    let r = Benchmark.run(spec: spec, units: units, unitsLabel: label)
                    Benchmark.printLine(r)                 // parseável do console
                    DispatchQueue.main.async { results.append(r) }
                }
            }

            print("=== FIM COREML BENCH 2c ===")
            DispatchQueue.main.async { running = false; status = "concluído" }
            // Sai após o run p/ que a captura de console (simctl/devicectl
            // --console) termine de forma determinística. Harness descartável.
            // 1.5s de folga para o stdout escoar (setbuf já é unbuffered).
            if ProcessInfo.processInfo.environment["BENCH_NO_EXIT"] == nil {
                Thread.sleep(forTimeInterval: 1.5)
                exit(EXIT_SUCCESS)
            }
        }
    }
}
