import 'dart:io';

import 'store.dart';

/// How an option is edited.
enum Kind {
  /// A checkbox.
  boolean,

  /// A whole number within [OptionField.min]..[OptionField.max].
  integer,

  /// Free text; empty removes the key.
  text,

  /// One of [OptionField.choices].
  choice,

  /// Any JSON value, for keys that take several shapes.
  json,
}

/// One key of RxMiner's configuration file, as upstream defines it in
/// `src/config.rs`. Unset keys take [fallback], upstream's default.
class OptionField {
  const OptionField(
    this.path,
    this.label,
    this.kind, {
    this.help = '',
    this.fallback,
    this.min,
    this.max,
    this.choices = const [],
    this.note,
    this.inConfig = true,
  });
  final List<String> path;
  final String label, help;
  final Kind kind;
  final Object? fallback;
  final int? min, max;
  final List<(Object?, String)> choices;

  /// A platform limit or caveat that applies on this system, if any.
  final String? Function()? note;

  /// False for the few options config.json has no key for; the app keeps
  /// those in its own settings.
  final bool inConfig;

  String get key => path.join('.');

  String describe(Object? value) {
    if (kind == Kind.choice) {
      for (final (v, label) in choices) {
        if (v == value) return label;
      }
    }
    return switch (value) {
      null => 'Not set',
      true => 'On',
      false => 'Off',
      String s when s.isEmpty => 'Empty',
      _ => '$value',
    };
  }
}

/// A titled group of fields.
class OptionSection {
  const OptionSection(this.title, this.fields, {this.intro});
  final String title;
  final String? intro;
  final List<OptionField> fields;
}

Object? readPath(Map<String, Object?> map, List<String> path) {
  Object? value = map;
  for (final part in path) {
    if (value is! Map) return null;
    value = value[part];
  }
  return value;
}

/// Sets or, for null, removes the key; empty parent sections are dropped.
void writePath(Map<String, Object?> map, List<String> path, Object? value) {
  if (path.length == 1) {
    value == null ? map.remove(path.first) : map[path.first] = value;
    return;
  }
  final child = map[path.first];
  final section = child is Map
      ? child.cast<String, Object?>()
      : <String, Object?>{};
  writePath(section, path.sublist(1), value);
  section.isEmpty && value == null
      ? map.remove(path.first)
      : map[path.first] = section;
}

String? _linuxOnly() =>
    Platform.isLinux ? null : 'Linux only. The miner rejects it here.';
String? _linuxX64Only() => Platform.isLinux
    ? null
    : 'Linux on x86-64 only. The miner rejects it elsewhere.';
String? _notWindows() =>
    Platform.isWindows ? 'Not available on Windows.' : null;
String? _noEffect() =>
    'The app runs the miner in its own process, so this has no effect here.';
String? _iosJit() => jitAllowed
    ? null
    : 'iOS forbids executable memory; the app always turns this off.';

const _priorities = [
  (null, 'Not set'),
  (0, '0, idle'),
  (1, '1, lowest'),
  (2, '2, below normal'),
  (3, '3, normal'),
  (4, '4, above normal'),
  (5, '5, highest'),
];

