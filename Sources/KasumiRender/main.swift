import Foundation
import KasumiMarkdown

let arguments = CommandLine.arguments
if arguments.count < 3 {
    FileHandle.standardError.write(
        Data(
            "Usage: KasumiRender INPUT.md OUTPUT.png|OUTPUT.jpg|OUTPUT.pdf [PNG_WIDTH] [--preset ID] [--profile FILE.toml] [--theme ID] [--dark] [--code-caption] [--code-radius POINTS]\n"
                .utf8))
    exit(2)
}
do {
    print(try await RenderCommand.run(arguments))
} catch {
    FileHandle.standardError.write(Data("Render failed: \(error)\n".utf8))
    exit(1)
}
