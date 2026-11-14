import Foundation

/// Package-only bridge for the executable; reader clients use the public facade.
package enum RenderCommand {
    package static func run(_ arguments: [String]) async throws -> String {
        let input = URL(fileURLWithPath: arguments[1])
        let source = try DocumentDecoder.decode(Data(contentsOf: input)).text
        let document = DocumentParser.parse(source, plainText: input.pathExtension == "txt", baseURL: input.deletingLastPathComponent())
        _ = await DocumentImageStore.shared.preload(document)
        var style = Typography(), width = 800.0, index = 3
        enum ArgumentError: LocalizedError {
            case invalid(String)
            var errorDescription: String? { switch self { case .invalid(let message): message } }
        }
        while index < arguments.count {
            let argument = arguments[index]; index += 1
            if argument == "--dark" { style.dark = true; continue }
            if let value = Double(argument), index == 4 { width = value; continue }
            guard ["--preset", "--profile", "--theme"].contains(argument), index < arguments.count else {
                throw ArgumentError.invalid("Unknown or incomplete option: \(argument)")
            }
            let value = arguments[index]; index += 1
            switch argument {
            case "--preset":
                guard let profile = BuiltinProfiles.all.first(where: { $0.id == value }) else { throw ArgumentError.invalid("Unknown preset: \(value)") }
                style = style.applying(profile.effective)
            case "--profile":
                var library = ProfileLibrary()
                try library.importProfile(String(contentsOfFile: value, encoding: .utf8), suggestedName: "Render profile")
                style = style.applying(library.selected.effective)
            default:
                guard let theme = DocumentThemeCatalog.themes.first(where: { $0.id == value }) else { throw ArgumentError.invalid("Unknown theme: \(value)") }
                style.dark = theme.dark
                if theme.dark { style.darkThemeID = theme.id } else { style.lightThemeID = theme.id }
            }
        }
        let output = URL(fileURLWithPath: arguments[2])
        if output.pathExtension.lowercased() == "pdf" {
            var options = PDFExportOptions(); options.title = input.lastPathComponent
            try DocumentExporter.writePDF(document, style: style, options: options, to: output)
        } else { try DocumentExporter.writeImage(document, style: style, width: width, scale: 1, to: output) }
        return "Exported \(document.blocks.count) blocks to \(arguments[2])"
    }
}
