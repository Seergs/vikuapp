import SwiftUI
import VikuDesignSystem
import VikunjaCore

/// Lets the user create or edit one `TaskReminder` — a specific date/time, or
/// a composable offset (quantity + unit + before/after) from the task's due
/// date (Vikunja also supports anchoring to a start/end date, but this app
/// has no UI for those fields yet, so the relative mode only offers the due
/// date). Driven entirely by closures, so it lives in `VikuUI` rather than
/// `Features/Tasks`, mirroring `DueDatePickerSheet`/`LabelPickerSheet`.
public struct ReminderPickerSheet: View {
    private enum Mode: Hashable {
        case specificDate
        case relative
    }

    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode
    @State private var date: Date
    @State private var quantity: Int
    @State private var unit: ReminderOffset.Unit
    @State private var direction: ReminderOffset.Direction
    /// Starts at `.medium`; switching into relative mode (more controls than
    /// fit at that detent — quantity, unit, direction, the "Relative to" row,
    /// and the preview footer) expands it to `.large`. Never auto-shrinks
    /// back, so a user who's dragged it open themselves doesn't get
    /// overridden by switching modes.
    @State private var selectedDetent: PresentationDetent = .medium
    private let dueDate: Date?
    private let isEditing: Bool
    private let onSave: (TaskReminder) -> Void
    private let onDelete: (() -> Void)?

    /// - Parameters:
    ///   - initialReminder: `nil` when creating a new reminder; the reminder
    ///     being edited otherwise.
    ///   - dueDate: The task's current due date, if any. `nil` hides the
    ///     "Relative" mode entirely — a relative reminder with no due date to
    ///     anchor to would never fire.
    ///   - onDelete: `nil` when creating a new reminder; shows a destructive
    ///     "Remove Reminder" action when editing an existing one.
    public init(
        initialReminder: TaskReminder?,
        dueDate: Date?,
        onSave: @escaping (TaskReminder) -> Void,
        onDelete: (() -> Void)? = nil,
    ) {
        self.dueDate = dueDate
        self.isEditing = initialReminder != nil
        self.onSave = onSave
        self.onDelete = onDelete
        if let initialReminder, initialReminder.relativeTo == .dueDate, dueDate != nil {
            let offset = ReminderOffset.decompose(seconds: initialReminder.relativePeriod)
            _mode = State(initialValue: .relative)
            _quantity = State(initialValue: offset.quantity)
            _unit = State(initialValue: offset.unit)
            _direction = State(initialValue: offset.direction)
            _date = State(initialValue: initialReminder.reminder)
            _selectedDetent = State(initialValue: .large)
        } else {
            _mode = State(initialValue: .specificDate)
            _quantity = State(initialValue: 1)
            _unit = State(initialValue: .days)
            // "Before" an already-overdue due date can only ever resolve to
            // the past, no matter the quantity/unit — default to "After" in
            // that case so a freshly-opened relative reminder on an overdue
            // task at least starts from the sensible direction, even though
            // reaching the future may still take widening the quantity.
            _direction = State(initialValue: (dueDate ?? Date()) < Date() ? .after : .before)
            // Not `dueDate ?? Date()`: the due date is routinely in the past
            // (an overdue task), and `Date()` itself reads as "already
            // passed" the instant this view first renders. Default instead
            // to a predictable near-future time a new reminder would
            // actually want.
            _date = State(initialValue: initialReminder?.reminder ?? Self.defaultSpecificDate())
        }
    }

