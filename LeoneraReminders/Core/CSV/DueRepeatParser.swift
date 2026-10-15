import Foundation

/// Interpreta el texto de la columna "Repetir" de la exportación de Due, p. ej.
/// "Diariamente 23:00", "Todos los sábados 8:00", "7mo de cada mes a las 20:00",
/// "1er de cada 2 meses a las 9:00" o "Todos los 8 nov, 20:20".
/// También entiende variantes comunes en inglés ("Every Saturday 8:00", "1st of every month").
enum DueRepeatParser {
    enum Result: Equatable, Sendable {
        /// Sin repetición (columna vacía o "Nunca").
        case none
        case rule(RepeatRule)
        /// No se pudo interpretar el texto.
        case unrecognized
    }

    static func parse(_ text: String, dueDate: Date, calendar: Calendar = .current) -> Result {
        let normalized = normalize(text).trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty || noneWords.contains(normalized) { return .none }

        let (time, remainder) = extractTime(from: normalized)
        let tokens = tokenize(remainder)
        guard let rule = interpret(tokens, time: time, dueDate: dueDate, calendar: calendar) else {
            return .unrecognized
        }
        return .rule(rule)
    }

    // MARK: - Normalización

    /// Minúsculas y sin acentos ("Sábados" → "sabados", "años" → "anos").
    static func normalize(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.lowercased().decomposedStringWithCanonicalMapping.unicodeScalars
        where scalar.properties.generalCategory != .nonspacingMark {
            scalars.append(scalar)
        }
        return String(scalars)
    }

    /// Busca la última hora con formato H:MM (con a. m./p. m. opcional) y la quita del texto.
    static func extractTime(from text: String) -> (TimeOfDay?, String) {
        let chars = Array(text)
        var match: (start: Int, end: Int, hour: Int, minute: Int)?
        for colon in chars.indices where chars[colon] == ":" {
            var start = colon
            while start > 0, colon - start < 2, chars[start - 1].isASCII, chars[start - 1].isNumber { start -= 1 }
            let end = colon + 3
            guard start < colon, end <= chars.count,
                  chars[colon + 1].isASCII, chars[colon + 1].isNumber,
                  chars[colon + 2].isASCII, chars[colon + 2].isNumber,
                  end == chars.count || !chars[end].isNumber,
                  start == 0 || !chars[start - 1].isNumber,
                  let hour = Int(String(chars[start..<colon])),
                  let minute = Int(String(chars[(colon + 1)..<end]))
            else { continue }
            match = (start, end, hour, minute)
        }
        guard var found = match else { return (nil, text) }

        let after = String(chars[found.end...]).filter { !$0.isWhitespace && $0 != "." }
        if after.hasPrefix("pm"), found.hour < 12 { found.hour += 12 }
        if after.hasPrefix("am"), found.hour == 12 { found.hour = 0 }
        guard (0...23).contains(found.hour), (0...59).contains(found.minute) else { return (nil, text) }

        let remainder = String(chars[..<found.start]) + " " + String(chars[found.end...])
        return (TimeOfDay(hour: found.hour, minute: found.minute), remainder)
    }

    // MARK: - Tokens

    enum Unit: Sendable { case minute, hour, day, week, month, year }

    enum Token: Equatable, Sendable {
        case number(Int)
        case ordinal(Int)
        case weekday(Int)
        case weekdayGroup(Set<Int>)
        case month(Int)
        case unit(Unit)
        case adverb(RepeatRule.Frequency, interval: Int)
        case every
        case last
        /// "penúltimo" (2) o "antepenúltimo" (3): posición contada desde el final.
        case fromEnd(Int)
        case onTheHour
        case word(String)
    }

