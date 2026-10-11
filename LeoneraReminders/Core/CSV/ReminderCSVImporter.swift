import Foundation

/// Convierte un CSV con columnas "Recordatorio", "Fecha límite" y "Repetir" (exportación de Due) en recordatorios.
enum ReminderCSVImporter {
    struct Issue: Hashable, Sendable, Identifiable {
        enum Kind: Hashable, Sendable {
            /// La fila no se importó.
            case skipped
            /// Se importó, pero sin repetición porque no se entendió el texto.
            case repeatNotRecognized
        }

        var line: Int
        var kind: Kind
        var title: String
        var message: String

        var id: String { "\(line)-\(message)" }
    }

    struct Entry: Hashable, Sendable, Identifiable {
        var line: Int
        var reminder: Reminder
        /// Texto original de la columna "Repetir".
        var repeatText: String

        var id: UUID { reminder.id }
    }

    struct Result: Sendable {
        var entries: [Entry]
        var issues: [Issue]

        var reminders: [Reminder] { entries.map(\.reminder) }
    }

    enum ImportError: Error, Equatable, LocalizedError {
        case empty
        case missingColumns

        var errorDescription: String? {
            switch self {
            case .empty: "El archivo está vacío."
            case .missingColumns: "No se encontraron las columnas de recordatorio y fecha límite."
            }
        }
    }

    static func parse(_ text: String, now: Date = Date(), calendar: Calendar = .current) throws -> Result {
        let rows = CSVParser.parse(text)
        guard let first = rows.first else { throw ImportError.empty }

        let header = Columns(header: first.fields)
        let columns = header ?? Columns(title: 0, date: 1, repeat: first.fields.count > 2 ? 2 : nil)
        let dataRows = header == nil ? rows : Array(rows.dropFirst())
        guard columns.title != columns.date else { throw ImportError.missingColumns }

        var entries: [Entry] = []
        var issues: [Issue] = []
        for row in dataRows {
            let title = row.field(columns.title).trimmingCharacters(in: .whitespacesAndNewlines)
            let dateText = row.field(columns.date).trimmingCharacters(in: .whitespacesAndNewlines)
            let repeatText = columns.repeat.map { row.field($0) }?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            guard !title.isEmpty else {
                if !dateText.isEmpty || !repeatText.isEmpty {
                    issues.append(Issue(line: row.line, kind: .skipped, title: "", message: "Fila sin título"))
                }
                continue
            }
            guard let dueDate = parseDate(dateText, calendar: calendar) else {
                let message = dateText.isEmpty ? "Sin fecha límite" : "Fecha no reconocida: \(dateText)"
                issues.append(Issue(line: row.line, kind: .skipped, title: title, message: message))
                continue
            }

            var rule: RepeatRule?
            switch DueRepeatParser.parse(repeatText, dueDate: dueDate, calendar: calendar) {
            case .none:
                rule = nil
            case .rule(let parsed):
                rule = parsed
            case .unrecognized:
                issues.append(Issue(line: row.line, kind: .repeatNotRecognized, title: title,
                                    message: "Repetición no reconocida: \(repeatText)"))
            }
            let reminder = Reminder(title: title, dueDate: dueDate, repeatRule: rule, createdAt: now)
            entries.append(Entry(line: row.line, reminder: reminder, repeatText: repeatText))
        }
        return Result(entries: entries, issues: issues)
    }

    /// Lee el archivo como texto: UTF-8 (con o sin BOM), UTF-16 con BOM o, en último caso, Windows-1252.
    static func decodeText(_ data: Data) -> String? {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            return String(data: data, encoding: .utf16)
        }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252)
    }

    // MARK: - Columnas

    struct Columns: Equatable {
        var title: Int
        var date: Int
        var `repeat`: Int?

        init(title: Int, date: Int, repeat: Int?) {
            self.title = title
            self.date = date
            self.repeat = `repeat`
        }

        /// Reconoce el encabezado (en español o inglés); `nil` si la primera fila no parece encabezado.
        init?(header: [String]) {
            let names = header.map { DueRepeatParser.normalize($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            func find(_ keywords: [String], excluding: Set<Int> = []) -> Int? {
                names.indices.first { index in
                    !excluding.contains(index) && keywords.contains { names[index].contains($0) }
                }
            }
            guard let date = find(["fecha", "due", "date", "vence", "limite", "cuando", "when"]),
                  let title = find(["recordatorio", "reminder", "titulo", "title", "nombre", "name", "tarea", "task"],
                                   excluding: [date])
            else { return nil }
            self.title = title
            self.date = date
            self.repeat = find(["repet", "repeat", "recurren", "frecuencia"], excluding: [title, date])
        }
    }

    // MARK: - Fechas

    /// Acepta ISO 8601 (como exporta Due: "2026-10-11T03:00:00Z") y algunos formatos locales comunes.
    static func parseDate(_ text: String, calendar: Calendar) -> Date? {
        guard !text.isEmpty else { return nil }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: text) { return date }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: text) { return date }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        for format in localFormats {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }

    private static let localFormats = [
        "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd",
        "dd/MM/yyyy HH:mm", "d/M/yyyy H:mm", "dd/MM/yyyy", "d/M/yyyy",
    ]

    // MARK: - Mezcla con los existentes

    /// Un importado es duplicado si ya hay uno con el mismo título (sin distinguir mayúsculas ni espacios extra)
    /// y la misma fecha (al minuto) o, si se repite, la misma regla de repetición: así reimportar el mismo
    /// archivo no duplica los repetitivos que ya avanzaron a otra fecha.
    private struct DuplicateKeys {
        struct ByDate: Hashable { let title: String; let minute: Int }
        struct ByRule: Hashable { let title: String; let rule: RepeatRule }

        private var dates = Set<ByDate>()
        private var rules = Set<ByRule>()

        /// Devuelve `false` si el recordatorio ya estaba.
        mutating func insert(_ reminder: Reminder) -> Bool {
            let title = reminder.title.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
            let date = ByDate(title: title, minute: Int((reminder.dueDate.timeIntervalSince1970 / 60).rounded(.down)))
            let rule = reminder.repeatRule.map { ByRule(title: title, rule: $0) }
            let isNew = !dates.contains(date) && !(rule.map(rules.contains) ?? false)
            dates.insert(date)
            if let rule { rules.insert(rule) }
            return isNew
        }
    }

    /// Prepara los recordatorios a importar: quita duplicados (contra los existentes y dentro del archivo)
    /// y, si se pide, mueve los repetitivos vencidos a su siguiente fecha.
    static func prepare(
        _ imported: [Reminder],
        existing: [Reminder],
        skipDuplicates: Bool,
        advancePastDueRepeating: Bool,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> (reminders: [Reminder], duplicates: Int) {
        var keys = DuplicateKeys()
        for reminder in existing { _ = keys.insert(reminder) }
        var result: [Reminder] = []
        var duplicates = 0
        for var reminder in imported {
            if skipDuplicates, !keys.insert(reminder) {
                duplicates += 1
                continue
            }
            if advancePastDueRepeating {
                reminder.advancePastDueRepetition(now: now, calendar: calendar)
            }
            result.append(reminder)
        }
        return (result, duplicates)
    }
}

private extension CSVParser.Row {
    func field(_ index: Int) -> String {
        index < fields.count ? fields[index] : ""
    }
}