    /// Tomorrow at 9 AM — `init`'s default for a brand-new specific-date
    /// reminder (see its doc comment for why `dueDate`/`Date()` aren't used).
    private static func defaultSpecificDate() -> Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    public var body: some View {
        NavigationStack {
            Form {
                if dueDate != nil {
                    Section {
                        Picker(String(localized: "Reminder type", bundle: .module), selection: $mode) {
                            Text("Specific Date", bundle: .module).tag(Mode.specificDate)
                            Text("Relative", bundle: .module).tag(Mode.relative)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                }

                Section(footer: previewFooter) {
                    switch mode {
                    case .specificDate:
                        DatePicker(String(localized: "Reminder", bundle: .module), selection: $date)
                    case .relative:
                        relativeFields
                    }
                }

                if isEditing, let onDelete {
                    Section {
                        Button(String(localized: "Remove Reminder", bundle: .module), role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(Text("Reminder", bundle: .module))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", bundle: .module)) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save", bundle: .module)) { save() }
                        .fontWeight(.semibold)
                        .disabled(isPast)
                }
            }
        }
        .onChange(of: mode) { _, newMode in
            if newMode == .relative {
                selectedDetent = .large
            }
        }
        .presentationDetents([.medium, .large], selection: $selectedDetent)
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var relativeFields: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: VikuSpacing.xs) {
                ForEach(QuickReminderPreset.allCases, id: \.self) { preset in
                    PresetPill(
                        label: preset.localizedLabel,
                        isSelected: relativeOffset == preset.offset,
                    ) {
                        quantity = preset.offset.quantity
                        unit = preset.offset.unit
                        direction = preset.offset.direction
                    }
                }
            }
            .padding(.vertical, VikuSpacing.xxs)
        }

        HStack {
            Text("Quantity", bundle: .module)
            Spacer()
            QuantityStepper(value: $quantity, range: 0 ... 99)
        }

        Picker(String(localized: "Unit", bundle: .module), selection: $unit) {
            ForEach(ReminderOffset.Unit.allCases, id: \.self) { unit in
                Text(verbatim: unit.localizedLabel).tag(unit)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()

        Picker(String(localized: "Direction", bundle: .module), selection: $direction) {
            ForEach(ReminderOffset.Direction.allCases, id: \.self) { direction in
                Text(verbatim: direction.localizedLabel).tag(direction)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()

        HStack {
            Text("Relative to", bundle: .module)
            Spacer()
            Text("Due Date", bundle: .module)
                .foregroundStyle(VikuColor.textSecondary)
        }
    }

    /// The offset `mode == .relative` currently describes, from the
    /// quantity/unit/direction controls.
    private var relativeOffset: ReminderOffset {
        ReminderOffset(quantity: quantity, unit: unit, direction: direction)
    }

    /// The reminder time the current form state resolves to — `date` as-is
    /// in specific-date mode, or `dueDate` shifted by `relativeOffset` in
    /// relative mode (falling back to `date` if there's somehow no due date,
    /// which `body` never actually allows the user to reach).
    private var computedReminderDate: Date {
        switch mode {
        case .specificDate: date
        case .relative: dueDate.map { $0.addingTimeInterval(TimeInterval(relativeOffset.seconds)) } ?? date
        }
    }

    private var isPast: Bool {
        computedReminderDate < Date()
    }

    /// The content of the fields section's footer — plain text below the
    /// grouped box (not another card row), matching every other `Form`
    /// section's footer styling.
    private var previewFooter: some View {
        HStack(alignment: .top, spacing: VikuSpacing.sm) {
            Image(systemName: isPast ? "bell" : "bell.fill")
                .foregroundStyle(isPast ? VikuColor.Semantic.dangerText : VikuColor.brandPrimary)
            VStack(alignment: .leading, spacing: VikuSpacing.xxs) {
                if isPast {
                    Text(verbatim: String(
                        localized: "That time has already passed: \(pastDateLabel)",
                        bundle: .module,
                    ))
                    .foregroundStyle(VikuColor.Semantic.dangerText)
                    if mode == .relative {
                        Text("It will move if you change the due date.", bundle: .module)
                    }
                } else {
                    Text(verbatim: String(localized: "Will ring \(scheduledPhrase)", bundle: .module))
                }
            }
        }
        .padding(.top, VikuSpacing.xxs)
    }

    /// A relative day word (or weekday, or date) plus the time, e.g.
    /// "tomorrow at 9:00 AM" — only ever called for a future
    /// `computedReminderDate` (`previewFooter` routes a past one to
    /// `pastDateLabel` instead), so there's no "yesterday"/negative-days case
    /// to handle here.
    private var scheduledPhrase: String {
        let resolved = computedReminderDate
        let time = resolved.formatted(date: .omitted, time: .shortened)
        let calendar = Calendar.current
        if calendar.isDateInToday(resolved) {
            return String(localized: "today at \(time)", bundle: .module)
        }
        if calendar.isDateInTomorrow(resolved) {
            return String(localized: "tomorrow at \(time)", bundle: .module)
        }
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: Date()),
            to: calendar.startOfDay(for: resolved),
        ).day ?? 0
        if days <= 6 {
            let weekday = resolved.formatted(.dateTime.weekday(.wide))
            return String(localized: "\(weekday) at \(time)", bundle: .module)
        }
        let dateText = resolved.formatted(date: .abbreviated, time: .omitted)
        return String(localized: "\(dateText) at \(time)", bundle: .module)
    }

    /// The full weekday + day + month (+ year, only when it differs from the
    /// current one) + time, e.g. "Thursday, October 8, 9:00 AM" — unlike
    /// `scheduledPhrase`'s relative day words, a *past* reminder needs the
    /// actual date spelled out, not "yesterday", since it could be anywhere
    /// in the past.
    private var pastDateLabel: String {
        let resolved = computedReminderDate
        let calendar = Calendar.current
        let time = resolved.formatted(date: .omitted, time: .shortened)
        let sameYear = calendar.component(.year, from: resolved) == calendar.component(.year, from: Date())
        let dayMonth = sameYear
            ? resolved.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
            : resolved.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).year())
        return String(localized: "\(dayMonth), \(time)", bundle: .module)
    }

