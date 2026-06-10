import Foundation

@MainActor
final class OpenAICoachChatModel: ObservableObject {
  @Published private(set) var isSignedIn = false
  @Published private(set) var deviceCode: CodexLoginDeviceCode?
  @Published private(set) var loginStatus = "Not signed in"
  @Published private(set) var modelPreset: CoachModelPreset
  @Published private(set) var messages: [CoachChatMessage] = []
  @Published private(set) var streamState: CoachStreamState = .idle
  @Published private(set) var errorMessage: String?

  private static let modelPresetDefaultsKey = "goose.coach.modelPreset"
  private static let seedPromptText = "What should we look at today?"
  private var auth: CodexStoredChatGPTAuth?
  private var sendTask: Task<Void, Never>?
  private var loginTask: Task<Void, Never>?
  private let authClient = CodexSelfContainedAuthClient()
  private let client = OpenAIResponsesClient()

  init() {
    let storedRawValue = UserDefaults.standard.string(forKey: Self.modelPresetDefaultsKey)
    modelPreset = storedRawValue.flatMap(CoachModelPreset.init(rawValue:)) ?? .defaultValue
    messages = Self.normalizedPersistedMessages(CoachConversationStore.load())
    if !messages.isEmpty {
      persistConversation()
    }
  }

  deinit {
    sendTask?.cancel()
    loginTask?.cancel()
  }

  func refreshAuth() {
    Task { [weak self, authClient] in
      do {
        if let storedAuth = try await authClient.storedAuth(refreshIfNeeded: true) {
          self?.auth = storedAuth
          self?.isSignedIn = true
          self?.deviceCode = nil
          self?.loginStatus = "Signed in"
          self?.seedAssistantPromptIfNeeded()
        } else {
          self?.auth = nil
          self?.isSignedIn = false
          self?.deviceCode = nil
          self?.loginStatus = "Not signed in"
        }
      } catch {
        // A transient refresh failure must not sign the user out while a stored
        // session still exists; the next send retries the refresh.
        if let fallbackAuth = try? await authClient.storedAuth(refreshIfNeeded: false) {
          self?.auth = fallbackAuth
          self?.isSignedIn = true
          self?.deviceCode = nil
          self?.loginStatus = "Signed in"
          self?.seedAssistantPromptIfNeeded()
        } else {
          self?.auth = nil
          self?.isSignedIn = false
          self?.deviceCode = nil
          self?.loginStatus = "Auth check failed"
          self?.errorMessage = self?.describe(error) ?? String(describing: error)
        }
      }
    }
  }

  func selectModelPreset(_ preset: CoachModelPreset) {
    modelPreset = preset
    UserDefaults.standard.set(preset.rawValue, forKey: Self.modelPresetDefaultsKey)
  }

  func startNewConversation() {
    sendTask?.cancel()
    sendTask = nil
    streamState = .idle
    errorMessage = nil
    messages.removeAll()
    CoachConversationStore.clear()
    seedAssistantPromptIfNeeded()
  }

  func startOAuthSignIn() {
    loginTask?.cancel()
    loginStatus = "Requesting OAuth code"
    deviceCode = nil
    errorMessage = nil

    loginTask = Task { [weak self, authClient] in
      do {
        let code = try await authClient.requestDeviceCodeWithRetry()
        self?.deviceCode = CodexLoginDeviceCode(
          verificationURL: code.verificationURL,
          userCode: code.userCode
        )
        self?.loginStatus = "Waiting for approval"

        let storedAuth = try await authClient.completeDeviceCodeLogin(code)
        self?.auth = storedAuth
        self?.isSignedIn = true
        self?.deviceCode = nil
        self?.loginStatus = "Signed in"
        self?.seedAssistantPromptIfNeeded()
      } catch is CancellationError {
        self?.loginStatus = "Cancelled"
      } catch {
        self?.loginStatus = "OAuth failed"
        self?.errorMessage = self?.describe(error) ?? String(describing: error)
      }
    }
  }

