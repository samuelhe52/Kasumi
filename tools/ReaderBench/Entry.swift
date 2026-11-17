import Foundation

@main struct ReaderBench {
    static func main() async throws {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.count == 2, args[0] == "--corpus" {
            let root = URL(fileURLWithPath: args[1])
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            for item in BenchmarkCase.all {
                try Data(item.source.utf8).write(to: root.appendingPathComponent(item.id + ".md"))
            }
            try writeJSON(["schema": 1, "generator": "LabSample-v1-en_US", "cases": BenchmarkCase.all.map(\.manifest)],
                          to: root.appendingPathComponent("manifest.json").path)
            return
        }
        if args.count == 6, args[0] == "--worker", let item = BenchmarkCase.all.first(where: { $0.id == args[2] }) {
            let phase = args[1], startState = hostState()
            let readStart = ContinuousClock.now
            let data = try Data(contentsOf: URL(fileURLWithPath: args[3]))
            guard let source = String(data: data, encoding: .utf8) else { throw BenchError.invalid("source decoding") }
            let readMs = milliseconds(readStart)
            let worker = Worker(item: item, source: source, full: args[5] == "full")
            let result: [String: Any]
            switch phase {
            case "cold": result = try await worker.open(warm: false, fileStart: readStart)
            case "warm": result = try await worker.open(warm: true)
            case "resize": result = try await worker.resize()
            case "afterPrepare": result = try await worker.afterPrepare()
            case "paint": result = try await worker.painting()
            case "find": result = try await worker.find()
            case "memory": result = try await worker.memory()
            default: throw BenchError.invalid("unknown worker phase")
            }
            // Validate after measurements so generator/locale setup cannot warm cold initialization.
            guard Data(source.utf8) == Data(item.source.utf8) else { throw BenchError.invalid("worker source differs from generator") }
            try writeJSON(["schema": 1, "phase": phase, "case": item.id, "corpus": item.manifest,
                           "valid": true,
                           "geometry": phase == "memory" ? ["width": 900, "height": 714, "fontSize": 18, "scale": 1] : ["width": 1179, "height": 701, "fontSize": 18, "scale": 2],
                           "readDecodeMs": readMs, "hostStart": startState, "hostEnd": hostState(), "result": result], to: args[4])
            return
        }
        throw BenchError.invalid("Usage: --corpus DIR | --worker PHASE CASE SOURCE OUTPUT quick|full")
    }
}
