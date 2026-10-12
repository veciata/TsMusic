import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:tsmusic/localization/app_localizations.dart';
import 'package:tsmusic/models/scrobble_config.dart';
import 'package:tsmusic/providers/scrobbling_provider.dart';

/// Configures and authorizes scrobbling for ListenBrainz or Last.fm.
class ScrobblingSettingsScreen extends StatefulWidget {
  const ScrobblingSettingsScreen({super.key});

  @override
  State<ScrobblingSettingsScreen> createState() =>
      _ScrobblingSettingsScreenState();
}

class _ScrobblingSettingsScreenState extends State<ScrobblingSettingsScreen> {
  late ScrobblingConfig _config;
  final TextEditingController _listenBrainzToken = TextEditingController();
  final TextEditingController _apiKey = TextEditingController();
  final TextEditingController _secret = TextEditingController();

  String? _pendingToken;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _config = context.read<ScrobblingProvider>().config;
    _listenBrainzToken.text = _config.listenBrainzToken;
    _apiKey.text = _config.lastFmApiKey;
    _secret.text = _config.lastFmSecret;
  }

  @override
  void dispose() {
    _listenBrainzToken.dispose();
    _apiKey.dispose();
    _secret.dispose();
    super.dispose();
  }

  void _setType(ScrobblingProviderType type) {
    setState(() => _config = _config.copyWith(type: type));
  }

  Future<void> _save() async {
    final provider = context.read<ScrobblingProvider>();
    await provider.updateConfig(_config);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).saved)));
  }

  Future<void> _authorizeLastFm() async {
    final l10n = AppLocalizations.of(context);
    final apiKey = _apiKey.text.trim();
    final secret = _secret.text.trim();
    if (apiKey.isEmpty || secret.isEmpty) {
      _showStatus(l10n.lastFmCredentialsRequired, isError: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final auth = context.read<ScrobblingProvider>().service.lastFmAuth();
      final token = await auth.getToken(apiKey: apiKey, secret: secret);
      if (token == null) {
        _showStatus(l10n.lastFmConnectFailed, isError: true);
        return;
      }
      _pendingToken = token;
      await launchUrl(
        auth.authorizeUrl(apiKey: apiKey, token: token),
        mode: LaunchMode.externalApplication,
      );
      _showStatus(l10n.lastFmAuthorizedHint);
    } catch (e) {
      _showStatus(l10n.lastFmConnectFailed, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _completeLastFmAuth() async {
    final l10n = AppLocalizations.of(context);
    final token = _pendingToken;
    final apiKey = _apiKey.text.trim();
    final secret = _secret.text.trim();
    if (token == null || apiKey.isEmpty || secret.isEmpty) {
      _showStatus(l10n.lastFmCredentialsRequired, isError: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final session = await context
          .read<ScrobblingProvider>()
          .service
          .lastFmAuth()
          .getSession(apiKey: apiKey, secret: secret, token: token);
      if (session == null) {
        _showStatus(l10n.lastFmConnectFailed, isError: true);
        return;
      }
      setState(() {
        _config = _config.copyWith(
          lastFmApiKey: apiKey,
          lastFmSecret: secret,
          lastFmSessionKey: session.sessionKey,
          lastFmUsername: session.username,
        );
        _pendingToken = null;
      });
      await _save();
    } catch (e) {
      _showStatus(l10n.lastFmConnectFailed, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showStatus(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final enabled = _config.type != ScrobblingProviderType.disabled;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.scrobbling)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          SwitchListTile(
            title: Text(l10n.enableScrobbling),
            subtitle: Text(l10n.enableScrobblingDescription),
            value: enabled,
            secondary: const Icon(Icons.scatter_plot),
            onChanged: (value) => _setType(
              value
                  ? ScrobblingProviderType.listenBrainz
                  : ScrobblingProviderType.disabled,
            ),
          ),
          if (enabled) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                l10n.scrobblingService,
                style: theme.textTheme.titleSmall,
              ),
            ),
            RadioGroup<ScrobblingProviderType>(
              groupValue: _config.type,
              onChanged: (value) {
                if (value != null) _setType(value);
              },
              child: Column(
                children: [
                  ListTile(
                    title: const Text('ListenBrainz'),
                    leading: const Radio<ScrobblingProviderType>(
                      value: ScrobblingProviderType.listenBrainz,
                    ),
                    onTap: () => _setType(ScrobblingProviderType.listenBrainz),
                  ),
                  ListTile(
                    title: const Text('Last.fm'),
                    leading: const Radio<ScrobblingProviderType>(
                      value: ScrobblingProviderType.lastFm,
                    ),
                    onTap: () => _setType(ScrobblingProviderType.lastFm),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            if (_config.type == ScrobblingProviderType.listenBrainz)
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _listenBrainzToken,
                  decoration: InputDecoration(
                    labelText: l10n.listenBrainzToken,
                    helperText: l10n.listenBrainzTokenHint,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (value) =>
                      _config = _config.copyWith(listenBrainzToken: value),
                ),
              ),
            if (_config.type == ScrobblingProviderType.lastFm)
              _buildLastFmFields(theme, l10n),
          ],
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(l10n.save),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLastFmFields(ThemeData theme, AppLocalizations l10n) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _apiKey,
          decoration: InputDecoration(
            labelText: l10n.lastFmApiKey,
            border: const OutlineInputBorder(),
          ),
          onChanged: (value) => _config = _config.copyWith(lastFmApiKey: value),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _secret,
          decoration: InputDecoration(
            labelText: l10n.lastFmSharedSecret,
            border: const OutlineInputBorder(),
          ),
          onChanged: (value) => _config = _config.copyWith(lastFmSecret: value),
        ),
        const SizedBox(height: 16),
        if (_config.lastFmSessionKey.isNotEmpty)
          Row(
            children: [
              Icon(Icons.check_circle, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _config.lastFmUsername.isEmpty
                      ? l10n.lastFmConnected
                      : '${l10n.lastFmConnected}: ${_config.lastFmUsername}',
                ),
              ),
            ],
          )
        else ...[
          Text(l10n.lastFmAuthorizationHint, style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : _authorizeLastFm,
                  child: Text(l10n.lastFmAuthorize),
                ),
              ),
              if (_pendingToken != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: _busy ? null : _completeLastFmAuth,
                    child: Text(l10n.lastFmCompleteAuth),
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    ),
  );
}