    private func save() {
        switch mode {
        case .specificDate:
            onSave(TaskReminder(reminder: date))
        case .relative:
            guard let dueDate else { return }
            let offset = relativeOffset
            onSave(TaskReminder(
                reminder: dueDate.addingTimeInterval(TimeInterval(offset.seconds)),
                relativePeriod: offset.seconds,
                relativeTo: .dueDate,
            ))
        }
        dismiss()
    }
}

/// A `-`/value/`+` pill, the current value shown between the two buttons —
/// unlike SwiftUI's own `Stepper`, which never displays the value itself and
/// relies on a separate label the caller has to keep in sync. iOS has no
/// built-in control shaped like this; this is a small hand-rolled one.
private struct QuantityStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack(spacing: 0) {
            stepButton(systemImage: "minus", disabled: value <= range.lowerBound) {
                value = max(range.lowerBound, value - 1)
            }
            Text(verbatim: "\(value)")
                .font(.system(.body, design: .rounded))
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(Color.primary)
                .frame(minWidth: 28)
            stepButton(systemImage: "plus", disabled: value >= range.upperBound) {
                value = min(range.upperBound, value + 1)
            }
        }
        .foregroundStyle(VikuColor.textSecondary)
        .padding(.horizontal, VikuSpacing.xs)
        .padding(.vertical, VikuSpacing.xxs)
        .background(VikuColor.Surface.field, in: Capsule())
    }

    private func stepButton(systemImage: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
    }
}

/// The relative mode's quick-pick shortcuts — tapping one just fills in
/// `quantity`/`unit`/`direction` (it doesn't save by itself), so the preview
/// footer and Save button stay the single source of truth either way,
/// whether a user taps a preset or dials in the composer fields directly.
private enum QuickReminderPreset: CaseIterable {
    case onTime
    case fifteenMinutes
    case thirtyMinutes
    case oneHour
    case oneDay
    case oneWeek

    var offset: ReminderOffset {
        switch self {
        case .onTime: ReminderOffset(quantity: 0, unit: .minutes, direction: .before)
        case .fifteenMinutes: ReminderOffset(quantity: 15, unit: .minutes, direction: .before)
        case .thirtyMinutes: ReminderOffset(quantity: 30, unit: .minutes, direction: .before)
        case .oneHour: ReminderOffset(quantity: 1, unit: .hours, direction: .before)
        case .oneDay: ReminderOffset(quantity: 1, unit: .days, direction: .before)
        case .oneWeek: ReminderOffset(quantity: 1, unit: .weeks, direction: .before)
        }
    }

    var localizedLabel: String {
        switch self {
        case .onTime: String(localized: "On time", bundle: .module)
        case .fifteenMinutes: String(localized: "15 min before", bundle: .module)
        case .thirtyMinutes: String(localized: "30 min before", bundle: .module)
        case .oneHour: String(localized: "1 hour before", bundle: .module)
        case .oneDay: String(localized: "1 day before", bundle: .module)
        case .oneWeek: String(localized: "1 week before", bundle: .module)
        }
    }
}

/// A selectable capsule chip — filled + bold when `isSelected`, outlined
/// otherwise. Deliberately neutral (no brand tint), matching `QuantityStepper`.
private struct PresetPill: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? Color.primary : VikuColor.textTertiary)
                .padding(.horizontal, VikuSpacing.sm + VikuSpacing.xs)
                .padding(.vertical, VikuSpacing.xs + VikuSpacing.xxs)
                .background(Capsule().fill(isSelected ? VikuColor.Surface.field : Color.clear))
                .overlay(Capsule().strokeBorder(VikuColor.textTertiary.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