    static func tokenize(_ text: String) -> [Token] {
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;:()/-"))
        let words = text.components(separatedBy: separators)
            .map { $0.replacingOccurrences(of: ".", with: "") }
            .filter { !$0.isEmpty && !fillers.contains($0) }

        var tokens: [Token] = []
        var index = 0
        while index < words.count {
            let word = words[index]
            let next = index + 1 < words.count ? words[index + 1] : nil

            // Pares de palabras: "entre semana", "fin(es) de semana".
            if let next, units[next] == .week {
                if word == "entre" { tokens.append(.weekdayGroup(RepeatRule.workdays)); index += 2; continue }
                if word == "fin" || word == "fines" { tokens.append(.weekdayGroup(RepeatRule.weekendDays)); index += 2; continue }
            }
            tokens.append(token(for: word))
            index += 1
        }
        return tokens
    }

    static func token(for word: String) -> Token {
        if let value = Int(word) { return .number(value) }
        if let first = word.first, first.isASCII, first.isNumber {
            let digits = word.prefix { $0.isASCII && $0.isNumber }
            if let value = Int(digits) { return .ordinal(value) }
        }
        if let value = numberWords[word] { return .number(value) }
        if let value = ordinalWords[word] { return .ordinal(value) }
        if let value = weekdayNames[word] { return .weekday(value) }
        if let group = weekdayGroups[word] { return .weekdayGroup(group) }
        if let value = monthNames[word] { return .month(value) }
        if let unit = units[word] { return .unit(unit) }
        if let adverb = adverbs[word] { return .adverb(adverb.0, interval: adverb.1) }
        if everyWords.contains(word) { return .every }
        if lastWords.contains(word) { return .last }
        if let value = fromEndWords[word] { return .fromEnd(value) }
        if word == "punto" || word == "oclock" { return .onTheHour }
        return .word(word)
    }

    // MARK: - Interpretación

