import SwiftUI

struct RootView: View {
  @EnvironmentObject private var model: GooseAppModel
  @AppStorage(OnboardingStorage.onboardingComplete) private var onboardingComplete = false
  @AppStorage(OnboardingStorage.onboardingRedoRequested) private var onboardingRedoRequested = false

  var body: some View {
    // Branch `simple`: one screen, no onboarding, no tabs. The sync toast
    // lives inside SimpleAppView's content (in-flow, French, no overlap).
    SimpleAppView()
    .gooseScreenBackground()
    .onAppear {
      mirrorCurrentOnboardingStateIfNeeded()
      restorePersistedOnboardingStateIfNeeded()
      syncModelOnboardingState()
    }
    .onChange(of: onboardingComplete) { _, _ in
      mirrorCurrentOnboardingStateIfNeeded()
      syncModelOnboardingState()
    }
  }

  private func mirrorCurrentOnboardingStateIfNeeded() {
    guard onboardingComplete else {
      return
    }
    OnboardingProfilePersistence.saveProfileFromDefaults(onboardingComplete: true)
  }

  private func restorePersistedOnboardingStateIfNeeded() {
    guard !onboardingComplete, !onboardingRedoRequested else {
      return
    }
    guard
      let state = OnboardingProfilePersistence.restoreIntoDefaultsIfAvailable(restoreCompletion: true),
      state.onboardingComplete
    else {
      return
    }
    onboardingComplete = true
  }

  private func syncModelOnboardingState() {
    guard model.onboardingComplete != onboardingComplete else {
      return
    }
    model.onboardingComplete = onboardingComplete
  }
}

