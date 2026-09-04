import SwiftUI

/// U1: the Sleep page was unreachable from the tab UI (deep-link only) — this
/// Home card restores one-tap access, mirroring the Stress card's pattern.
/// U2-aligned: no fabricated score — "--" + "Pas encore de donnée" until a
/// trusted value exists (recovery-todo: fixtures must go).
struct HomeSleepSection: View {
  let sleep: HealthMetricSnapshot
  let openSleep: () -> Void

  private var scoreText: String {
    // Only surface a number that came from real packet data; anything else is
    // an honest "--" (never the old fallback-92).
    if case .available = sleep.source,
       let n = SleepV2Numbers.firstInt(in: sleep.value),
       n > 0 {
      return "\(n)"
    }
    return "--"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HomeSectionHeader(title: "Sommeil")

      Button {
        openSleep()
      } label: {
        HStack(spacing: 14) {
          VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
              Image(systemName: "bed.double.fill")
                .foregroundStyle(sleep.tint)
              Text("Dernière nuit")
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
              Spacer()
            }

            Text(sleep.freshness)
              .font(.caption.weight(.semibold))
              .foregroundStyle(.secondary)

            Text(scoreText == "--" ? "Pas encore de donnée" : "Score de sommeil (notre estimation)")
              .font(.caption)
              .foregroundStyle(.tertiary)
          }

          ZStack {
            Circle()
              .stroke(sleep.tint.opacity(0.14), lineWidth: 8)
            Circle()
              .trim(from: 0, to: scoreText == "--" ? 0 : scoreProgress)
              .stroke(sleep.tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
              .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
              Text(scoreText)
                .font(.title3.bold())
              Text(sleep.status)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
          }
          .frame(width: 76, height: 76)

          Image(systemName: "chevron.right")
            .font(.caption.weight(.bold))
            .foregroundStyle(.tertiary)
        }
        .padding(14)
        .cardSurface(tint: sleep.tint, prominent: true)
      }
      .buttonStyle(.plain)
    }
  }

  private var scoreProgress: Double {
    min(max((Double(scoreText) ?? 0) / 100, 0), 1)
  }
}