    static func interpret(_ tokens: [Token], time: TimeOfDay?, dueDate: Date, calendar: Calendar) -> RepeatRule? {
        let due = calendar.dateComponents([.hour, .minute, .weekday, .day, .month], from: dueDate)
        let hour = time?.hour ?? due.hour ?? 9
        let minute = time?.minute ?? due.minute ?? 0

        // Un número (u "otro") justo antes de una unidad es el intervalo: "cada 2 meses".
        var interval: (value: Int, unit: Unit)?
        var consumed = Set<Int>()
        var unitsFound: [Unit] = []
        var minuteOfHour: Int?
        for (i, token) in tokens.enumerated() {
            guard case .unit(let unit) = token else { continue }
            unitsFound.append(unit)
            if i > 0, case .number(let n) = tokens[i - 1], interval == nil, unit != .minute {
                interval = (n, unit)
                consumed.insert(i - 1)
            }
            if unit == .minute, i + 1 < tokens.count, case .number(let n) = tokens[i + 1] {
                minuteOfHour = n
                consumed.insert(i + 1)
            }
        }

        var weekdays = Set<Int>()
        var months: [Int] = []
        var ordinals: [Int] = []
        var freeNumbers: [Int] = []
        var hasLast = false
        var fromEnd: Int?
        var onTheHour = false
        var adverb: (RepeatRule.Frequency, Int)?
        for (i, token) in tokens.enumerated() {
            switch token {
            case .weekday(let day): weekdays.insert(day)
            case .weekdayGroup(let group): weekdays.formUnion(group)
            case .month(let m): months.append(m)
            case .ordinal(let n): ordinals.append(n)
            case .number(let n) where !consumed.contains(i): freeNumbers.append(n)
            case .last: hasLast = true
            case .fromEnd(let n): fromEnd = fromEnd ?? n
            case .onTheHour: onTheHour = true
            case .adverb(let frequency, let n): adverb = adverb ?? (frequency, n)
            default: break
            }
        }

        func intervalFor(_ unit: Unit) -> Int {
            guard let interval, interval.unit == unit else { return 1 }
            return max(1, interval.value)
        }
        let dayNumber = (ordinals + freeNumbers).first { (1...31).contains($0) }
        let dueWeekday = due.weekday ?? 1
        let dueDay = due.day ?? 1
        let dueMonth = due.month ?? 1

        func weekly(_ n: Int) -> RepeatRule {
            RepeatRule(frequency: .weekly, interval: n, hour: hour, minute: minute,
                       weekdays: weekdays.isEmpty ? [dueWeekday] : weekdays)
        }
        func monthly(_ n: Int) -> RepeatRule {
            // "Último domingo de cada mes", "2do martes de cada mes", "penúltimo viernes de cada mes".
            if weekdays.count == 1, let weekday = weekdays.first {
                let ordinal = fromEnd.map { -$0 } ?? (hasLast ? -1 : ordinals.first { (1...4).contains($0) })
                if let ordinal {
                    return RepeatRule(frequency: .monthly, interval: n, hour: hour, minute: minute,
                                      weekdayOrdinal: ordinal, ordinalWeekday: weekday)
                }
            }
            return RepeatRule(frequency: .monthly, interval: n, hour: hour, minute: minute,
                       dayOfMonth: dayNumber ?? (hasLast ? 31 : dueDay), lastDayOfMonth: hasLast && dayNumber == nil)
        }
        func yearly(_ n: Int) -> RepeatRule {
            RepeatRule(frequency: .yearly, interval: n, hour: hour, minute: minute,
                       dayOfMonth: dayNumber ?? dueDay, month: months.first ?? dueMonth)
        }
        func hourly(_ n: Int) -> RepeatRule {
            let m = minuteOfHour ?? (onTheHour ? 0 : (time?.minute ?? due.minute ?? 0))
            return RepeatRule(frequency: .hourly, interval: n, hour: hour, minute: min(max(m, 0), 59))
        }

        if let (frequency, n) = adverb {
            switch frequency {
            case .hourly: return hourly(n)
            case .daily: return RepeatRule(frequency: .daily, interval: n, hour: hour, minute: minute)
            case .weekly: return weekly(n)
            case .monthly: return monthly(n)
            case .yearly: return yearly(n)
            }
        }
        if !months.isEmpty { return yearly(intervalFor(.year)) }
        if unitsFound.contains(.month) { return monthly(intervalFor(.month)) }
        if !weekdays.isEmpty {
            return weekdays.count == 7 && intervalFor(.week) == 1
                ? RepeatRule(frequency: .daily, hour: hour, minute: minute)
                : weekly(intervalFor(.week))
        }
        if unitsFound.contains(.week) { return weekly(intervalFor(.week)) }
        if unitsFound.contains(.year) { return yearly(intervalFor(.year)) }
        if unitsFound.contains(.day) { return RepeatRule(frequency: .daily, interval: intervalFor(.day), hour: hour, minute: minute) }
        if unitsFound.contains(.hour) { return hourly(intervalFor(.hour)) }
        return nil
    }

    // MARK: - Vocabulario (ya normalizado: minúsculas y sin acentos)

    static let noneWords: Set<String> = ["nunca", "ninguno", "ninguna", "no", "never", "none"]

    static let fillers: Set<String> = [
        "a", "las", "la", "el", "los", "de", "del", "en", "y", "e", "al", "o",
        "at", "on", "the", "of", "and", "in",
        "p", "m", "am", "pm", "hrs", "hr", "h", "hs",
    ]

    static let everyWords: Set<String> = ["cada", "todos", "todas", "every", "each"]
    static let lastWords: Set<String> = ["ultimo", "ultima", "last"]

    static let numberWords: [String: Int] = [
        "un": 1, "uno": 1, "una": 1, "dos": 2, "tres": 3, "cuatro": 4, "cinco": 5, "seis": 6,
        "siete": 7, "ocho": 8, "nueve": 9, "diez": 10, "once": 11, "doce": 12,
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
        "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12,
        "otro": 2, "otra": 2, "other": 2,
    ]

