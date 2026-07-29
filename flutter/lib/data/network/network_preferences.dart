/// Network / advanced preferences mirroring Mihon's `NetworkPreferences.kt`.
/// Keys match the Kotlin app verbatim for settings-import parity.
///
/// [dohProviderProvider] selects a DNS-over-HTTPS provider by integer id
/// (-1 = off). [verboseLoggingProvider] toggles verbose HTTP logging. Both
/// require an app restart to take effect in Mihon.
library;

import '../preferences/typed_preferences.dart';

/// DoH provider ids — identical to Mihon's `PREF_DOH_*` constants in
/// `DohProviders.kt`. `-1` means DoH is disabled.
const dohOff = -1;
const dohCloudflare = 1;
const dohGoogle = 2;
const dohAdGuard = 3;
const dohQuad9 = 4;
const dohAliDns = 5;
const dohDnsPod = 6;
const doh360 = 7;
const dohQuad101 = 8;
const dohMullvad = 9;
const dohControlD = 10;
const dohNjalla = 11;
const dohShecan = 12;

/// Display labels keyed by provider id, in Mihon's menu order.
const dohProviderLabels = <int, String>{
  dohOff: 'Disabled',
  dohCloudflare: 'Cloudflare',
  dohGoogle: 'Google',
  dohAdGuard: 'AdGuard',
  dohQuad9: 'Quad9',
  dohAliDns: 'AliDNS',
  dohDnsPod: 'DNSPod',
  doh360: '360',
  dohQuad101: 'Quad 101',
  dohMullvad: 'Mullvad',
  dohControlD: 'Control D',
  dohNjalla: 'Njalla',
  dohShecan: 'Shecan',
};

/// SharedPreferences keys (Mihon-identical).
const dohProviderKey = 'doh_provider';
const verboseLoggingKey = 'verbose_logging';

/// Default `User-Agent` — verbatim Mihon `NetworkPreferences.default_user_agent`
/// default value. Cloudflare's `cf_clearance` cookie is bound to the exact
/// User-Agent that solved the challenge, so the shared Dio client AND every
/// challenge-solving WebView must send this identical string; otherwise the
/// harvested clearance cookie is rejected and the source stays blocked.
const defaultUserAgent =
    'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/141.0.0.0 Mobile Safari/537.36';

// No provider for `doh_provider`: nothing applies a DoH resolver yet (the
// plan lives in the `TODO(doh)` in `AppHttpClient._create()`). The ids, the
// [dohProviderLabels] table and [dohProviderKey] are kept for that work; what
// is deliberately absent is the settings picker, which would otherwise let
// someone choose a provider and believe their lookups were private.

/// Verbose HTTP logging toggle. Mihon key `verbose_logging`. Read by
/// `AppHttpClient._create()`, which attaches a header-level Dio
/// `LogInterceptor` when set — mirroring Kotlin `NetworkHelper`. Sampled once
/// as the shared client is built, so a change lands on the next restart.
final verboseLoggingProvider = boolPref(verboseLoggingKey, false);
