import SwiftUI

/// 달력으로 보는 코칭 — 날마다 몇 건 했는지. 날짜를 누르면 그날 기록이 아래에 나온다.
struct CalendarView: View {
    let sessions: [CoachingSession]
    /// 기록을 고르면 목록에서 그 기록을 연다.
    let onSelect: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var month = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())

    private let calendar = Calendar.current

    /// 날짜(그날 0시) → 그날 코칭들
    private var sessionsByDay: [Date: [CoachingSession]] {
        Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.startDate) }
    }

    var body: some View {
        let byDay = sessionsByDay
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 16) {
                        monthHeader(byDay)
                        weekdayHeader
                        dayGrid(byDay)
                    }
                    .padding(.vertical, 8)
                }
                daySection(byDay[selectedDay] ?? [])
            }
            .navigationTitle("달력")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료", systemImage: "checkmark") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 640)
        #endif
    }

    // MARK: Month

    private func monthHeader(_ byDay: [Date: [CoachingSession]]) -> some View {
        let inMonth = byDay.filter { calendar.isDate($0.key, equalTo: month, toGranularity: .month) }.values.flatMap { $0 }
        let minutes = inMonth.reduce(0) { $0 + $1.logEntry.recordedMinutes }
        return HStack {
            Button {
                moveMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("이전 달"))

            Spacer()
            VStack(spacing: 2) {
                Text(month.formatted(.dateTime.year().month(.wide)))
                    .font(.headline)
                Text("\(inMonth.count)건 · \(KACDuration.hoursMinutes(minutes))")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()

            Button {
                moveMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("다음 달"))
        }
    }

    private var weekdayHeader: some View {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        let ordered = Array(symbols[first...] + symbols[..<first])
        return HStack(spacing: 0) {
            ForEach(ordered.indices, id: \.self) { index in
                Text(ordered[index])
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    private func dayGrid(_ byDay: [Date: [CoachingSession]]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 6) {
            ForEach(Array(monthDays.enumerated()), id: \.offset) { _, day in
                if let day {
                    dayCell(day, count: byDay[day]?.count ?? 0)
                } else {
                    Color.clear.frame(height: 1)
                }
            }
        }
    }

    private func dayCell(_ day: Date, count: Int) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDay)
        let isToday = calendar.isDateInToday(day)
        return Button {
            selectedDay = day
        } label: {
            VStack(spacing: 4) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.body.weight(isToday ? .bold : .regular))
                    .foregroundStyle(isSelected ? Color.white : (isToday ? Color.accentColor : Color.primary))
                    .frame(width: 34, height: 34)
                    .background(isSelected ? Color.accentColor : Color.clear, in: Circle())
                Text(count > 0 ? "\(count)건" : " ")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(day.formatted(.dateTime.month().day().weekday())))
        .accessibilityValue(count > 0 ? Text("코칭 \(count)건") : Text("코칭 없음"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Day

    private func daySection(_ daySessions: [CoachingSession]) -> some View {
        Section {
            if daySessions.isEmpty {
                Text("이날은 코칭 기록이 없어요.")
                    .foregroundStyle(.secondary)
            }
            ForEach(daySessions.sorted { $0.startDate < $1.startDate }) { session in
                Button {
                    onSelect(session.uuid)
                    dismiss()
                } label: {
                    SessionRow(session: session, issues: [], progress: nil)
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text(selectedDay.formatted(.dateTime.month().day().weekday(.wide)))
        }
    }

    // MARK: Helpers

    /// 이번 달 칸들. 첫 주 앞의 빈 칸은 nil.
    private var monthDays: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let leading = (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7
        let days = range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: month) }
        return Array(repeating: nil, count: leading) + days
    }

    private func moveMonth(by value: Int) {
        guard let next = calendar.date(byAdding: .month, value: value, to: month) else { return }
        month = next
        // 고른 날도 그 달로 — 그 달 오늘 날짜가 있으면 오늘, 아니면 1일.
        selectedDay = calendar.isDate(Date(), equalTo: next, toGranularity: .month)
            ? calendar.startOfDay(for: Date())
            : next
    }
}