/// Every configuration key RxMiner accepts, except those upstream rejects
/// unless left at their default (cpu.enabled, randomx.cache_qos, pools[].daemon,
/// pools[].self-select and pools[].submit-to-origin).
final configSections = <OptionSection>[
  const OptionSection('CPU', [
    OptionField(
      ['cpu', 'max-threads-hint'],
      'Thread limit, percent of CPUs',
      Kind.integer,
      fallback: 100,
      min: 1,
      max: 100,
      help: 'Caps the automatic thread count. A thread profile ignores it.',
    ),
    OptionField(
      ['cpu', 'rx'],
      'Thread profile',
      Kind.json,
      help:
          'Worker threads and CPU binding. {"threads": 4} runs four; '
          '{"threads": 4, "affinity": "0xF"} pins them to CPUs 0 to 3; '
          '[0, 2, 4, -1] lists CPU IDs, -1 unpinned. Unset picks physical cores.',
    ),
    OptionField(
      ['cpu', 'huge-pages'],
      'Huge pages',
      Kind.boolean,
      fallback: true,
      help: 'Prefers 2 MiB pages, falling back to ordinary pages.',
    ),
    OptionField(
      ['cpu', 'huge-pages-jit'],
      'Huge pages for JIT code',
      Kind.boolean,
      fallback: false,
    ),
    OptionField(
      ['cpu', 'memory-pool'],
      'Scratchpad pool',
      Kind.json,
      fallback: false,
      help: 'false, true for one page per worker, or a page count up to 1024.',
    ),
    OptionField(
      ['cpu', 'hw-aes'],
      'Hardware AES',
      Kind.choice,
      choices: [(null, 'Detect'), (true, 'Force on'), (false, 'Force off')],
    ),
    OptionField(
      ['cpu', 'priority'],
      'Thread priority',
      Kind.choice,
      choices: _priorities,
    ),
    OptionField(
      ['cpu', 'yield'],
      'Yield between hashes',
      Kind.boolean,
      fallback: true,
    ),
    OptionField(
      ['cpu', 'argon2-impl'],
      'Argon2 cache kernel',
      Kind.choice,
      choices: [
        (null, 'Detect'),
        ('x86_64', 'x86_64'),
        ('SSSE3', 'SSSE3'),
        ('AVX2', 'AVX2'),
      ],
    ),
    OptionField(
      ['cpu', 'smt'],
      'Use SMT siblings',
      Kind.boolean,
      fallback: false,
      help: 'Includes hyper-threads in the automatic selection.',
    ),
    OptionField(
      ['cpu', 'thp'],
      'Transparent huge-page hints',
      Kind.boolean,
      fallback: true,
    ),
  ]),
  OptionSection('RandomX', [
    const OptionField(
      ['randomx', 'mode'],
      'Memory mode',
      Kind.choice,
      fallback: 'auto',
      choices: [
        ('auto', 'Automatic'),
        ('fast', 'Fast, 2.3 GiB dataset'),
        ('light', 'Light, 256 MiB cache'),
      ],
    ),
    OptionField(
      ['randomx', 'jit'],
      'JIT compiler',
      Kind.boolean,
      fallback: true,
      note: _iosJit,
    ),
    const OptionField(
      ['randomx', 'secure'],
      'Secure JIT',
      Kind.boolean,
      fallback: false,
      help: 'Never keeps JIT pages writable and executable at once. Slower.',
    ),
    const OptionField(
      ['randomx', 'init'],
      'Dataset initialization threads',
      Kind.integer,
      fallback: -1,
      min: -1,
      max: 1024,
      help: '-1 for automatic, 0 for the worker threads, or a count.',
    ),
    const OptionField(
      ['randomx', 'init-avx2'],
      'AVX2 dataset initialization',
      Kind.choice,
      fallback: -1,
      choices: [(-1, 'Automatic'), (0, 'Off')],
    ),
    OptionField(
      ['randomx', 'scratchpad_prefetch_mode'],
      'Scratchpad prefetch mode',
      Kind.choice,
      fallback: 1,
      choices: const [(0, '0, off'), (1, '1'), (2, '2'), (3, '3')],
      note: () => Platform.version.contains('x64')
          ? null
          : 'Modes other than 1 need the x86-64 JIT.',
    ),
    const OptionField(
      ['randomx', 'numa'],
      'One dataset per NUMA node',
      Kind.boolean,
      fallback: true,
    ),
    OptionField(
      ['randomx', '1gb-pages'],
      '1 GiB pages',
      Kind.boolean,
      fallback: false,
      note: _linuxOnly,
    ),
    OptionField(
      ['randomx', 'wrmsr'],
      'MSR tuning',
      Kind.json,
      fallback: false,
      help: 'false, true for the CPU preset, or a list of register writes.',
      note: _linuxX64Only,
    ),
    const OptionField(
      ['randomx', 'rdmsr'],
      'Restore MSRs on exit',
      Kind.boolean,
      fallback: true,
    ),
  ]),
  OptionSection('Connection', [
    const OptionField(
      ['retries'],
      'Retries per pool',
      Kind.integer,
      fallback: 5,
      min: 1,
      max: 1000,
    ),
    const OptionField(
      ['retry-pause'],
      'Pause between retries, seconds',
      Kind.integer,
      fallback: 5,
      min: 0,
      max: 86400,
    ),
    const OptionField(
      ['user-agent'],
      'User agent',
      Kind.text,
      help: 'Sent to pools at login. Unset sends RxMiner/<version>.',
    ),
    const OptionField(
      ['dns', 'ip_version'],
      'DNS address family',
      Kind.choice,
      fallback: 0,
      choices: [(0, 'Any'), (4, 'IPv4 only'), (6, 'IPv6 only')],
    ),
    const OptionField(
      ['dns', 'ttl'],
      'DNS cache, seconds',
      Kind.integer,
      fallback: 30,
      min: 0,
      max: 86400,
    ),
  ]),
  const OptionSection(
    'HTTP API',
    intro:
        'Off: the app runs a private API on 127.0.0.1 with a new token each '
        'session. On: the miner serves these settings, and the app reads the '
        'same API. Pause and resume need restricted off and a token.',
    [
      OptionField(
        ['http', 'enabled'],
        'Enabled',
        Kind.boolean,
        fallback: false,
      ),
      OptionField(
        ['http', 'host'],
        'Listen address',
        Kind.text,
        fallback: '127.0.0.1',
        help: '0.0.0.0 makes the API reachable from other devices.',
      ),
      OptionField(
        ['http', 'port'],
        'Port',
        Kind.integer,
        fallback: 0,
        min: 0,
        max: 65535,
      ),
      OptionField(['http', 'access-token'], 'Access token', Kind.text),
      OptionField(
        ['http', 'restricted'],
        'Read only',
        Kind.boolean,
        fallback: true,
      ),
    ],
  ),
  const OptionSection('HTTP API TLS', [
    OptionField(
      ['tls', 'enabled'],
      'Serve over TLS',
      Kind.boolean,
      fallback: false,
    ),
    OptionField(['tls', 'cert'], 'Certificate file', Kind.text),
    OptionField(['tls', 'cert_key'], 'Private key file', Kind.text),
    OptionField(['tls', 'protocols'], 'Protocols', Kind.text),
    OptionField(['tls', 'ciphers'], 'TLS 1.2 ciphers', Kind.text),
    OptionField(['tls', 'ciphersuites'], 'TLS 1.3 cipher suites', Kind.text),
    OptionField(['tls', 'dhparam'], 'DH parameters file', Kind.text),
  ]),
  OptionSection('Logging and runtime', [
    const OptionField(
      ['print-time'],
      'Hashrate line every, seconds',
      Kind.integer,
      fallback: 60,
      min: 0,
      max: 86400,
    ),
    const OptionField(
      ['health-print-time'],
      'Health line every, seconds',
      Kind.integer,
      fallback: 60,
      min: 0,
      max: 86400,
    ),
    const OptionField(
      ['verbose'],
      'Verbose',
      Kind.choice,
      fallback: 0,
      choices: [(0, 'Off'), (1, 'On')],
    ),
    const OptionField(
      ['log-file'],
      'Log file',
      Kind.text,
      help: 'Unset: the app keeps its own log. Set: the Log tab follows this file.',
    ),
    OptionField(
      ['syslog'],
      'Syslog',
      Kind.boolean,
      fallback: false,
      note: _notWindows,
    ),
    const OptionField(
      ['colors'],
      'Colours on a terminal',
      Kind.boolean,
      fallback: true,
    ),
    const OptionField(
      ['watch'],
      'Reload on save',
      Kind.boolean,
      fallback: true,
      help: 'Saving while mining restarts the workers with the new file.',
    ),
    const OptionField(
      ['autosave'],
      'Save the chosen CPU profile',
      Kind.boolean,
      fallback: true,
      help: 'Writes the selected CPUs back to cpu.rx at start.',
    ),
    OptionField(
      ['pause-on-battery'],
      'Pause on battery',
      Kind.boolean,
      fallback: false,
      note: _linuxOnly,
    ),
    OptionField(
      ['background'],
      'Background mode',
      Kind.boolean,
      fallback: false,
      note: _noEffect,
    ),
  ]),
  const OptionSection(
    'Benchmark',
    intro:
        'Setting a size or duration makes Start run an offline benchmark '
        'instead of mining. The Benchmark button ignores these.',
    [
      OptionField(
        ['benchmark', 'size'],
        'Hash count',
        Kind.choice,
        choices: [
          (null, 'Not set'),
          ('250K', '250K'),
          ('500K', '500K'),
          ('1M', '1M'),
          ('2M', '2M'),
          ('3M', '3M'),
          ('4M', '4M'),
          ('5M', '5M'),
          ('6M', '6M'),
          ('7M', '7M'),
          ('8M', '8M'),
          ('9M', '9M'),
          ('10M', '10M'),
        ],
      ),
      OptionField(
        ['benchmark', 'seconds'],
        'Duration, seconds',
        Kind.integer,
        min: 1,
        max: 86400,
      ),
      OptionField(
        ['benchmark', 'seed'],
        'Seed',
        Kind.text,
        help: '64 hexadecimal digits. Unset uses zeros.',
      ),
      OptionField(
        ['benchmark', 'hash'],
        'Expected checksum',
        Kind.text,
        help: '16 hexadecimal digits; needs a hash count.',
      ),
      OptionField(
        ['benchmark', 'algo'],
        'Algorithm',
        Kind.choice,
        choices: [(null, 'Not set'), ('rx/0', 'rx/0')],
      ),
    ],
  ),
];

