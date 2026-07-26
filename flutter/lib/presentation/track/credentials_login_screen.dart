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
      body: Stack(
        children: [
          const TideAurora(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TideHeader(title: widget.title),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                  children: [
                    if (widget.helperText != null) ...[
                      Text(widget.helperText!, style: TideText.body()),
                      const SizedBox(height: 22),
                    ],
                    if (widget.includeServerUrl) ...[
                      TideField(
                        controller: _server,
                        label: widget.serverUrlLabel,
                        hintText: widget.serverUrlHint,
                        icon: Icons.dns_outlined,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 18),
                    ],
                    TideField(
                      controller: _user,
                      label: widget.usernameLabel,
                      icon: Icons.person_outline,
                      autocorrect: false,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 18),
                    TideField(
                      controller: _pass,
                      label: widget.passwordLabel,
                      icon: Icons.lock_outline,
                      obscureText: _obscure,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                      trailing: TideIconButton(
                        icon: _obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        onTap: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    const SizedBox(height: 30),
                    TideButton(
                      label: 'Log in',
                      primary: true,
                      onTap: _submit,
                    ),
                    const SizedBox(height: 10),
                    TideButton(
                      label: 'Cancel',
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
