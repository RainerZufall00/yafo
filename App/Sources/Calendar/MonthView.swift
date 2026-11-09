import CoreData
import SwiftUI
import YafoKit

/// Startbildschirm: Monatsraster über die ganze Höhe. iPhone: Tippen öffnet den Tag,
/// iPad: Tagesliste daneben.
struct MonthView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// Erster Tag des angezeigten Monats; folgt dem Blättern im Pager.
    @State private var month = MonthView.startOfMonth(.now)
    @State private var scrolledMonth: Date? = MonthView.startOfMonth(.now)
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)
    @State private var person: Member?
    @State private var showingEditor = false
    @State private var showingScreenshotPicker = false
    @State private var showingYear = false
    @State private var openedDay: Date?

    @FetchRequest(sortDescriptors: [SortDescriptor(\.createdAt)])
    private var calendars: FetchedResults<EventCalendar>
    @FetchRequest(sortDescriptors: [])
    private var appearances: FetchedResults<CalendarAppearance>
    @FetchRequest(sortDescriptors: [SortDescriptor(\.name)])
    private var families: FetchedResults<Family>
    /// Nur damit Abo-Änderungen (Feiertage) die Ansicht neu zeichnen.
    @FetchRequest(sortDescriptors: [])
    private var subscriptions: FetchedResults<CalendarSubscription>

    private var style: CalendarStyle {
        let _ = subscriptions.count
        return CalendarStyle(calendars: calendars, appearances: appearances, person: person)
    }

    var body: some View {
        NavigationStack {
            Group {
                if showingYear {
                    VStack(spacing: 0) {
                        yearHeader
                        YearView(year: month, style: style) { day in
                            month = Self.startOfMonth(day)
                            scrolledMonth = month
                            selectedDay = day
                            withAnimation(.snappy) { showingYear = false }
                        }
                    }
                } else if sizeClass == .regular {
                    HStack(alignment: .top, spacing: 0) {
                        monthGrid.frame(maxWidth: .infinity)
                        Divider()
                        DayListView(day: selectedDay, style: style).frame(width: 320)
                    }
                } else {
                    monthGrid
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .screenshotImport(isPresented: $showingScreenshotPicker)
            .sheet(isPresented: $showingEditor) {
                EventEditorView(initialDay: selectedDay)
            }
            .navigationDestination(item: $openedDay) { day in
                DayPage(day: day, style: style)
            }
        }
    }

    private var monthGrid: some View {
        VStack(spacing: 0) {
            monthHeader
            monthPager
        }
    }

    /// Monate als Seiten: Beim Wischen laufen alter und neuer Monat mit dem Finger mit.
    /// Zehn Jahre in jede Richtung; gebaut werden nur die sichtbaren Seiten.
    private var monthPager: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(Self.pagedMonths, id: \.self) { page in
                    MonthGridView(grid: MonthGrid(containing: page), selectedDay: $selectedDay, style: style,
                                  onOpenDay: sizeClass == .regular ? nil : { openedDay = $0 })
                        .containerRelativeFrame([.horizontal, .vertical])
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
        .scrollIndicators(.hidden)
        .scrollPosition(id: $scrolledMonth)
        .onChange(of: scrolledMonth) {
            if let scrolledMonth, scrolledMonth != month { month = scrolledMonth }
        }
    }

    private static let pagedMonths: [Date] = {
        let current = startOfMonth(.now)
        return (-120...120).compactMap { Calendar.current.date(byAdding: .month, value: $0, to: current) }
    }()

    static func startOfMonth(_ date: Date) -> Date {
        Calendar.current.dateInterval(of: .month, for: date)?.start ?? date
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

    private var yearHeader: some View {
        HStack {
            Text(month.formatted(.dateTime.year()))
                .font(.title2.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button("Previous Year", systemImage: "chevron.left") { showYear(offset: -1) }
            Button("Next Year", systemImage: "chevron.right") { showYear(offset: 1) }
        }
        .labelStyle(.iconOnly)
        .imageScale(.large)
        .buttonStyle(.borderless)
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    private func showYear(offset: Int) {
        withAnimation(.snappy) {
            month = Calendar.current.date(byAdding: .year, value: offset, to: month) ?? month
            scrolledMonth = month
        }
    }

    private func showMonth(offset: Int) {
        guard let target = Calendar.current.date(byAdding: .month, value: offset, to: month) else { return }
        withAnimation(.snappy) { scrolledMonth = target }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Today") {
                withAnimation(.snappy) {
                    scrolledMonth = Self.startOfMonth(.now)
                    selectedDay = Calendar.current.startOfDay(for: .now)
                }
                if showingYear { month = Self.startOfMonth(.now) }
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button(showingYear ? "Month" : "Year",
                   systemImage: showingYear ? "calendar" : "square.grid.3x3") {
                withAnimation(.snappy) { showingYear.toggle() }
            }
            filterMenu
            // Tippen: neuer Termin; lange drücken: auch „Aus Screenshot“.
            Menu {
                Button("New Event", systemImage: "square.and.pencil") { showingEditor = true }
                Button("From Screenshot", systemImage: "text.viewfinder") { showingScreenshotPicker = true }
            } label: {
                Label("New Event", systemImage: "plus")
            } primaryAction: {
                showingEditor = true
            }
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
