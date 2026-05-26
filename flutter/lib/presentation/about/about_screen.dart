import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// About / version info. Mirrors the Kotlin AboutScreen layout: app
/// name, version, and a few external links.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const _repoUrl = 'https://github.com/sjoygsh/Mohyeong';
  static const _licenseUrl =
      'https://github.com/sjoygsh/Mohyeong/blob/main/LICENSE';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: FutureBuilder<PackageInfo>(
        future: PackageInfo.fromPlatform(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final info = snap.data!;
          return ListView(
            children: [
              const SizedBox(height: 24),
              Center(
                child: Icon(
                  Icons.menu_book,
                  size: 72,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  info.appName.isEmpty ? 'Mohyeong' : info.appName,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  'v${info.version} (${info.buildNumber})',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const SizedBox(height: 24),
              ListTile(
                leading: const Icon(Icons.code),
                title: const Text('Source code'),
                subtitle: const Text(_repoUrl),
                onTap: () => _open(_repoUrl),
              ),
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: const Text('License'),
                onTap: () => _open(_licenseUrl),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
