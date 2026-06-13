import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var services: AppServices
    @StateObject private var viewModel = DashboardViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @Binding var selectedTab: AppTab

    var body: some View {
        ErrorBoundaryView(error: viewModel.loadError, retryAction: { viewModel.load() }) {
            ScrollView {
                VStack(alignment: .leading, spacing: SiraatSpacing.md) {
                    DashboardHeader(hijriDate: viewModel.hijriDateText)

                    if let schedule = viewModel.prayerSchedule, !schedule.times.isEmpty {
                        NextPrayerHero(schedule: schedule)

                        PrayerTimesStrip(schedule: schedule)
                            .padding(.top, SiraatSpacing.xxs)

                        if viewModel.prayerSchedule != nil {
                            ReminderCard(
                                statusText: viewModel.reminderStatusText,
                                isEnabled: viewModel.reminderSettings.isEnabled
                            ) {
                                viewModel.schedulePrayerReminders()
                            }
                        }
                    } else {
                        LocationPromptCard {
                            viewModel.requestLocation()
                        } onManualLocation: { coord in
                            viewModel.setManualLocation(coord)
                        }
                    }

                    if let verse = viewModel.verseOfTheDay {
                        SectionHeader("VERSE OF THE DAY")
                            .padding(.top, SiraatSpacing.xs)
                        VerseOfTheDayCard(verse: verse)
                    }

                    QiblaCard(direction: viewModel.qiblaDirection)

                    SectionHeader("QUICK ACTIONS")
                        .padding(.top, SiraatSpacing.xs)
                    QuickActionsCard(selectedTab: $selectedTab)

                    if let readingPosition = viewModel.readingPosition {
                        ContinueReadingCard(position: readingPosition) {
                            selectedTab = .quran
                        }
                    }
                }
                .padding(SiraatSpacing.lg)
            }
        }
        .background(SiraatColor.background.ignoresSafeArea())
        .navigationTitle("")
        .toolbar(.hidden, for: .navigationBar)
        .toast($viewModel.toastState)
        .alert("Location Error", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { _ in viewModel.errorMessage = nil })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .task {
            viewModel.configure(
                databaseManager: services.quranDatabaseManager,
                locationManager: services.locationManager,
                prayerTimesService: services.prayerTimesService,
                prayerNotificationService: services.prayerNotificationService,
                qiblaService: services.qiblaService
            )
            viewModel.load()
        }
        .onChange(of: scenePhase) {
            viewModel.scenePhaseChanged(scenePhase)
        }
    }
}

// MARK: - Section header

private struct SectionHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(SiraatType.micro.weight(.semibold))
            .tracking(1.2)
            .foregroundStyle(SiraatColor.textSecondary)
    }
}

// MARK: - Header

private struct DashboardHeader: View {
    let hijriDate: String

    private var gregorianDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, d MMMM"
        return formatter.string(from: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SiraatSpacing.xxs) {
            Text("Siraat")
                .font(SiraatType.display)
                .foregroundStyle(SiraatColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: SiraatSpacing.xs) {
                Label(hijriDate, systemImage: "moon.stars.fill")
                    .foregroundStyle(SiraatColor.accent)
                Text("·").foregroundStyle(SiraatColor.textSecondary)
                Text(gregorianDate)
                    .foregroundStyle(SiraatColor.textSecondary)
            }
            .font(SiraatType.callout.weight(.medium))
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Next prayer hero

private struct NextPrayerHero: View {
    let schedule: DailyPrayerSchedule

    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            hero(now: context.date)
        }
    }

    private func hero(now: Date) -> some View {
        let upcoming = schedule.times.first { $0.date > now && $0.name != .sunrise }
            ?? schedule.times.first { $0.date > now }
        let previous = schedule.times.last { $0.date <= now }
        let progress = fractionElapsed(now: now, previous: previous, next: upcoming)

        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("NEXT PRAYER")
                        .font(.caption.weight(.semibold))
                        .tracking(1.5)
                        .foregroundStyle(.white.opacity(0.7))
                    Text(upcoming?.name.displayName ?? "—")
                        .font(.system(size: 40, weight: .bold, design: .serif))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let upcoming {
                        Text(timeFormatter.string(from: upcoming.date))
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                Spacer()
                CountdownRing(progress: progress) {
                    VStack(spacing: 0) {
                        if let upcoming {
                            Text(countdown(from: now, to: upcoming.date))
                                .font(.system(.headline, design: .rounded).weight(.semibold))
                                .foregroundStyle(.white)
                                .monospacedDigit()
                            Text("left")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }
            }
        }
        .padding(SiraatSpacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [SiraatColor.accentDeep, SiraatColor.accent],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: SiraatRadius.card, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Next prayer \(upcoming?.name.displayName ?? ""), \(upcoming.map { countdown(from: now, to: $0.date) } ?? "") remaining")
    }

    private func fractionElapsed(now: Date, previous: PrayerTime?, next: PrayerTime?) -> Double {
        guard let next else { return 0 }
        let start = previous?.date ?? next.date.addingTimeInterval(-3600)
        let total = next.date.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        return min(max(now.timeIntervalSince(start) / total, 0), 1)
    }

    private func countdown(from now: Date, to target: Date) -> String {
        let remaining = max(0, Int(target.timeIntervalSince(now)))
        let hours = remaining / 3600
        let minutes = (remaining % 3600) / 60
        let seconds = remaining % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m \(String(format: "%02d", seconds))s" }
        return "\(seconds)s"
    }
}

private struct CountdownRing<Content: View>: View {
    let progress: Double
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.2), lineWidth: 6)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(.white, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            content
        }
        .frame(width: 92, height: 92)
    }
}

