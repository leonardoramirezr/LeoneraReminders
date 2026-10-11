import SwiftUI

/// Editor de la regla de repetición: nunca, cada N horas, días, semanas (con días), meses (día o último día) o años.
struct RepeatRuleEditorView: View {
    @Binding var rule: RepeatRule?
    /// Fecha límite actual: de ella salen los valores iniciales y la vista previa.
    let dueDate: Date

    private enum Choice: Hashable {
        case never
        case frequency(RepeatRule.Frequency)
    }

    var body: some View {
        Form {
            Section {
                Picker("Repetir", selection: choice) {
                    Text("Nunca").tag(Choice.never)
                    ForEach(RepeatRule.Frequency.allCases) { frequency in
                        Text(frequency.label).tag(Choice.frequency(frequency))
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            if let current = rule {
                Section {
                    Stepper(value: field(\.interval), in: 1...99) {
                        Text("Cada \(current.interval) \(current.unitName(for: current.interval))")
                    }
                    details(for: current)
                } footer: {
                    Text(current.summary())
                }

                Section("Próximas fechas") {
                    let upcoming = current.occurrences(after: dueDate, count: 4)
                    LabeledContent("Ahora", value: DateText.relative(dueDate))
                    ForEach(upcoming, id: \.self) { date in
                        Text(DateText.full(date))
                    }
                }
            }
        }
        .navigationTitle("Repetir")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func details(for current: RepeatRule) -> some View {
        switch current.frequency {
        case .hourly:
            Picker("Minuto", selection: field(\.minute)) {
                ForEach(0..<60, id: \.self) { minute in
                    Text(String(format: ":%02d", minute)).tag(minute)
                }
            }
        case .daily:
            timePicker
        case .weekly:
            WeekdayPicker(selection: field(\.weekdays))
                .padding(.vertical, 4)
            timePicker
        case .monthly:
            Picker("Día del mes", selection: monthDay) {
                ForEach(1...31, id: \.self) { day in
                    Text("Día \(day)").tag(day)
                }
                Text("Último día").tag(0)
            }
            timePicker
        case .yearly:
            Picker("Mes", selection: field(\.month)) {
                ForEach(1...12, id: \.self) { month in
                    Text(SpanishNames.months[month].capitalized).tag(month)
                }
            }
            Picker("Día", selection: field(\.dayOfMonth)) {
                ForEach(1...RepeatRule.daysIn(year: 2028, month: current.month, calendar: .current), id: \.self) { day in
                    Text("\(day)").tag(day)
                }
            }
            timePicker
        }
    }

    private var timePicker: some View {
        DatePicker(
            "Hora",
            selection: Binding(
                get: { (rule?.time ?? TimeOfDay(of: dueDate)).applied(to: dueDate) },
                set: { rule?.time = TimeOfDay(of: $0) }
            ),
            displayedComponents: .hourAndMinute
        )
    }

    // MARK: - Bindings

    private var choice: Binding<Choice> {
        Binding(
            get: { rule.map { .frequency($0.frequency) } ?? .never },
            set: { newValue in
                switch newValue {
                case .never:
                    rule = nil
                case .frequency(let frequency):
                    if var existing = rule {
                        existing.frequency = frequency
                        rule = existing
                    } else {
                        rule = RepeatRule.matching(dueDate, frequency: frequency)
                    }
                }
            }
        )
    }

    /// Día del mes, con 0 = último día.
    private var monthDay: Binding<Int> {
        Binding(
            get: { (rule?.lastDayOfMonth ?? false) ? 0 : (rule?.dayOfMonth ?? 1) },
            set: { day in
                rule?.lastDayOfMonth = day == 0
                rule?.dayOfMonth = day == 0 ? 31 : day
            }
        )
    }

    private func field<Value>(_ keyPath: WritableKeyPath<RepeatRule, Value>) -> Binding<Value> {
        Binding(
            get: { (rule ?? RepeatRule.matching(dueDate, frequency: .daily))[keyPath: keyPath] },
            set: { rule?[keyPath: keyPath] = $0 }
        )
    }
}

/// Selector de días de la semana (al menos uno).
struct WeekdayPicker: View {
    @Binding var selection: Set<Int>

    var body: some View {
        HStack(spacing: 4) {
            ForEach(SpanishNames.orderedWeekdays(calendar: .current), id: \.self) { day in
                let isOn = selection.contains(day)
                Button {
                    toggle(day)
                } label: {
                    Text(SpanishNames.weekdayInitials[day])
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 38, height: 38)
                        .background(isOn ? Color.brand : Color.secondary.opacity(0.15), in: Circle())
                        .foregroundStyle(isOn ? Color.white : Color.primary)
                }
                .buttonStyle(.borderless)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(SpanishNames.weekdays[day])
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }

    private func toggle(_ day: Int) {
        if selection.contains(day) {
            if selection.count > 1 { selection.remove(day) }
        } else {
            selection.insert(day)
        }
    }
}