  func signOut() {
    sendTask?.cancel()
    sendTask = nil
    loginTask?.cancel()
    loginTask = nil
    Task { [weak self, authClient] in
      do {
        try await authClient.clearStoredAuth()
      } catch {
        self?.errorMessage = self?.describe(error) ?? String(describing: error)
      }
    }
    auth = nil
    deviceCode = nil
    isSignedIn = false
    loginStatus = "Not signed in"
    streamState = .idle
    messages.removeAll()
    CoachConversationStore.clear()
  }

  func cancelStreaming() {
    sendTask?.cancel()
    sendTask = nil
    streamState = .idle
    cancelStreamingMessages()
  }

  func send(
    _ prompt: String,
    healthStore: HealthDataStore,
    appModel: GooseAppModel
  ) {
    let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedPrompt.isEmpty, !streamState.isStreaming else {
      return
    }
    guard let auth else {
      isSignedIn = false
      errorMessage = OpenAIResponsesError.missingOAuthSession.localizedDescription
      return
    }

    let assistantID = UUID()
    let contextualPrompt = contextualPrompt(for: trimmedPrompt)
    messages.append(CoachChatMessage(role: .user, text: trimmedPrompt))
    messages.append(CoachChatMessage(id: assistantID, role: .assistant, text: "", isStreaming: true))
    streamState = .streaming
    errorMessage = nil
    persistConversation()

    sendTask?.cancel()
    sendTask = Task { [weak self] in
      guard let self else {
        return
      }
      do {
        try await streamResponseLoop(
          prompt: trimmedPrompt,
          contextualPrompt: contextualPrompt,
          auth: auth,
          assistantID: assistantID,
          healthStore: healthStore,
          appModel: appModel
        )
        finishAssistantMessage(assistantID)
        streamState = .idle
      } catch is CancellationError {
        markAssistantMessageCancelled(assistantID)
        streamState = .idle
      } catch where isCancelledError(error) {
        markAssistantMessageCancelled(assistantID)
        streamState = .idle
      } catch {
        let message = describe(error)
        appendAssistantText("\n\(message)", to: assistantID)
        finishAssistantMessage(assistantID)
        errorMessage = message
        streamState = .failed(message)
      }
    }
  }

  private func streamResponseLoop(
    prompt: String,
    contextualPrompt: String,
    auth: CodexStoredChatGPTAuth,
    assistantID: UUID,
    healthStore: HealthDataStore,
    appModel: GooseAppModel
  ) async throws {
    let activeAuth = try await authClient.storedAuth(refreshIfNeeded: true) ?? auth
    self.auth = activeAuth
    let activeModelPreset = modelPreset
    var conversationInput = OpenAICoachRequestFactory.userInput(contextualPrompt)
    var input: Any = conversationInput
    // .auto (not .required): health-data tool output should only leave the device
    // when the model actually needs it for the question.
    var toolMode: OpenAICoachRequestFactory.ToolMode = .auto

    for _ in 0..<2 {
      var completedToolCalls: [OpenAICoachToolCall] = []
      var responseID: String?
      var inFlightToolCalls: [String: OpenAICoachToolCall] = [:]

      let requestBody = OpenAICoachRequestFactory.makeRequest(
        input: input,
        toolMode: toolMode,
        modelPreset: activeModelPreset
      )

      try await client.stream(auth: activeAuth, body: requestBody) { [weak self] event in
        guard let self else {
          return
        }
        try handle(
          event,
          assistantID: assistantID,
          inFlightToolCalls: &inFlightToolCalls,
          completedToolCalls: &completedToolCalls,
          responseID: &responseID
        )
      }

      guard !completedToolCalls.isEmpty else {
        return
      }

      let toolItems = completedToolCalls.flatMap { call -> [[String: Any]] in
        let output = execute(call: call, healthStore: healthStore, appModel: appModel)
        updateToolEvent(id: call.id, in: assistantID) { event in
          event.status = "Returned"
          event.resultSummary = summarizeToolOutput(output)
        }
        return [
          [
            "type": "function_call",
            "id": call.id,
            "call_id": call.callID,
            "name": call.name,
            "arguments": call.arguments.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "{}" : call.arguments,
          ],
          [
            "type": "function_call_output",
            "call_id": call.callID,
            "output": output,
          ],
        ]
      }
      conversationInput.append(contentsOf: toolItems)
      conversationInput.append(OpenAICoachRequestFactory.finalAnswerInput(originalPrompt: prompt))
      input = conversationInput
      toolMode = .none
    }

    if isAssistantTextEmpty(assistantID) {
      throw OpenAIResponsesError.api("Coach returned tool calls but no final reply.")
    }
  }

