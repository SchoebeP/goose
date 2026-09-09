import Foundation
import SwiftUI

// ============================================================
// Morning — Direction A "Quiet Companion".
// Last night, just processed: HRV / Resting HR / Wrist temp / Sleep,
// each judged against the owner's own personal usual band. Respiratory
// and SpO2 are intentionally absent (fake / not measurable) — Sleep
// takes Respiratory's place in the 2×2. Every number is our own.
// ============================================================

/// Morning landing screen. No longer a tabbed container — `HealthView`
/// just wraps this so legacy references keep compiling.
struct MorningView: View {
  @EnvironmentObject var model: GooseAppModel
  @ObservedObject var healthStore: HealthDataStore
  @Binding var selectedDate: Date

  var body: some View {
    let store = healthStore
    let night = store.latestBandVitalDay()
    let bands = store.vitalBands
    let lastSleep = store.sleepNights.last

    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        hero(night: night)

        LazyVGrid(columns: gridColumns, spacing: 12) {
          NavigationLink(value: GDADetail.hrv) {
            GDAVitalTile(
              label: "HRV",
              color: GDA.hrv,
              value: night?.hrvRMSSDms,
              unit: "ms",
              band: bands["hrv"],
              decimals: 1
            )
          }
          .buttonStyle(.plain)

          GDAVitalTile(
            label: "Resting HR",
            color: GDA.heart,
            value: night?.restingHRbpm,
            unit: "bpm",
            band: bands["rhr"]
          )

          GDAVitalTile(
            label: "Wrist temp",
            color: GDA.temp,
            value: night?.skinTempValue,
            unit: "°C",
            band: bands["temp"],
            provisional: true,
            decimals: 1
          )

          NavigationLink(value: GDADetail.sleep) {
            sleepTile(minutes: lastSleep?.minutes)
          }
          .buttonStyle(.plain)
        }

        Text("* provisional — coarse skin-temp calibration")
          .font(.system(size: 12))
          .foregroundStyle(GDA.text3)

        partialTodayNote

        Text("Judged against your own last weeks, not population norms. Our numbers, never WHOOP's.")
          .font(.system(size: 12))
          .foregroundStyle(GDA.text3)
          .multilineTextAlignment(.center)
          .frame(maxWidth: .infinity)
          .padding(.top, 2)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 18)
    }
    .gdaScreenBackground()
    .navigationTitle("Morning")
    .navigationBarTitleDisplayMode(.inline)
    .navigationDestination(for: GDADetail.self) { d in
      switch d {
      case .sleep: GDASleepDetailView(store: store)
      case .hrv: GDAHRVDetailView(store: store)
      }
    }
    .task {
      store.refreshBandVitalsDaily()
      store.refreshSleepNights()
    }
  }

  private var gridColumns: [GridItem] {
    [
      GridItem(.flexible(minimum: 0), spacing: 12),
      GridItem(.flexible(minimum: 0), spacing: 12),
    ]
  }

  // MARK: - Hero

  @ViewBuilder
  private func hero(night: BandVitalDay?) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("NIGHT OF \(nightLabel(for: night)) · JUST PROCESSED")
        .font(GDA.caps(11.5))
        .tracking(1.4)
        .foregroundStyle(GDA.text3)
        .lineLimit(1)
        .minimumScaleFactor(0.7)

      Text("A mostly usual morning.")
        .font(.system(size: 27, weight: .bold, design: .rounded))
        .foregroundStyle(GDA.text)
        .fixedSize(horizontal: false, vertical: true)

      Text("HRV and resting heart rate sit in your range — wrist temp reads at the top of its.")
        .font(.system(size: 14))
        .foregroundStyle(GDA.text2)
        .lineSpacing(3)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 16)
    .padding(.vertical, 18)
    .background(
      LinearGradient(
        colors: [GDA.hrv.opacity(0.09), GDA.surface],
        startPoint: .top,
        endPoint: .bottom
      ),
      in: RoundedRectangle(cornerRadius: GDA.cardRadius, style: .continuous)
    )
    .overlay(
      RoundedRectangle(cornerRadius: GDA.cardRadius, style: .continuous)
        .strokeBorder(GDA.line, lineWidth: 1)
    )
  }

  // MARK: - Sleep tile (replaces Respiratory in the 2×2)

  @ViewBuilder
  private func sleepTile(minutes: Int?) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 6) {
        Circle().fill(GDA.sleep).frame(width: 8, height: 8)
        Text("SLEEP")
          .font(GDA.caps(12))
          .tracking(0.6)
          .foregroundStyle(GDA.text2)
          .lineLimit(1)
        Spacer(minLength: 4)
        Image(systemName: "chevron.right")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(GDA.text3)
      }
      Text(sleepDurationText(minutes: minutes))
        .font(GDA.num(30))
        .foregroundStyle(GDA.text)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
      Text("Detected by us from movement + HR")
        .font(.system(size: 11.5))
        .foregroundStyle(GDA.text3)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .gdaCard()
  }

  // MARK: - Partial-today note

  private var partialTodayNote: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: "moon")
        .font(.system(size: 18))
        .foregroundStyle(GDA.text3)
      Text("Today's resting HR is partial and reads high. Tonight's sleep completes the picture — check back tomorrow morning.")
        .font(.system(size: 13))
        .foregroundStyle(GDA.text2)
        .lineSpacing(3)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .gdaCard()
  }

  // MARK: - Formatting

  /// "Xh Ym" from a sleep duration in minutes, or "—" when unknown.
  private func sleepDurationText(minutes: Int?) -> String {
    guard let minutes, minutes > 0 else { return "—" }
    let h = minutes / 60
    let m = minutes % 60
    return "\(h)h \(m)m"
  }

  /// "JUN 9" from the band-vitals "yyyy-MM-dd" date, or "LAST NIGHT" when none.
  private func nightLabel(for night: BandVitalDay?) -> String {
    guard let key = night?.date else { return "LAST NIGHT" }
    let parser = DateFormatter()
    parser.calendar = .current
    parser.locale = Locale(identifier: "en_US_POSIX")
    parser.timeZone = Calendar.current.timeZone
    parser.dateFormat = "yyyy-MM-dd"
    guard let date = parser.date(from: key) else { return key.uppercased() }
    let out = DateFormatter()
    out.calendar = .current
    out.locale = Locale(identifier: "en_US_POSIX")
    out.timeZone = Calendar.current.timeZone
    out.dateFormat = "MMM d"
    return out.string(from: date).uppercased()
  }
}

/// Legacy wrapper: `HealthView` is no longer tabbed — it just renders the
/// Morning screen so existing references keep compiling.
struct HealthView: View {
  @ObservedObject var store: HealthDataStore
  @State private var selectedDate = Date()

  var body: some View {
    MorningView(healthStore: store, selectedDate: $selectedDate)
  }
}
