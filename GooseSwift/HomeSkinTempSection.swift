import SwiftUI

/// U5: skin temperature was collected but invisible (page untabbed). This Home
/// card surfaces the trusted delta when it exists, honest "--" otherwise, and
/// links to the calibration flow. Own computation — never labelled as WHOOP's.
struct HomeSkinTempSection: View {
  @ObservedObject var store: HealthDataStore
  let openCalibration: () -> Void

  private var tempText: String {
    store.recoveryWristTemperatureDisplayText()
  }

  private var hasValue: Bool { tempText != "--" }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HomeSectionHeader(title: "Température cutanée")

      Button {
        openCalibration()
      } label: {
        HStack(spacing: 14) {
          VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
              Image(systemName: "thermometer.medium")
                .foregroundStyle(.orange)
              Text("Écart vs ta baseline")
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
              Spacer()
            }

            Text(hasValue ? "Dernière nuit (notre calcul)" : "Pas encore de donnée")
              .font(.caption)
              .foregroundStyle(.tertiary)

            Text("Nuits connectées nécessaires pour la baseline")
              .font(.caption2)
              .foregroundStyle(.tertiary)
          }

          Text(hasValue ? tempText.replacingOccurrences(of: " C", with: " °C") : "--")
            .font(.title2.bold().monospacedDigit())
            .foregroundStyle(hasValue ? .orange : .secondary)

          Image(systemName: "chevron.right")
            .font(.caption.weight(.bold))
            .foregroundStyle(.tertiary)
        }
        .padding(14)
        .cardSurface(tint: .orange, prominent: false)
      }
      .buttonStyle(.plain)
    }
  }
}
