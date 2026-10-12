/// Which scrobbling service the user has enabled.
enum ScrobblingProviderType { disabled, listenBrainz, lastFm }

/// Persisted scrobbling configuration.
///
/// ListenBrainz only needs a user token. Last.fm needs an API key and shared
/// secret (registered by the user at
/// https://www.last.fm/api/account/create) plus a session key obtained through
/// the authorization flow.
class ScrobblingConfig {
  const ScrobblingConfig({
    this.type = ScrobblingProviderType.disabled,
    this.listenBrainzToken = '',
    this.lastFmApiKey = '',
    this.lastFmSecret = '',
    this.lastFmSessionKey = '',
    this.lastFmUsername = '',
  });

  final ScrobblingProviderType type;
  final String listenBrainzToken;
  final String lastFmApiKey;
  final String lastFmSecret;
  final String lastFmSessionKey;
  final String lastFmUsername;

  bool get isEnabled => type != ScrobblingProviderType.disabled;

  /// True when the selected service has everything it needs to submit.
  bool get isConfigured {
    switch (type) {
      case ScrobblingProviderType.disabled:
        return false;
      case ScrobblingProviderType.listenBrainz:
        return listenBrainzToken.trim().isNotEmpty;
      case ScrobblingProviderType.lastFm:
        return lastFmApiKey.trim().isNotEmpty &&
            lastFmSecret.trim().isNotEmpty &&
            lastFmSessionKey.trim().isNotEmpty;
    }
  }

  ScrobblingConfig copyWith({
    ScrobblingProviderType? type,
    String? listenBrainzToken,
    String? lastFmApiKey,
    String? lastFmSecret,
    String? lastFmSessionKey,
    String? lastFmUsername,
  }) => ScrobblingConfig(
    type: type ?? this.type,
    listenBrainzToken: listenBrainzToken ?? this.listenBrainzToken,
    lastFmApiKey: lastFmApiKey ?? this.lastFmApiKey,
    lastFmSecret: lastFmSecret ?? this.lastFmSecret,
    lastFmSessionKey: lastFmSessionKey ?? this.lastFmSessionKey,
    lastFmUsername: lastFmUsername ?? this.lastFmUsername,
  );

  Map<String, dynamic> toMap() => {
    'type': type.name,
    'listenBrainzToken': listenBrainzToken,
    'lastFmApiKey': lastFmApiKey,
    'lastFmSecret': lastFmSecret,
    'lastFmSessionKey': lastFmSessionKey,
    'lastFmUsername': lastFmUsername,
  };

  factory ScrobblingConfig.fromMap(Map<String, dynamic> map) =>
      ScrobblingConfig(
        type: ScrobblingProviderType.values.firstWhere(
          (value) => value.name == map['type'],
          orElse: () => ScrobblingProviderType.disabled,
        ),
        listenBrainzToken: map['listenBrainzToken'] as String? ?? '',
        lastFmApiKey: map['lastFmApiKey'] as String? ?? '',
        lastFmSecret: map['lastFmSecret'] as String? ?? '',
        lastFmSessionKey: map['lastFmSessionKey'] as String? ?? '',
        lastFmUsername: map['lastFmUsername'] as String? ?? '',
      );
}
