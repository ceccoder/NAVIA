import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// Models information about the latest available release from GitHub.
class AppReleaseInfo {
  final String tagName;
  final String name;
  final String releaseNotes;
  final String downloadUrl;
  final DateTime publishedAt;

  const AppReleaseInfo({
    required this.tagName,
    required this.name,
    required this.releaseNotes,
    required this.downloadUrl,
    required this.publishedAt,
  });

  factory AppReleaseInfo.fromJson(Map<String, dynamic> json) {
    String apkUrl = '';
    final assets = json['assets'] as List<dynamic>? ?? [];
    for (final asset in assets) {
      final name = (asset['name'] as String? ?? '').toLowerCase();
      if (name.endsWith('.apk')) {
        apkUrl = asset['browser_download_url'] as String? ?? '';
        break;
      }
    }

    if (apkUrl.isEmpty) {
      apkUrl = json['html_url'] as String? ?? '';
    }

    return AppReleaseInfo(
      tagName: json['tag_name'] as String? ?? 'v1.0.0',
      name: json['name'] as String? ?? 'Update',
      releaseNotes: json['body'] as String? ?? 'Performance improvements and bug fixes.',
      downloadUrl: apkUrl,
      publishedAt: DateTime.tryParse(json['published_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

/// Service managing Over-The-Air (OTA) in-app updates via GitHub Releases API.
class UpdateService {
  static const String currentVersion = '1.0.0';
  static const String repoOwner = 'ceccoder';
  static const String repoName = 'NAVIA';

  /// Checks GitHub API for newer releases
  static Future<AppReleaseInfo?> checkForUpdate() async {
    try {
      final url = Uri.parse('https://api.github.com/repos/$repoOwner/$repoName/releases/latest');
      final response = await http.get(url, headers: {
        'Accept': 'application/vnd.github.v3+json',
      }).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final latest = AppReleaseInfo.fromJson(data);
        
        // Compare versions (clean 'v' prefix if present)
        final latestVer = latest.tagName.replaceAll(RegExp(r'[^0-9.]'), '');
        final currentVer = currentVersion.replaceAll(RegExp(r'[^0-9.]'), '');

        if (_isVersionNewer(latestVer, currentVer)) {
          return latest;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static bool _isVersionNewer(String latest, String current) {
    try {
      final lParts = latest.split('.').map(int.parse).toList();
      final cParts = current.split('.').map(int.parse).toList();
      for (int i = 0; i < lParts.length && i < cParts.length; i++) {
        if (lParts[i] > cParts[i]) return true;
        if (lParts[i] < cParts[i]) return false;
      }
      return lParts.length > cParts.length;
    } catch (_) {
      return latest != current;
    }
  }

  /// Launches direct download of the APK or GitHub release in browser
  static Future<bool> startDownload(String url) async {
    try {
      final uri = Uri.parse(url);
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  /// Displays a styled, accessible update dialog
  static void showUpdateDialog(BuildContext context, AppReleaseInfo release, {bool isManual = false}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFF38BDF8), width: 1.5),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF38BDF8).withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.system_update_rounded, color: Color(0xFF38BDF8), size: 28),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Update Available',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Version ${release.tagName}',
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'What\'s New:',
              style: TextStyle(color: Color(0xFFE2E8F0), fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 6),
            Container(
              constraints: const BoxConstraints(maxHeight: 120),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(10),
              ),
              child: SingleChildScrollView(
                child: Text(
                  release.releaseNotes,
                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Downloading will update NAVIA directly without losing your settings.',
              style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Later', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF38BDF8),
              foregroundColor: const Color(0xFF0F172A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('Update Now', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () {
              Navigator.of(ctx).pop();
              startDownload(release.downloadUrl);
            },
          ),
        ],
      ),
    );
  }
}