    static let ordinalWords: [String: Int] = [
        "primer": 1, "primero": 1, "primera": 1, "segundo": 2, "segunda": 2,
        "tercer": 3, "tercero": 3, "tercera": 3, "cuarto": 4, "cuarta": 4,
        "first": 1, "second": 2, "third": 3, "fourth": 4,
    ]

    static let fromEndWords: [String: Int] = [
        "penultimo": 2, "penultima": 2, "penultimate": 2, "antepenultimo": 3, "antepenultima": 3, "antepenultimate": 3,
    ]

    static let weekdayNames: [String: Int] = [
        "domingo": 1, "domingos": 1, "lunes": 2, "martes": 3, "miercoles": 4,
        "jueves": 5, "viernes": 6, "sabado": 7, "sabados": 7,
        "sunday": 1, "sundays": 1, "sun": 1, "monday": 2, "mondays": 2, "mon": 2,
        "tuesday": 3, "tuesdays": 3, "tue": 3, "tues": 3, "wednesday": 4, "wednesdays": 4, "wed": 4,
        "thursday": 5, "thursdays": 5, "thu": 5, "thur": 5, "thurs": 5,
        "friday": 6, "fridays": 6, "fri": 6, "saturday": 7, "saturdays": 7, "sat": 7,
    ]

    static let weekdayGroups: [String: Set<Int>] = [
        "laborables": RepeatRule.workdays, "habiles": RepeatRule.workdays,
        "weekdays": RepeatRule.workdays, "weekday": RepeatRule.workdays,
        "weekends": RepeatRule.weekendDays, "weekend": RepeatRule.weekendDays,
    ]

    static let monthNames: [String: Int] = [
        "enero": 1, "ene": 1, "febrero": 2, "feb": 2, "marzo": 3, "mar": 3, "abril": 4, "abr": 4,
        "mayo": 5, "may": 5, "junio": 6, "jun": 6, "julio": 7, "jul": 7, "agosto": 8, "ago": 8,
        "septiembre": 9, "setiembre": 9, "sep": 9, "sept": 9, "set": 9, "octubre": 10, "oct": 10,
        "noviembre": 11, "nov": 11, "diciembre": 12, "dic": 12,
        "january": 1, "jan": 1, "february": 2, "march": 3, "april": 4, "apr": 4, "june": 6, "july": 7,
        "august": 8, "aug": 8, "september": 9, "october": 10, "november": 11, "december": 12, "dec": 12,
    ]

    static let units: [String: Unit] = [
        "minuto": .minute, "minutos": .minute, "min": .minute, "minute": .minute, "minutes": .minute,
        "hora": .hour, "horas": .hour, "hour": .hour, "hours": .hour,
        "dia": .day, "dias": .day, "day": .day, "days": .day,
        "semana": .week, "semanas": .week, "week": .week, "weeks": .week,
        "mes": .month, "meses": .month, "month": .month, "months": .month,
        "ano": .year, "anos": .year, "year": .year, "years": .year,
    ]

    static let adverbs: [String: (RepeatRule.Frequency, Int)] = [
        "diariamente": (.daily, 1), "diario": (.daily, 1), "daily": (.daily, 1),
        "semanalmente": (.weekly, 1), "semanal": (.weekly, 1), "weekly": (.weekly, 1),
        "quincenalmente": (.weekly, 2), "quincenal": (.weekly, 2), "biweekly": (.weekly, 2), "fortnightly": (.weekly, 2),
        "mensualmente": (.monthly, 1), "mensual": (.monthly, 1), "monthly": (.monthly, 1),
        "bimestralmente": (.monthly, 2), "bimestral": (.monthly, 2), "bimonthly": (.monthly, 2),
        "trimestralmente": (.monthly, 3), "trimestral": (.monthly, 3), "quarterly": (.monthly, 3),
        "semestralmente": (.monthly, 6), "semestral": (.monthly, 6),
        "anualmente": (.yearly, 1), "anual": (.yearly, 1), "yearly": (.yearly, 1), "annually": (.yearly, 1),
        "hourly": (.hourly, 1),
    ]
}