  private func handle(
    _ event: OpenAIResponseStreamEvent,
    assistantID: UUID,
    inFlightToolCalls: inout [String: OpenAICoachToolCall],
    completedToolCalls: inout [OpenAICoachToolCall],
    responseID: inout String?
  ) throws {
    responseID = responseID ?? responseIDFrom(event.payload)

    switch event.type {
    case "response.created", "response.in_progress":
      responseID = responseID ?? responseIDFrom(event.payload)
    case "response.output_text.delta":
      if let delta = event.payload["delta"] as? String {
        appendAssistantText(delta, to: assistantID)
      }
    case "response.output_text.done":
      guard let text = event.payload["text"] as? String, isAssistantTextEmpty(assistantID) else {
        return
      }
      appendAssistantText(text, to: assistantID)
    case "response.output_item.added":
      guard let item = event.payload["item"] as? [String: Any],
            let call = toolCall(from: item, fallbackID: fallbackToolID(from: event.payload)) else {
        return
      }
      inFlightToolCalls[call.id] = call
      upsertToolEvent(
        CoachToolEvent(
          id: call.id,
          name: call.name,
          status: "Calling",
          arguments: call.arguments,
          resultSummary: nil
        ),
        in: assistantID
      )
    case "response.function_call_arguments.delta":
      let id = fallbackToolID(from: event.payload)
      guard let id, let delta = event.payload["delta"] as? String else {
        return
      }
      var call = inFlightToolCalls[id] ?? OpenAICoachToolCall(id: id, callID: id, name: "function", arguments: "")
      call.arguments += delta
      inFlightToolCalls[id] = call
      updateToolEvent(id: id, in: assistantID) { event in
        event.status = "Preparing"
        event.arguments = call.arguments
      }
    case "response.function_call_arguments.done":
      completeToolCall(
        from: event.payload,
        assistantID: assistantID,
        inFlightToolCalls: &inFlightToolCalls,
        completedToolCalls: &completedToolCalls
      )
    case "response.output_item.done":
      completeToolCall(
        from: event.payload,
        assistantID: assistantID,
        inFlightToolCalls: &inFlightToolCalls,
        completedToolCalls: &completedToolCalls
      )
    case "response.completed":
      responseID = responseIDFrom(event.payload) ?? responseID
    case "response.failed", "error":
      throw OpenAIResponsesError.api(errorMessage(from: event.payload))
    default:
      break
    }
  }

  private func completeToolCall(
    from payload: [String: Any],
    assistantID: UUID,
    inFlightToolCalls: inout [String: OpenAICoachToolCall],
    completedToolCalls: inout [OpenAICoachToolCall]
  ) {
    let fallbackID = fallbackToolID(from: payload)
    let finishedCall: OpenAICoachToolCall?
    if let item = payload["item"] as? [String: Any],
       let itemCall = toolCall(from: item, fallbackID: fallbackID) {
      finishedCall = itemCall
    } else if let fallbackID, var call = inFlightToolCalls[fallbackID] {
      if let arguments = payload["arguments"] as? String {
        call.arguments = arguments
      }
      finishedCall = call
    } else {
      finishedCall = nil
    }

    guard let finishedCall else {
      return
    }
    guard !completedToolCalls.contains(where: { $0.id == finishedCall.id || $0.callID == finishedCall.callID }) else {
      return
    }

    completedToolCalls.append(finishedCall)
    inFlightToolCalls[finishedCall.id] = finishedCall
    upsertToolEvent(
      CoachToolEvent(
        id: finishedCall.id,
        name: finishedCall.name,
        status: "Running",
        arguments: finishedCall.arguments,
        resultSummary: nil
      ),
      in: assistantID
    )
  }

