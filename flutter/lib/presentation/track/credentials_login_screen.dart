import 'package:flutter/material.dart';

import '../tide/tide.dart';

/// Result of a username/password login dialog. `null` indicates the user
/// cancelled. Empty values are not filtered — the caller decides which
/// fields are required.
class CredentialsLoginResult {
  const CredentialsLoginResult({
    required this.username,
    required this.password,
    this.serverUrl,
  });

  final String username;
  final String password;

  /// Only populated when the tracker requested a server URL field
  /// (Komga, Suwayomi). Null for cloud trackers (MangaUpdates).
  final String? serverUrl;
}

/// Modal username/password login form. Pushed by trackers that don't
/// support OAuth (MangaUpdates, Komga, Suwayomi) — surfaced through the
/// shared navigator key registered with [MaterialApp].
///
/// The widget is intentionally stateless about success vs failure: the
/// tracker pops it with a [CredentialsLoginResult] on submit, or null on
/// cancel.
class CredentialsLoginScreen extends StatefulWidget {
  const CredentialsLoginScreen({
    super.key,
    required this.title,
    this.usernameLabel = 'Username',
    this.passwordLabel = 'Password',
    this.includeServerUrl = false,
    this.serverUrlLabel = 'Server URL',
    this.serverUrlHint,
    this.helperText,
  });

  final String title;
  final String usernameLabel;
  final String passwordLabel;
  final bool includeServerUrl;
  final String serverUrlLabel;
  final String? serverUrlHint;
  final String? helperText;

  @override
  State<CredentialsLoginScreen> createState() => _CredentialsLoginScreenState();
}

class _CredentialsLoginScreenState extends State<CredentialsLoginScreen> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _server = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    _server.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(
      CredentialsLoginResult(
        username: _user.text.trim(),
        password: _pass.text,
        serverUrl: widget.includeServerUrl ? _server.text.trim() : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TideColors.ground,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TideHeader(title: widget.title),
          Expanded(child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: ListView(
          children: [
            if (widget.helperText != null) ...[
              Text(
                widget.helperText!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
            ],
            if (widget.includeServerUrl) ...[
              TextField(
                controller: _server,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: widget.serverUrlLabel,
                  hintText: widget.serverUrlHint,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _user,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: widget.usernameLabel,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pass,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: widget.passwordLabel,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _submit,
              child: const Text('Log in'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      )),
        ],
      ),
    );
  }
}
