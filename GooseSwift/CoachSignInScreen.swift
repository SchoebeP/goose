import SwiftUI

struct CoachSignInScreen: View {
  let loginStatus: String
  let deviceCode: CodexLoginDeviceCode?
  let errorMessage: String?
  let signIn: () -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        VStack(alignment: .leading, spacing: 10) {
          Image(systemName: "sparkles")
            .font(.title2.weight(.bold))
            .foregroundStyle(.blue)
            .frame(width: 42, height: 42)
            .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

          Text("Sign in to Coach")
            .font(.title2.bold())
          Text("Sign in to stream Coach replies and local Goose tool calls.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

        VStack(alignment: .leading, spacing: 12) {
          CoachStatusLine(title: "Sign in", value: loginStatus)

          if let deviceCode {
            VStack(alignment: .leading, spacing: 8) {
              Text(deviceCode.userCode)
                .font(.title2.monospacedDigit().weight(.bold))
              Link(deviceCode.verificationURL.absoluteString, destination: deviceCode.verificationURL)
                .font(.footnote.weight(.semibold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
          }

          if let errorMessage, !errorMessage.isEmpty {
            Label(errorMessage, systemImage: "exclamationmark.triangle")
              .font(.footnote)
              .foregroundStyle(.red)
              .fixedSize(horizontal: false, vertical: true)
          }

          Button(action: signIn) {
            Label("Continue", systemImage: "person.crop.circle.badge.checkmark")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)

          Text("After sign-in, Coach automatically sends each question plus a bounded summary of local health data (scores, vitals, activity, capture status) to your OpenAI account. Tokens are stored in Keychain.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 18)
    }
  }
}

private struct CoachStatusLine: View {
  let title: String
  let value: String

  var body: some View {
    HStack {
      Text(title)
        .font(.subheadline)
        .foregroundStyle(.secondary)
      Spacer()
      Text(value)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.primary)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
  }
}
