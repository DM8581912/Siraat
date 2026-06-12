import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var services: AppServices
    @StateObject private var viewModel = DashboardViewModel()
    @Binding var selectedTab: AppTab

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Siraat")
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text("Your Quran companion for reading, listening, translation, and recitation practice.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                SectionBand(title: "Today") {
                    HStack(spacing: 16) {
                        SummaryMetric(title: "Script", value: viewModel.settings.script.displayName)
                        SummaryMetric(title: "Bookmarks", value: "\(viewModel.bookmarks.count)")
                        SummaryMetric(title: "Next", value: viewModel.prayerSchedule?.nextPrayer?.name.displayName ?? "--")
                    }
                }

                SectionBand(title: "Prayer Times") {
                    PrayerTimesSummary(schedule: viewModel.prayerSchedule)

                    Button {
                        viewModel.requestLocation()
                    } label: {
                        Label("Use Current Location", systemImage: "location")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint("Requests location to calculate local prayer times")

                    Text(viewModel.locationStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        viewModel.schedulePrayerReminders()
                    } label: {
                        Label("Schedule Prayer Reminders", systemImage: "bell")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.prayerSchedule == nil)

                    Text(viewModel.reminderStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                SectionBand(title: "Qibla") {
                    QiblaSummary(direction: viewModel.qiblaDirection)
                }

                SectionBand(title: "Quick Actions") {
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
                    }
                }

                SectionBand(title: "Continue") {
                    if let readingPosition = viewModel.readingPosition {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Last read")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(QuranChapter.chapter(number: readingPosition.surahNumber).transliteratedName), Ayah \(readingPosition.verseNumber)")
                                .font(.headline)
                        }
                    }

                    Button {
                        selectedTab = .quran
                    } label: {
                        Label("Open Quran Reader", systemImage: "book")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the Quran reader tab")
                }
            }
            .padding()
        }
        .navigationTitle("Dashboard")
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
    }
}

private struct SummaryMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title2.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PrayerTimesSummary: View {
    let schedule: DailyPrayerSchedule?

    private let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        if let schedule {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                ForEach(schedule.times) { prayer in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(prayer.name.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(formatter.string(from: prayer.date))
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(prayer.id == schedule.nextPrayer?.id ? SiraatColor.gold.opacity(0.18) : SiraatColor.background)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        } else {
            ContentUnavailableView(
                "Prayer times need location",
                systemImage: "location.magnifyingglass",
                description: Text("Use your current location to calculate today’s prayer schedule on device.")
            )
        }
    }
}

private struct QiblaSummary: View {
    let direction: QiblaDirection?

    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle()
                    .strokeBorder(SiraatColor.secondaryBackground, lineWidth: 12)
                    .frame(width: 132, height: 132)

                Image(systemName: "location.north.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(SiraatColor.accent)
                    .rotationEffect(.degrees(direction?.compassOffsetDegrees ?? direction?.bearingDegrees ?? 0))
                    .animation(.spring(response: 0.35, dampingFraction: 0.82), value: direction?.compassOffsetDegrees)

                Text("N")
                    .font(.caption.bold())
                    .offset(y: -54)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Qibla compass")
            .accessibilityValue(direction?.displayBearing ?? "Location needed")

            VStack(alignment: .leading, spacing: 6) {
                Text(direction?.displayBearing ?? "--")
                    .font(.largeTitle.bold())
                Text(direction?.compassOffsetDegrees == nil ? "Bearing from north" : "Turn until the arrow points forward")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}