  private func execute(
    call: OpenAICoachToolCall,
    healthStore: HealthDataStore,
    appModel: GooseAppModel
  ) -> String {
    let payload = CoachLocalToolContext.build(healthStore: healthStore, appModel: appModel)
    let tools = payload["tools"] as? [String: Any] ?? [:]
    let output: Any

    switch call.name {
    case "load_stats", "get_activities", "get_capture_sessions", "get_raw_session_data":
      output = tools[call.name] ?? ["error": "tool_not_available", "tool": call.name]
    case "get_data_gaps":
      output = [
        "readiness": healthStore.metricInputReadinessSummary(),
        "input_next_action": healthStore.metricInputReadinessNextActionSummary(),
        "score_next_action": healthStore.packetDerivedScoreNextActionSummary(),
        "packet_inputs": healthStore.packetInputStatus,
        "packet_scores": healthStore.packetScoreStatus,
        "capture": tools["get_capture_sessions"] ?? [:],
      ]
    default:
      output = ["error": "unknown_tool", "tool": call.name]
    }

    return jsonString(output)
  }

  private func appendAssistantText(_ delta: String, to id: UUID) {
    guard let index = messages.firstIndex(where: { $0.id == id }) else {
      return
    }
    messages[index].text += delta
  }

  private func contextualPrompt(for prompt: String) -> String {
    let transcript = recentTranscriptContext(excludingCurrentPrompt: prompt)
    guard !transcript.isEmpty else {
      return prompt
    }
    return """
    Recent Coach conversation context:
    \(transcript)

    Current user message:
    \(prompt)
    """
  }

  private func recentTranscriptContext(excludingCurrentPrompt prompt: String) -> String {
    let turns = messages.compactMap { message -> String? in
      guard !message.isStreaming, !message.isCancelled else {
        return nil
      }
      let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty, text != Self.seedPromptText else {
        return nil
      }
      if message.role == .user, text == prompt {
        return nil
      }
      switch message.role {
      case .user:
        return "User: \(text)"
      case .assistant:
        return "Coach: \(text)"
      }
    }
    return boundedContext(from: turns.suffix(12), maxCharacters: 6_000)
  }

  private func boundedContext<S: Sequence>(from turns: S, maxCharacters: Int) -> String where S.Element == String {
    var selected: [String] = []
    var count = 0
    for turn in Array(turns).reversed() {
      let nextCount = count + turn.count + 2
      guard nextCount <= maxCharacters || selected.isEmpty else {
        break
      }
      selected.append(turn)
      count = nextCount
    }
    return selected.reversed().joined(separator: "\n\n")
  }

