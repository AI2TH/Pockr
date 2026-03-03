import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

const _kProjectUrl = 'https://github.com/AI2TH/Pockr';
const _kDownloadUrl = 'https://drive.google.com/drive/folders/1LWLATGacL_hoWuJ4V6S4hUEbBOqTci11?usp=drive_link';
const _kCompany = 'AI2TH';
const _kVersion = '1.0.0';
const _kTagline = 'Docker on Android — no root required';

class _LicenseEntry {
  final String name;
  final String license;
  final String description;
  final String url;
  const _LicenseEntry(this.name, this.license, this.description, this.url);
}

const _licenses = [
  _LicenseEntry(
    'Pockr',
    'MIT',
    'This app is open source. You are free to use, copy, modify, and distribute it '
        'with attribution, without warranty.',
    'https://github.com/AI2TH/Pockr/blob/main/LICENSE',
  ),
  _LicenseEntry(
    'QEMU',
    'GPLv2 (TCG: BSD/Expat)',
    'QEMU runs as a separate subprocess — your app code is not subject to GPLv2. '
        'Distributing QEMU binaries requires including the GPLv2 license text '
        'and making the source code available.',
    'https://wiki.qemu.org/License',
  ),
  _LicenseEntry(
    'Alpine Linux',
    'MIT / various',
    'Minimal Linux distribution used as the VM guest OS inside QEMU.',
    'https://alpinelinux.org',
  ),
  _LicenseEntry(
    'Docker',
    'Apache 2.0',
    'Container runtime installed inside the Alpine VM. '
        'All Docker management goes through the internal API server.',
    'https://www.apache.org/licenses/LICENSE-2.0',
  ),
  _LicenseEntry(
    'Flutter',
    'BSD 3-Clause',
    'UI framework used to build this Android app.',
    'https://flutter.dev',
  ),
];

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _copy(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final secondary = Theme.of(context).colorScheme.secondary;

    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        children: [
          // ── App header ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 36, 24, 28),
            child: Column(
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.25),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.asset(
                    'assets/images/logo.jpeg',
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Pockr',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  _kTagline,
                  style: TextStyle(color: Colors.white60, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: primary.withOpacity(0.3)),
                  ),
                  child: Text(
                    'v$_kVersion',
                    style: TextStyle(
                      color: primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, indent: 16, endIndent: 16),

          // ── Company ─────────────────────────────────────────────────
          _SectionLabel('Company'),
          ListTile(
            leading: const Icon(Icons.business_outlined),
            title: const Text(_kCompany),
            subtitle: const Text('Developer'),
          ),

          const Divider(height: 1, indent: 16, endIndent: 16),

          // ── Project ─────────────────────────────────────────────────
          _SectionLabel('Project'),
          ListTile(
            leading: const Icon(Icons.code_outlined),
            title: const Text('Source Code'),
            subtitle: Text(
              _kProjectUrl.replaceFirst('https://', ''),
              style: const TextStyle(fontSize: 12),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Copy URL',
                  icon: const Icon(Icons.copy_outlined, size: 18),
                  onPressed: () => _copy(context, _kProjectUrl),
                ),
                IconButton(
                  tooltip: 'Open in browser',
                  icon: const Icon(Icons.open_in_new_outlined, size: 18),
                  onPressed: () => _launch(_kProjectUrl),
                ),
              ],
            ),
          ),

          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('Download APK'),
            subtitle: const Text(
              'Google Drive',
              style: TextStyle(fontSize: 12),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Copy URL',
                  icon: const Icon(Icons.copy_outlined, size: 18),
                  onPressed: () => _copy(context, _kDownloadUrl),
                ),
                IconButton(
                  tooltip: 'Open in browser',
                  icon: const Icon(Icons.open_in_new_outlined, size: 18),
                  onPressed: () => _launch(_kDownloadUrl),
                ),
              ],
            ),
          ),

          const Divider(height: 1, indent: 16, endIndent: 16),

          // ── Architecture note ────────────────────────────────────────
          _SectionLabel('How it works'),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Text(
              'Pockr embeds a QEMU virtual machine running Alpine Linux. '
              'Docker runs inside the VM. A FastAPI server inside the VM '
              'exposes a REST API over localhost — no root required.',
              style: TextStyle(color: Colors.white60, fontSize: 13, height: 1.5),
            ),
          ),

          const Divider(height: 1, indent: 16, endIndent: 16),

          // ── Licenses ─────────────────────────────────────────────────
          _SectionLabel('Open Source Licenses'),
          ..._licenses.map(
            (l) => _LicenseTile(entry: l, onLaunch: _launch),
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

// ── Helpers ────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

class _LicenseTile extends StatelessWidget {
  final _LicenseEntry entry;
  final Future<void> Function(String) onLaunch;
  const _LicenseTile({required this.entry, required this.onLaunch});

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context).colorScheme.secondary;
    final primary = Theme.of(context).colorScheme.primary;

    return ExpansionTile(
      leading: const Icon(Icons.article_outlined),
      title: Text(entry.name),
      subtitle: Text(
        entry.license,
        style: TextStyle(color: secondary, fontSize: 12),
      ),
      childrenPadding: const EdgeInsets.fromLTRB(72, 0, 16, 16),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          entry.description,
          style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () => onLaunch(entry.url),
          child: Text(
            entry.url,
            style: TextStyle(
              color: primary,
              fontSize: 12,
              decoration: TextDecoration.underline,
              decorationColor: primary,
            ),
          ),
        ),
      ],
    );
  }
}
