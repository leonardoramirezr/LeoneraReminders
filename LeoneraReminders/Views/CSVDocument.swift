import SwiftUI
import UniformTypeIdentifiers

/// Archivo CSV ya generado, para guardarlo con `fileExporter`.
struct CSVDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.commaSeparatedText]

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