// MARK: - Prayer times list

private struct PrayerTimesStrip: View {
    let schedule: DailyPrayerSchedule

    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = context.date
            let nextID = (schedule.times.first { $0.date > now && $0.name != .sunrise }
                ?? schedule.times.first { $0.date > now })?.id

            VStack(spacing: 0) {
                ForEach(Array(schedule.times.enumerated()), id: \.element.id) { index, prayer in
                    let isNext = prayer.id == nextID
                    let isPast = prayer.date <= now
                    HStack {
                        Image(systemName: icon(for: prayer.name))
                            .font(SiraatType.body)
                            .foregroundStyle(isNext ? SiraatColor.accent : SiraatColor.textSecondary)
                            .frame(width: 26)
                        Text(prayer.name.displayName)
                            .font(SiraatType.body.weight(isNext ? .semibold : .regular))
                            .foregroundStyle(isNext ? SiraatColor.textPrimary : (isPast ? SiraatColor.textSecondary : SiraatColor.textPrimary))
                        Spacer()
                        Text(timeFormatter.string(from: prayer.date))
                            .font(SiraatType.body.weight(isNext ? .semibold : .regular))
                            .foregroundStyle(isNext ? SiraatColor.accent : SiraatColor.textPrimary)
                            .monospacedDigit()
                    }
                    .padding(.vertical, SiraatSpacing.sm)
                    .padding(.horizontal, SiraatSpacing.sm)
                    .background(isNext ? SiraatColor.accent.opacity(0.10) : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: SiraatRadius.inner, style: .continuous))

                    if index < schedule.times.count - 1 {
                        Divider().overlay(SiraatColor.hairline).padding(.leading, 48)
                    }
                }
            }
        }
    }

    private func icon(for name: PrayerName) -> String {
        switch name {
        case .fajr: "sunrise"
        case .sunrise: "sun.max"
        case .dhuhr: "sun.max.fill"
        case .asr: "sun.min"
        case .maghrib: "sunset"
        case .isha: "moon.stars"
        }
    }
}

// MARK: - Supporting cards

private struct LocationPromptCard: View {
    let action: () -> Void
    let onManualLocation: (LocationCoordinate) -> Void

    @State private var showManualEntry = false

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "location.magnifyingglass")
                    .font(.system(size: 36))
                    .foregroundStyle(SiraatColor.accent)
                Text("Prayer times need your location")
                    .font(.headline)
                    .foregroundStyle(SiraatColor.textPrimary)
                Text("Calculated on device using your chosen method. Nothing is uploaded.")
                    .font(.subheadline)
                    .foregroundStyle(SiraatColor.textSecondary)
                Button(action: action) {
                    Label("Use Current Location", systemImage: "location.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(SiraatColor.accent)

                Button {
                    showManualEntry = true
                } label: {
                    Label("Enter Location Manually", systemImage: "mappin.and.ellipse")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(SiraatColor.accent)
            }
        }
        .sheet(isPresented: $showManualEntry) {
            ManualLocationSheet(onSelect: onManualLocation)
                .presentationDetents([.medium])
        }
    }
}

private struct ManualLocationSheet: View {
    let onSelect: (LocationCoordinate) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var latitude = ""
    @State private var longitude = ""

