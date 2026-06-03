/// Tracks whether the first-run onboarding flow has been completed.
///
/// Key is `__APP_STATE_onboarding_complete`, identical to Mihon's
/// `BasePreferences.shownOnboardingFlow` (`appStateKey("onboarding_complete")`)
/// — app-state, excluded from backups, so a restored backup never silently
/// re-shows or skips onboarding based on the source device.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String onboardingCompleteKey = '__APP_STATE_onboarding_complete';

/// Reactive flag for whether onboarding is done. Defaults to false until the
/// stored value loads; the cold-start gate reads SharedPreferences directly
/// rather than trusting this default (see OnboardingGate).
class OnboardingCompleteNotifier extends Notifier<bool> {
  @override
  bool build() {
    _load();
    return false;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getBool(onboardingCompleteKey) ?? false;
    if (stored != state) state = stored;
  }

  Future<void> set(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(onboardingCompleteKey, value);
  }
}

final onboardingCompleteProvider =
    NotifierProvider<OnboardingCompleteNotifier, bool>(
  OnboardingCompleteNotifier.new,
);
