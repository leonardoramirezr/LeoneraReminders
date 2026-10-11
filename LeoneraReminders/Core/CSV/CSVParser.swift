import Foundation

/// Lector de CSV (RFC 4180): campos entre comillas, comillas escapadas ("") y saltos de línea dentro de campos.
enum CSVParser {
    struct Row: Equatable, Sendable {
        /// Número de línea (1 = primera) donde empieza la fila.
        var line: Int
        var fields: [String]
    }

    static func parse(_ text: String, delimiter: Character? = nil) -> [Row] {
        let separator = (delimiter ?? detectDelimiter(in: text)).unicodeScalars.first ?? ","
        let quote: Unicode.Scalar = "\""
        var rows: [Row] = []
        var fields: [String] = []
        var field = String.UnicodeScalarView()
        var inQuotes = false
        var line = 1
        var rowStartLine = 1
        var fieldWasQuoted = false

        var scalars = Array(text.unicodeScalars)
        if scalars.first == "\u{FEFF}" { scalars.removeFirst() }

        func endField() {
            fields.append(String(field))
            field = String.UnicodeScalarView()
            fieldWasQuoted = false
        }

        func endRow() {
            endField()
            // Ignora líneas totalmente vacías.
            if !(fields.count == 1 && fields[0].isEmpty) {
                rows.append(Row(line: rowStartLine, fields: fields))
            }
            fields = []
        }

        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            if inQuotes {
                if scalar == quote {
                    if index + 1 < scalars.count, scalars[index + 1] == quote {
                        field.append(quote)
                        index += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    if scalar == "\n" { line += 1 }
                    field.append(scalar)
                }
            } else if scalar == quote, field.isEmpty, !fieldWasQuoted {
                inQuotes = true
                fieldWasQuoted = true
            } else if scalar == separator {
                endField()
            } else if scalar == "\r" || scalar == "\n" {
                if scalar == "\r", index + 1 < scalars.count, scalars[index + 1] == "\n" { index += 1 }
                endRow()
                line += 1
                rowStartLine = line
            } else {
                field.append(scalar)
            }
            index += 1
        }
        if !field.isEmpty || !fields.isEmpty || fieldWasQuoted {
            endRow()
        }
        return rows
    }

    /// Elige entre coma, punto y coma o tabulador según la primera línea (fuera de comillas).
    static func detectDelimiter(in text: String) -> Character {
        var commas = 0, semicolons = 0, tabs = 0
        var inQuotes = false
        for character in text {
            if character == "\"" { inQuotes.toggle(); continue }
            guard !inQuotes else { continue }
            if character.isNewline { break }
            switch character {
            case ",": commas += 1
            case ";": semicolons += 1
            case "\t": tabs += 1
            default: break
            }
        }
        if semicolons > commas, semicolons >= tabs { return ";" }
        if tabs > commas, tabs > semicolons { return "\t" }
        return ","
    }
}