    private let cities: [(String, Double, Double)] = [
        ("Makkah", 21.4225, 39.8262),
        ("New York", 40.7128, -74.0060),
        ("London", 51.5074, -0.1278),
        ("Istanbul", 41.0082, 28.9784),
        ("Kuala Lumpur", 3.1390, 101.6869),
        ("Cairo", 30.0444, 31.2357),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section("Quick Select") {
                    ForEach(cities, id: \.0) { name, lat, lon in
                        Button {
                            onSelect(LocationCoordinate(latitude: lat, longitude: lon))
                            dismiss()
                        } label: {
                            Text(name).foregroundStyle(SiraatColor.textPrimary)
                        }
                    }
                }

                Section("Custom Coordinates") {
                    TextField("Latitude (e.g. 40.71)", text: $latitude)
                        .keyboardType(.decimalPad)
                    TextField("Longitude (e.g. -74.01)", text: $longitude)
                        .keyboardType(.decimalPad)
                    Button("Use These Coordinates") {
                        guard let lat = Double(latitude), let lon = Double(longitude),
                              (-90...90).contains(lat), (-180...180).contains(lon) else { return }
                        onSelect(LocationCoordinate(latitude: lat, longitude: lon))
                        dismiss()
                    }
                    .disabled({
                        guard let lat = Double(latitude), let lon = Double(longitude) else { return true }
                        return !(-90...90).contains(lat) || !(-180...180).contains(lon)
                    }())
                }
            }
            .navigationTitle("Manual Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

private struct ReminderCard: View {
    let statusText: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Card {
            HStack(spacing: 14) {
                Image(systemName: isEnabled ? "bell.fill" : "bell")
                    .font(.title3)
                    .foregroundStyle(SiraatColor.gold)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Prayer Reminders")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SiraatColor.textPrimary)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(SiraatColor.textSecondary)
                }
                Spacer()
                Button("Schedule", action: action)
                    .buttonStyle(.bordered)
                    .tint(SiraatColor.accent)
            }
        }
    }
}

private struct QiblaCard: View {
    let direction: QiblaDirection?

    var body: some View {
        Card {
            HStack(spacing: 20) {
                ZStack {
                    Circle()
                        .strokeBorder(SiraatColor.hairline, lineWidth: 10)
                        .frame(width: 96, height: 96)
                    Image(systemName: "location.north.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(SiraatColor.accent)
                        .rotationEffect(.degrees(direction?.compassOffsetDegrees ?? direction?.bearingDegrees ?? 0))
                        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: direction?.compassOffsetDegrees)
                    Text("N").font(.caption2.bold()).foregroundStyle(SiraatColor.textSecondary).offset(y: -38)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Qibla compass")
                .accessibilityValue(direction?.displayBearing ?? "Location needed")

                VStack(alignment: .leading, spacing: 4) {
                    Text("Qibla")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SiraatColor.textSecondary)
                    Text(direction?.displayBearing ?? "—")
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .foregroundStyle(SiraatColor.textPrimary)
                    Text(direction?.compassOffsetDegrees == nil ? "Bearing from north" : "Turn until the arrow points up")
                        .font(.footnote)
                        .foregroundStyle(SiraatColor.textSecondary)
                }
                Spacer()
            }
        }
    }
}

private struct VerseOfTheDayCard: View {
    let verse: QuranVerse

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Label("Verse of the Day", systemImage: "sun.haze")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SiraatColor.gold)

                ArabicText(verse.textUthmani, size: 24, scripture: true)
                    .lineSpacing(8)
                    .foregroundStyle(SiraatColor.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .multilineTextAlignment(.trailing)
                    .environment(\.layoutDirection, .rightToLeft)

                if !verse.translation.isEmpty {
                    Text(verse.translation)
                        .font(.subheadline)
                        .foregroundStyle(SiraatColor.textSecondary)
                }

                Text("Qur'an \(verse.verseKey) · Saheeh International")
                    .font(.caption2)
                    .foregroundStyle(SiraatColor.textSecondary)
            }
        }
    }
}

private struct QuickActionsCard: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        Card {
            VStack(spacing: 10) {
                Button {
                    selectedTab = .liveTranslation
                } label: {
                    Label("Start Khutba Translation", systemImage: "waveform.and.mic")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(SiraatColor.accent)

                NavigationLink {
                    RecitationCorrectionView()
                } label: {
                    Label("Practice Recitation", systemImage: "checkmark.seal")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(SiraatColor.accent)
            }
        }
    }
}

private struct ContinueReadingCard: View {
    let position: QuranReadingPosition
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Card {
                HStack(spacing: 14) {
                    Image(systemName: "book.fill")
                        .font(.title3)
                        .foregroundStyle(SiraatColor.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Continue reading")
                            .font(.caption)
                            .foregroundStyle(SiraatColor.textSecondary)
                        Text("\(QuranChapter.chapter(number: position.surahNumber).transliteratedName), Ayah \(position.verseNumber)")
                            .font(.headline)
                            .foregroundStyle(SiraatColor.textPrimary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(SiraatColor.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