/// Options for every pool that config.json cannot hold.
const proxyFields = <OptionField>[
  OptionField(
    ['proxy'],
    'Proxy for every pool',
    Kind.text,
    help:
        'SOCKS5 host:port or an http:// CONNECT URL. Unlike a pool’s own '
        'SOCKS5 proxy, it also carries the developer-fee connections.',
    inConfig: false,
  ),
  OptionField(
    ['no-proxy'],
    'Ignore proxy environment variables',
    Kind.boolean,
    fallback: false,
    help: 'ALL_PROXY and HTTPS_PROXY are not used.',
    inConfig: false,
  ),
];

/// Every key of one `pools[]` entry, except daemon and self-select modes.
const poolFields = <OptionField>[
  OptionField(
    ['url'],
    'Pool address',
    Kind.text,
    help: 'host:port, or stratum+tcp:// and stratum+ssl:// URLs.',
  ),
  OptionField(['user'], 'Wallet address or user', Kind.text),
  OptionField(['pass'], 'Password', Kind.text, fallback: 'x'),
  OptionField(['rig-id'], 'Worker name', Kind.text),
  OptionField(['enabled'], 'Enabled', Kind.boolean, fallback: true),
  OptionField(
    ['tls'],
    'Use TLS',
    Kind.boolean,
    fallback: false,
    help: 'Also on when the address starts with stratum+ssl://.',
  ),
  OptionField(
    ['tls-verify'],
    'Verify the certificate',
    Kind.boolean,
    fallback: false,
    help: 'Against this system’s trusted roots, or the CA file below.',
  ),
  OptionField(
    ['tls-fingerprint'],
    'Certificate SHA-256 fingerprint',
    Kind.text,
    help: '64 hexadecimal digits; colons are allowed.',
  ),
  OptionField(['tls-ca'], 'CA certificate file', Kind.text),
  OptionField(
    ['socks5'],
    'SOCKS5 proxy',
    Kind.text,
    help:
        'host:port. The proxy for every pool, under Connection, overrides it.',
  ),
  OptionField(
    ['keepalive'],
    'Keepalive',
    Kind.json,
    help: 'null for automatic, true for 60 seconds, false, or seconds.',
  ),
  OptionField(
    ['nicehash'],
    'NiceHash nonce mode',
    Kind.boolean,
    fallback: false,
  ),
  OptionField(
    ['algo'],
    'Algorithm',
    Kind.choice,
    choices: [(null, 'Not set'), ('rx/0', 'rx/0')],
  ),
  OptionField(
    ['coin'],
    'Coin',
    Kind.choice,
    choices: [(null, 'Not set'), ('monero', 'monero')],
  ),
];
