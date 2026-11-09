import CoreData
import PhotosUI
import SwiftUI
import YafoKit

/// Startbildschirm: Woche, Monat oder Jahr über die ganze Höhe. iPhone: Tippen öffnet den Tag,
/// iPad: Tagesliste daneben.
struct MonthView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// Erster Tag des angezeigten Monats; folgt dem Blättern im Pager.
    @State private var month = MonthView.startOfMonth(.now)
    @State private var scrolledMonth: Date? = MonthView.startOfMonth(.now)
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)
    @State private var person: Member?
    /// Erster Tag der angezeigten Woche; folgt dem Blättern im Wochen-Pager.
    @State private var week = MonthView.startOfWeek(.now)
    @State private var scrolledWeek: Date? = MonthView.startOfWeek(.now)
    @State private var showingEditor = false
    @State private var choosingScreenshot = false
    @State private var screenshotItem: PhotosPickerItem?
    @State private var screenshot: PickedImage?
    @State private var showingFamily = false
    @AppStorage("calendarMode") private var mode: CalendarMode = .month
    @State private var openedDay: Date?
    @AppStorage(InterfaceStyle.storageKey) private var interfaceStyle = InterfaceStyle.tabs

    /// Im Wisch-Modus blättern Monate nach oben und unten, seitlich geht es zu Todos und Einkauf.
    private var isVertical: Bool { interfaceStyle == .swipe }

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
                if mode == .year {
                    VStack(spacing: 0) {
                        yearHeader
                        YearView(year: month, style: style) { day in
                            show(day)
                            withAnimation(.snappy) { mode = .month }
                        }
                    }
                } else if sizeClass == .regular {
                    HStack(alignment: .top, spacing: 0) {
                        periodGrid.frame(maxWidth: .infinity)
                        Divider()
                        DayListView(day: selectedDay, style: style).frame(width: 320)
                    }
                } else {
                    periodGrid
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .sheet(isPresented: $showingEditor) {
                EventEditorView(initialDay: selectedDay)
            }
            .photosPicker(isPresented: $choosingScreenshot, selection: $screenshotItem, matching: .images)
            .onChange(of: screenshotItem) { Task { await loadScreenshot() } }
            .sheet(item: $screenshot) { picked in
                ScreenshotImportView(image: picked.image, repository: model.repository,
                                     creatorID: model.creatorID(for:)) { count in
                    screenshot = nil
                    if count > 0 { model.save() }
                }
            }
            .onChange(of: model.calendarResetRequest) {
                // Tipp aufs Widget: offene Tagesseite schließen und heute zeigen.
                openedDay = nil
                showToday()
}
            .sheet(isPresented: $showingFamily) {
                FamilyView()
            }
            .navigationDestination(item: $openedDay) { day in
                DayPage(day: day, style: style) { shown in show(shown) }
            }
        }
    }

    @ViewBuilder
    private var periodGrid: some View {
        if mode == .week {
            VStack(spacing: 0) {
                weekHeader
                weekPager
            }
        } else {
            VStack(spacing: 0) {
                monthHeader
                monthPager
            }
        }
    }

    /// Wochen als Seiten, wie die Monate: fünf Jahre in jede Richtung. Im Wisch-Modus wie die Monate
    /// von oben nach unten, damit seitliches Wischen zu Todos und Einkauf führt.
    @ViewBuilder
    private var weekPager: some View {
        if isVertical {
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) { weekPages }
                    .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
            .modifier(MonthPagerBehavior(scrolledMonth: $scrolledWeek, month: $week))
        } else {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) { weekPages }
                    .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
            .modifier(MonthPagerBehavior(scrolledMonth: $scrolledWeek, month: $week))
        }
    }

    private var weekPages: some View {
        ForEach(Self.pagedWeeks, id: \.self) { page in
            WeekPageView(weekStart: page, selectedDay: $selectedDay, style: style,
                         onOpenDay: sizeClass == .regular ? nil : { openedDay = $0 })
                .containerRelativeFrame([.horizontal, .vertical])
        }
    }

    private static let pagedWeeks: [Date] = {
        let current = startOfWeek(.now)
        return (-260...260).compactMap { Calendar.current.date(byAdding: .weekOfYear, value: $0, to: current) }
    }()

    static func startOfWeek(_ date: Date) -> Date {
        Calendar.current.dateInterval(of: .weekOfYear, for: date)?.start ?? date
    }

    /// Springt in allen Ansichten auf den Tag (Monat, Woche, Auswahl).
    private func show(_ day: Date) {
        selectedDay = Calendar.current.startOfDay(for: day)
        month = Self.startOfMonth(day)
        scrolledMonth = month
        week = Self.startOfWeek(day)
        scrolledWeek = week
    }

    /// Kalenderwoche und Zeitraum, mit Pfeilen für VoiceOver.
    private var weekHeader: some View {
        let end = Calendar.current.date(byAdding: .day, value: 6, to: week) ?? week
        return HStack(alignment: .firstTextBaseline) {
            Text("Week \(Calendar.current.component(.weekOfYear, from: week))")
                .font(.title2.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            Text((week..<end).formatted(.interval.day().month(.abbreviated).year()))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Button("Previous Week", systemImage: isVertical ? "chevron.up" : "chevron.left") { showWeek(offset: -1) }
            Button("Next Week", systemImage: isVertical ? "chevron.down" : "chevron.right") { showWeek(offset: 1) }
        }
        .labelStyle(.iconOnly)
        .imageScale(.large)
        .buttonStyle(.borderless)
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    private func showWeek(offset: Int) {
        guard let target = Calendar.current.date(byAdding: .weekOfYear, value: offset, to: week) else { return }
        withAnimation(.snappy) { scrolledWeek = target }
    }

    /// Monate als Seiten: Beim Wischen laufen alter und neuer Monat mit dem Finger mit.
    /// Zehn Jahre in jede Richtung; gebaut werden nur die sichtbaren Seiten.
    /// Klassisch seitlich und genau eine Seite pro Wisch; im Wisch-Modus von oben nach unten wie bei
    /// Apple, mit Schwung auch über mehrere Monate, und immer an einem Monatsanfang einrastend.
    @ViewBuilder
    private var monthPager: some View {
        if isVertical {
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) { monthPages }
                    .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .modifier(MonthPagerBehavior(scrolledMonth: $scrolledMonth, month: $month))
        } else {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) { monthPages }
                    .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
            .modifier(MonthPagerBehavior(scrolledMonth: $scrolledMonth, month: $month))
        }
    }

    private var monthPages: some View {
        ForEach(Self.pagedMonths, id: \.self) { page in
            MonthGridView(grid: MonthGrid(containing: page), selectedDay: $selectedDay, style: style,
                          onOpenDay: sizeClass == .regular ? nil : { openedDay = $0 })
                .containerRelativeFrame([.horizontal, .vertical])
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
            Button("Previous Month", systemImage: isVertical ? "chevron.up" : "chevron.left") { showMonth(offset: -1) }
            Button("Next Month", systemImage: isVertical ? "chevron.down" : "chevron.right") { showMonth(offset: 1) }
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

    private func showToday() {
        withAnimation(.snappy) {
            scrolledMonth = Self.startOfMonth(.now)
            scrolledWeek = Self.startOfWeek(.now)
            selectedDay = Calendar.current.startOfDay(for: .now)
        }
        if mode == .year { month = Self.startOfMonth(.now) }
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
        if isVertical {
            // Ohne Tab-Leiste: „Familie“ als Blatt; das Abzeichen zeigt Familien ohne eigenes Profil.
            ToolbarItem(placement: .topBarLeading) {
                Button("Family", systemImage: model.familiesNeedingProfile.isEmpty
                       ? "person.3" : "person.crop.circle.badge.exclamationmark") { showingFamily = true }
            }
        }
        ToolbarItem(placement: .topBarLeading) {
            Button("Today", action: showToday)
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Menu {
                Picker("View", selection: Binding(
                    get: { mode },
                    set: { newMode in
                        // Woche und Monat zeigen den gewählten Tag.
                        show(selectedDay)
                        withAnimation(.snappy) { mode = newMode }
                    }
                )) {
                    ForEach(CalendarMode.allCases) { option in
                        Label(option.title, systemImage: option.systemImage).tag(option)
                    }
                }
            } label: {
                Label("View", systemImage: mode.systemImage)
            }
            filterMenu
            // Tippen: neuer Termin; lange drücken: auch „Termin aus Screenshot“.
            Menu {
                Button("New Event", systemImage: "square.and.pencil") { showingEditor = true }
                Button("Event from Screenshot", systemImage: "text.viewfinder") { choosingScreenshot = true }
            } label: {
                Label("New Event", systemImage: "plus")
            } primaryAction: {
                showingEditor = true
            }
        }
    }

    private func loadScreenshot() async {
        guard let item = screenshotItem else { return }
        screenshotItem = nil
        if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
            screenshot = PickedImage(image: image)
        }
    }

    private var filterMenu: some View {
        Menu {
            Section("Person") {
                Picker("Person", selection: $person) {
                    Text("Everyone").tag(Member?.none)
                    ForEach(families) { family in
                        ForEach(model.repository.activeMembers(of: family)) { member in
                            Group {
                                if families.count > 1 {
                                    Text("\(member.displayLabel) · \(family.name ?? "")")
                                } else {
                                    Text(member.displayLabel)
                                }
                            }
                            .tag(Member?.some(member))
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

/// Ausgewähltes Bild für das Blatt „Termin aus Screenshot“.
struct PickedImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// Gemeinsames Verhalten beider Blätter-Richtungen: angezeigten Monat (bzw. Woche) mitführen.
private struct MonthPagerBehavior: ViewModifier {
    @Binding var scrolledMonth: Date?
    @Binding var month: Date

    func body(content: Content) -> some View {
        content
            .scrollIndicators(.hidden)
            .scrollPosition(id: $scrolledMonth)
            .onChange(of: scrolledMonth) {
                if let scrolledMonth, scrolledMonth != month { month = scrolledMonth }
            }
    }
}
