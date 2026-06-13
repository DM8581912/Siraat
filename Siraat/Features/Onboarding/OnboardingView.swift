import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var services: AppServices
    @Binding var hasCompletedOnboarding: Bool
    @State private var currentPage = 0
    @State private var showManualEntry = false
    @State private var manualLatitude = ""
    @State private var manualLongitude = ""
    @State private var manualCityName = ""
    @State private var locationGranted = false
    @State private var locationDenied = false

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentPage) {
                welcomePage.tag(0)
                featuresPage.tag(1)
                locationPage.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.3), value: currentPage)

            bottomBar
        }
        .background(SiraatColor.background.ignoresSafeArea())
        .onChange(of: services.locationManager.authorizationStatus) {
            let status = services.locationManager.authorizationStatus
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                locationGranted = true
            } else if status == .denied || status == .restricted {
                locationDenied = true
            }
        }
    }

    // MARK: - Welcome

    private var welcomePage: some View {
        VStack(spacing: SiraatSpacing.lg) {
            Spacer()
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 64))
                .foregroundStyle(SiraatColor.accent)
                .accessibilityHidden(true)

            Text("Siraat")
                .font(SiraatType.display)
                .foregroundStyle(SiraatColor.textPrimary)

            Text("A calm companion for daily Muslim practice.")
                .font(SiraatType.body)
                .foregroundStyle(SiraatColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, SiraatSpacing.xxl)

            Spacer()
            Spacer()
        }
    }

    // MARK: - Features

    private var featuresPage: some View {
        VStack(spacing: SiraatSpacing.lg) {
            Spacer()

            VStack(alignment: .leading, spacing: SiraatSpacing.lg) {
                FeatureRow(icon: "sun.max.fill", title: "Prayer Times",
                           body: "Accurate times from the Adhan engine, with your chosen calculation method.")
                FeatureRow(icon: "book.closed.fill", title: "Quran Reader",
                           body: "6,236 ayahs offline, 4 scripts, 6 translations, 4 reciters.")
                FeatureRow(icon: "location.north.fill", title: "Qibla Compass",
                           body: "True-north bearing to the Kaaba from your location.")
                FeatureRow(icon: "waveform.and.mic", title: "Live Translation",
                           body: "On-device Arabic-to-English khutba translation.")
            }
            .padding(.horizontal, SiraatSpacing.xl)

            Spacer()
            Spacer()
        }
    }

    // MARK: - Location

    private var locationPage: some View {
        ScrollView {
            VStack(spacing: SiraatSpacing.lg) {
                Spacer(minLength: SiraatSpacing.xxl)

                Image(systemName: "location.magnifyingglass")
                    .font(.system(size: 48))
                    .foregroundStyle(SiraatColor.accent)
                    .accessibilityHidden(true)

                Text("Prayer times need a location")
                    .font(SiraatType.title)
                    .foregroundStyle(SiraatColor.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Calculated on your device. Your location is never uploaded or stored on any server.")
                    .font(SiraatType.body)
                    .foregroundStyle(SiraatColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, SiraatSpacing.xl)

                if locationGranted {
                    Label("Location granted", systemImage: "checkmark.circle.fill")
                        .font(SiraatType.body.weight(.semibold))
                        .foregroundStyle(SiraatColor.accent)
                } else {
                    Button {
                        services.locationManager.requestLocation()
                    } label: {
                        Label("Use Current Location", systemImage: "location.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(SiraatColor.accent)
                    .padding(.horizontal, SiraatSpacing.xl)
                }

                if locationDenied || showManualEntry {
                    manualLocationSection
                } else if !locationGranted {
                    Button("Enter location manually") {
                        showManualEntry = true
                    }
                    .font(SiraatType.callout)
                    .foregroundStyle(SiraatColor.accent)
                }

                Spacer(minLength: SiraatSpacing.xxl)
            }
        }
    }

    private var manualLocationSection: some View {
        VStack(spacing: SiraatSpacing.md) {
            Text("Manual Location")
                .font(SiraatType.heading)
                .foregroundStyle(SiraatColor.textPrimary)

            CityButton(name: "Makkah", lat: 21.4225, lon: 39.8262, action: selectCity)
            CityButton(name: "New York", lat: 40.7128, lon: -74.0060, action: selectCity)
            CityButton(name: "London", lat: 51.5074, lon: -0.1278, action: selectCity)
            CityButton(name: "Istanbul", lat: 41.0082, lon: 28.9784, action: selectCity)
            CityButton(name: "Kuala Lumpur", lat: 3.1390, lon: 101.6869, action: selectCity)
            CityButton(name: "Cairo", lat: 30.0444, lon: 31.2357, action: selectCity)

            HStack(spacing: SiraatSpacing.sm) {
                VStack(alignment: .leading, spacing: SiraatSpacing.xxs) {
                    Text("Latitude").font(SiraatType.caption).foregroundStyle(SiraatColor.textSecondary)
                    TextField("e.g. 40.71", text: $manualLatitude)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: SiraatSpacing.xxs) {
                    Text("Longitude").font(SiraatType.caption).foregroundStyle(SiraatColor.textSecondary)
                    TextField("e.g. -74.01", text: $manualLongitude)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .padding(.horizontal, SiraatSpacing.xl)

            Button {
                applyManualCoordinates()
            } label: {
                Label("Use These Coordinates", systemImage: "mappin.and.ellipse")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(SiraatColor.accent)
            .padding(.horizontal, SiraatSpacing.xl)
            .disabled(!isValidManualInput)
        }
        .padding(.top, SiraatSpacing.sm)
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack {
            if currentPage > 0 {
                Button("Back") { currentPage -= 1 }
                    .foregroundStyle(SiraatColor.textSecondary)
            }

            Spacer()

            pageIndicator

            Spacer()

            if currentPage < 2 {
                Button("Next") { currentPage += 1 }
                    .fontWeight(.semibold)
                    .foregroundStyle(SiraatColor.accent)
            } else {
                Button("Get Started") { completeOnboarding() }
                    .fontWeight(.semibold)
                    .foregroundStyle(SiraatColor.accent)
                    .disabled(!hasLocation)
            }
        }
        .padding(.horizontal, SiraatSpacing.lg)
        .padding(.vertical, SiraatSpacing.md)
        .background(.regularMaterial)
    }

    private var pageIndicator: some View {
        HStack(spacing: SiraatSpacing.xs) {
            ForEach(0..<3, id: \.self) { page in
                Circle()
                    .fill(page == currentPage ? SiraatColor.accent : SiraatColor.hairline)
                    .frame(width: 8, height: 8)
            }
        }
    }

    // MARK: - Helpers

    private var hasLocation: Bool {
        services.locationManager.coordinate != nil
    }

    private var isValidManualInput: Bool {
        guard let lat = Double(manualLatitude), let lon = Double(manualLongitude) else { return false }
        return (-90...90).contains(lat) && (-180...180).contains(lon)
    }

    private func selectCity(lat: Double, lon: Double) {
        services.locationManager.setManualCoordinate(LocationCoordinate(latitude: lat, longitude: lon))
        locationGranted = true
    }

    private func applyManualCoordinates() {
        guard let lat = Double(manualLatitude), let lon = Double(manualLongitude) else { return }
        selectCity(lat: lat, lon: lon)
    }

    private func completeOnboarding() {
        hasCompletedOnboarding = true
    }
}

// MARK: - Subviews

private struct FeatureRow: View {
    let icon: String
    let title: String
    let body: String

    var body: some View {
        HStack(alignment: .top, spacing: SiraatSpacing.md) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(SiraatColor.accent)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: SiraatSpacing.xxs) {
                Text(title)
                    .font(SiraatType.heading)
                    .foregroundStyle(SiraatColor.textPrimary)
                Text(body)
                    .font(SiraatType.callout)
                    .foregroundStyle(SiraatColor.textSecondary)
            }
        }
    }
}

private struct CityButton: View {
    let name: String
    let lat: Double
    let lon: Double
    let action: (Double, Double) -> Void

    var body: some View {
        Button {
            action(lat, lon)
        } label: {
            HStack {
                Text(name)
                    .font(SiraatType.body)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
            }
            .foregroundStyle(SiraatColor.textPrimary)
            .padding(.horizontal, SiraatSpacing.md)
            .padding(.vertical, SiraatSpacing.sm)
            .background(SiraatColor.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: SiraatRadius.inner, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, SiraatSpacing.xl)
    }
}
