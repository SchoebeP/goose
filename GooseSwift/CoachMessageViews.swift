import SwiftUI

struct CoachMessageBubble: View {
  let message: CoachChatMessage

  var body: some View {
    HStack(alignment: .bottom) {
      if message.role == .user {
        Spacer(minLength: 42)
      }

      VStack(alignment: .leading, spacing: 10) {
        if !message.text.isEmpty {
          CoachMessageText(message: message)
        }

        if message.isCancelled {
          CoachCancelledMessageStatus(hasPartialText: !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } else if message.isStreaming {
          HStack(spacing: 8) {
            ProgressView()
              .controlSize(.small)
            Text("Thinking")
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(.secondary)
          }
        }

        if !message.toolEvents.isEmpty {
          VStack(spacing: 8) {
            ForEach(message.toolEvents) { event in
              CoachToolCallRow(event: event)
            }
          }
        }
      }
      .padding(.horizontal, horizontalPadding)
      .padding(.vertical, verticalPadding)
      .frame(maxWidth: message.role == .user ? 320 : .infinity, alignment: .leading)
      .background(background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

      if message.role == .assistant {
        Spacer(minLength: 42)
      }
    }
  }

  private var background: Color {
    switch message.role {
    case .user:
      return .blue
    case .assistant:
      return .clear
    }
  }

  private var horizontalPadding: CGFloat {
    message.role == .user ? 12 : 2
  }

  private var verticalPadding: CGFloat {
    message.role == .user ? 10 : 4
  }
}

private struct CoachMessageText: View {
  let message: CoachChatMessage

  var body: some View {
    Group {
      if message.role == .assistant {
        VStack(alignment: .leading, spacing: 4) {
          ForEach(markdownLines.indices, id: \.self) { index in
            let line = markdownLines[index]
            if line.isEmpty {
              Color.clear
                .frame(height: 6)
            } else {
              Text(Self.markdownText(for: line))
            }
          }
        }
      } else {
        Text(message.text)
      }
    }
    .font(.body)
    .foregroundStyle(message.role == .user ? .white : .primary)
    .textSelection(.enabled)
    .fixedSize(horizontal: false, vertical: true)
  }

  private var markdownLines: [String] {
    message.text
      .replacingOccurrences(of: "\r\n", with: "\n")
      .split(separator: "\n", omittingEmptySubsequences: false)
      .map(String.init)
  }

  private static func markdownText(for line: String) -> AttributedString {
    // Inline-only: .full would let a model-controlled reply embed remote
    // images (tracking pixels) that SwiftUI fetches on render.
    let options = AttributedString.MarkdownParsingOptions(
      interpretedSyntax: .inlineOnlyPreservingWhitespace,
      failurePolicy: .returnPartiallyParsedIfPossible
    )
    return (try? AttributedString(markdown: line, options: options)) ?? AttributedString(line)
  }
}

private struct CoachCancelledMessageStatus: View {
  let hasPartialText: Bool

  var body: some View {
    HStack(spacing: 7) {
      Image(systemName: "stop.circle.fill")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)

      Text(hasPartialText ? "Stopped" : "Generation stopped")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 9)
    .padding(.vertical, 6)
    .background(.ultraThinMaterial, in: Capsule(style: .continuous))
  }
}

private struct CoachToolCallRow: View {
  let event: CoachToolEvent
  @State private var isExpanded = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Button {
        withAnimation(.easeInOut(duration: 0.16)) {
          isExpanded.toggle()
        }
      } label: {
        HStack(spacing: 7) {
          Image(systemName: "chevron.right")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.secondary)
            .rotationEffect(.degrees(isExpanded ? 90 : 0))
            .frame(width: 10, height: 14)

          Image(systemName: "wrench.and.screwdriver")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.blue)

          Text(event.name)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)

          Spacer(minLength: 8)

          CoachToolStatusBadge(status: event.status)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

      if isExpanded {
        VStack(alignment: .leading, spacing: 8) {
          if !event.arguments.isEmpty {
            CoachToolPayloadBlock(title: "Arguments", text: CoachToolPayloadFormatter.format(event.arguments))
          }
          if let resultSummary = event.resultSummary, !resultSummary.isEmpty {
            CoachToolPayloadBlock(title: "Result", text: CoachToolPayloadFormatter.format(resultSummary))
          }
        }
        .padding(.leading, 17)
        .transition(.opacity.combined(with: .move(edge: .top)))
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(Color(.separator).opacity(0.16), lineWidth: 1)
    }
  }
}

private struct CoachToolStatusBadge: View {
  let status: String

  var body: some View {
    Text(status)
      .font(.caption2.weight(.semibold))
      .foregroundStyle(color)
      .lineLimit(1)
      .padding(.horizontal, 7)
      .padding(.vertical, 3)
      .background(color.opacity(0.12), in: Capsule(style: .continuous))
  }

  private var color: Color {
    switch status.lowercased() {
    case "returned":
      return .green
    case "running":
      return .orange
    case "calling", "preparing":
      return .blue
    default:
      return .secondary
    }
  }
}

private struct CoachToolPayloadBlock: View {
  let title: String
  let text: String

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(title)
        .font(.caption2.weight(.bold))
        .foregroundStyle(.secondary)
        .textCase(.uppercase)

      Text(text)
        .font(.system(size: 11, weight: .regular, design: .monospaced))
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
  }
}

private enum CoachToolPayloadFormatter {
  static func format(_ value: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return "{}"
    }
    guard let data = trimmed.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data),
          JSONSerialization.isValidJSONObject(object),
          let formattedData = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
          let formatted = String(data: formattedData, encoding: .utf8) else {
      return trimmed
    }
    return formatted.replacingOccurrences(of: "\\/", with: "/")
  }
}
