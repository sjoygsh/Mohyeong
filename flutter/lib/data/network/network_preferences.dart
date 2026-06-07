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

/// Selected DoH provider id. Mihon key `doh_provider`, default -1 (off).
final dohProviderProvider = intPref(dohProviderKey, dohOff);

/// Verbose HTTP logging toggle. Mihon key `verbose_logging`.
final verboseLoggingProvider = boolPref(verboseLoggingKey, false);
