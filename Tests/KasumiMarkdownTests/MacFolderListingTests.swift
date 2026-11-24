import Foundation
import Testing

@Suite struct MacFolderListingTests {
    @Test func listsSupportedVisibleFilesInNameOrder() throws {
        let manager = FileManager.default
        let folder = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: folder) }

        for name in ["Part 10.md", "Part 2.MD", "Alpha.markdown", "notes.txt", "ignore.pdf", ".hidden.md"] {
            try Data().write(to: folder.appendingPathComponent(name))
        }
        try manager.createDirectory(at: folder.appendingPathComponent("folder.md"), withIntermediateDirectories: false)

        #expect(
            MacFolderListing.files(in: folder).map(\.lastPathComponent) == [
                "Alpha.markdown", "notes.txt", "Part 2.MD", "Part 10.md"
            ])
        #expect(MacFolderListing.files(in: folder.appendingPathComponent("missing")).isEmpty)
    }
}