  private func isAssistantTextEmpty(_ id: UUID) -> Bool {
    guard let message = messages.first(where: { $0.id == id }) else {
      return true
    }
    return message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private func upsertToolEvent(_ event: CoachToolEvent, in messageID: UUID) {
    guard let messageIndex = messages.firstIndex(where: { $0.id == messageID }) else {
      return
    }
    if let eventIndex = messages[messageIndex].toolEvents.firstIndex(where: { $0.id == event.id }) {
      messages[messageIndex].toolEvents[eventIndex] = event
    } else {
      messages[messageIndex].toolEvents.append(event)
    }
  }

  private func updateToolEvent(
    id: String,
    in messageID: UUID,
    update: (inout CoachToolEvent) -> Void
  ) {
    guard let messageIndex = messages.firstIndex(where: { $0.id == messageID }) else {
      return
    }
    guard let eventIndex = messages[messageIndex].toolEvents.firstIndex(where: { $0.id == id }) else {
      return
    }
    update(&messages[messageIndex].toolEvents[eventIndex])
  }

  private func finishAssistantMessage(_ id: UUID) {
    guard let index = messages.firstIndex(where: { $0.id == id }) else {
      return
    }
    messages[index].isStreaming = false
    if messages[index].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
       messages[index].toolEvents.isEmpty,
       !messages[index].isCancelled {
      messages.remove(at: index)
    }
    persistConversation()
  }

  private func markAssistantMessageCancelled(_ id: UUID) {
    guard let index = messages.firstIndex(where: { $0.id == id }) else {
      return
    }
    messages[index].isStreaming = false
    messages[index].isCancelled = true
    markUnfinishedToolEventsStopped(in: index)
    persistConversation()
  }

  private func cancelStreamingMessages() {
    for index in messages.indices {
      guard messages[index].isStreaming else {
        continue
      }
      messages[index].isStreaming = false
      if messages[index].role == .assistant {
        messages[index].isCancelled = true
        markUnfinishedToolEventsStopped(in: index)
      }
    }
    persistConversation()
  }

  private func markUnfinishedToolEventsStopped(in messageIndex: Int) {
    for eventIndex in messages[messageIndex].toolEvents.indices {
      if messages[messageIndex].toolEvents[eventIndex].status != "Returned" {
        messages[messageIndex].toolEvents[eventIndex].status = "Stopped"
      }
    }
  }

  private func seedAssistantPromptIfNeeded() {
    guard messages.isEmpty else {
      return
    }
    messages.append(
      CoachChatMessage(
        role: .assistant,
        text: Self.seedPromptText
      )
    )
    persistConversation()
  }

  private func toolCall(from item: [String: Any], fallbackID: String?) -> OpenAICoachToolCall? {
    let itemID = item["id"] as? String ?? fallbackID
    let callID = item["call_id"] as? String ?? itemID
    let name = item["name"] as? String ?? (item["function"] as? [String: Any])?["name"] as? String
    let arguments = item["arguments"] as? String ?? (item["function"] as? [String: Any])?["arguments"] as? String ?? ""
    guard let itemID, let callID, let name else {
      return nil
    }
    return OpenAICoachToolCall(id: itemID, callID: callID, name: name, arguments: arguments)
  }

  private func fallbackToolID(from payload: [String: Any]) -> String? {
    payload["item_id"] as? String ??
      payload["call_id"] as? String ??
      (payload["output_index"] as? Int).map { "tool-\($0)" }
  }

  private func responseIDFrom(_ payload: [String: Any]) -> String? {
    if let responseID = payload["response_id"] as? String {
      return responseID
    }
    if let response = payload["response"] as? [String: Any] {
      return response["id"] as? String
    }
    return nil
  }

  private func errorMessage(from payload: [String: Any]) -> String {
    if let error = payload["error"] as? [String: Any] {
      return error["message"] as? String ?? "\(error)"
    }
    return payload["message"] as? String ?? "Coach stream failed."
  }

  private func summarizeToolOutput(_ output: String) -> String {
    let compact = output
      .replacingOccurrences(of: "\n", with: " ")
      .replacingOccurrences(of: "  ", with: " ")
    return String(compact.prefix(180))
  }

  private func jsonString(_ value: Any) -> String {
    guard JSONSerialization.isValidJSONObject(value),
          let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
          let string = String(data: data, encoding: .utf8) else {
      return "{\"error\":\"json_encoding_failed\"}"
    }
    return string
  }

  private func persistConversation() {
    CoachConversationStore.save(messages)
  }

  private func describe(_ error: Error) -> String {
    if isCancelledError(error) {
      return "Generation stopped."
    }
    if let localizedError = error as? LocalizedError, let description = localizedError.errorDescription {
      return description
    }
    return String(describing: error)
  }

  private func isCancelledError(_ error: Error) -> Bool {
    if let urlError = error as? URLError {
      return urlError.code == .cancelled
    }
    let nsError = error as NSError
    return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
  }

  private static func normalizedPersistedMessages(_ storedMessages: [CoachChatMessage]) -> [CoachChatMessage] {
    storedMessages.map { message in
      var normalized = message
      if normalized.isStreaming {
        normalized.isStreaming = false
        normalized.isCancelled = true
      }
      if normalized.isCancelled {
        for index in normalized.toolEvents.indices where normalized.toolEvents[index].status != "Returned" {
          normalized.toolEvents[index].status = "Stopped"
        }
      }
      return normalized
    }
  }
}
