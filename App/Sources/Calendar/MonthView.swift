import CoreData
import SwiftUI
import YafoKit

/// Startbildschirm: Monatsraster, darunter (iPad: daneben) die Tagesliste.
struct MonthView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var month = Date.now
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)
    @State private var person: Member?
    @State private var showingEditor = false

    @FetchRequest(sortDescriptors: [SortDescriptor(\.createdAt)])
    private var calendars: FetchedResults<EventCalendar>
    @FetchRequest(sortDescriptors: [])
    private var appearances: FetchedResults<CalendarAppearance>
    @FetchRequest(sortDescriptors: [SortDescriptor(\.name)])
    private var families: FetchedResults<Family>

    private var style: CalendarStyle {
        CalendarStyle(calendars: calendars, appearances: appearances, person: person)
    }

    var body: some View {
        NavigationStack {
            Group {
                if sizeClass == .regular {
                    HStack(alignment: .top, spacing: 0) {
                        monthGrid.frame(maxWidth: .infinity)
                        Divider()
                        DayListView(day: selectedDay, style: style).frame(width: 320)
                    }
                } else {
                    VStack(spacing: 0) {
                        monthGrid
                        Divider()
                        DayListView(day: selectedDay, style: style)
                            .frame(height: 200)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .sheet(isPresented: $showingEditor) {
                EventEditorView(initialDay: selectedDay)
            }
        }
    }

    private var monthGrid: some View {
        VStack(spacing: 0) {
            monthHeader
            MonthGridView(grid: MonthGrid(containing: month), selectedDay: $selectedDay, style: style)
        }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 30).onEnded { value in
                if value.translation.width < -60 { showMonth(offset: 1) }
                if value.translation.width > 60 { showMonth(offset: -1) }
            })
    }

    /// Monatsname mit Pfeilen; Wischen allein wäre für VoiceOver nicht erreichbar.
    private var monthHeader: some View {
        HStack {
            Text(month.formatted(.dateTime.month(.wide).year()))
                .font(.title2.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button("Previous Month", systemImage: "chevron.left") { showMonth(offset: -1) }
            Button("Next Month", systemImage: "chevron.right") { showMonth(offset: 1) }
        }
        .labelStyle(.iconOnly)
        .imageScale(.large)
        .buttonStyle(.borderless)
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    private func showMonth(offset: Int) {
        withAnimation(.snappy) {
            month = Calendar.current.date(byAdding: .month, value: offset, to: month) ?? month
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Today") {
                withAnimation(.snappy) {
                    month = .now
                    selectedDay = Calendar.current.startOfDay(for: .now)
                }
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            filterMenu
            Button("New Event", systemImage: "plus") { showingEditor = true }
        }
    }

    private var filterMenu: some View {
        Menu {
            Section("Person") {
                Picker("Person", selection: $person) {
                    Text("Everyone").tag(Member?.none)
                    ForEach(families) { family in
                        ForEach(model.repository.activeMembers(of: family)) { member in
                            Text("\(member.displayLabel) · \(family.name ?? "")").tag(Member?.some(member))
                        }
                    }
                }
            }
            Section("Calendars") {
                ForEach(calendars) { calendar in
                    Toggle(calendar.displayName, isOn: Binding(
                        get: { calendar.id.map { !style.hiddenCalendars.contains($0) } ?? true },
                        set: { visible in
                            model.repository.setAppearance(of: calendar, isVisible: visible)
                            model.save()
                        }
                    ))
                }
            }
        } label: {
            Label("Filter", systemImage: person == nil && style.hiddenCalendars.isEmpty
                  ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
    }
}
