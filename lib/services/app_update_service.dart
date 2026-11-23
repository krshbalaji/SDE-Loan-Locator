import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

class AppReleaseManifest {
  const AppReleaseManifest({
    required this.latestVersion,
    required this.latestBuild,
    required this.apkUrl,
    this.releaseNotes = '',
  });

  final String latestVersion;
  final int latestBuild;
  final String apkUrl;
  final String releaseNotes;

  factory AppReleaseManifest.fromJson(Map<String, dynamic> json) {
    return AppReleaseManifest(
      latestVersion: (json['latestVersion'] ?? json['version'] ?? '').toString(),
      latestBuild: int.tryParse((json['latestBuild'] ?? json['buildNumber'] ?? '0').toString()) ?? 0,
      apkUrl: (json['apkUrl'] ?? json['url'] ?? '').toString(),
      releaseNotes: (json['releaseNotes'] ?? json['notes'] ?? '').toString(),
    );
  }
}

class ApkUpdateOutcome {
  const ApkUpdateOutcome({
    required this.allowed,
    required this.launched,
    required this.message,
  });

  final bool allowed;
  final bool launched;
  final String message;
}

class AppUpdateService extends ChangeNotifier {
  static const int currentBuildNumber = 1;
  static const String currentVersionName = '1.0.0+1';

  bool _checkedStartup = false;
  bool _isChecking = false;
  bool _updateAvailable = false;
  AppReleaseManifest? _latestManifest;
  String? _lastError;

  bool get isChecking => _isChecking;
  bool get updateAvailable => _updateAvailable;
  AppReleaseManifest? get latestManifest => _latestManifest;
  String? get lastError => _lastError;

  Future<void> checkOnStartup({
    Uri? manifestUri,
    int currentBuild = currentBuildNumber,
  }) async {
    if (_checkedStartup || _isChecking) return;
    _checkedStartup = true;
    await checkForUpdates(manifestUri: manifestUri, currentBuild: currentBuild);
  }

  Future<void> checkForUpdates({
    Uri? manifestUri,
    int currentBuild = currentBuildNumber,
  }) async {
    final targetUri = manifestUri ??
        Uri.parse('https://sde-loan-locator.web.app/version.json');
    _isChecking = true;
    _lastError = null;
    notifyListeners();

    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 6);
      try {
        final request = await client.getUrl(targetUri);
        final response = await request.close().timeout(const Duration(seconds: 8));
        if (response.statusCode == 200) {
          final body = await response.transform(utf8.decoder).join();
          final decoded = jsonDecode(body);
          if (decoded is Map<String, dynamic>) {
            final manifest = AppReleaseManifest.fromJson(decoded);
            _latestManifest = manifest;
            _updateAvailable =
                manifest.latestBuild > currentBuild && manifest.apkUrl.isNotEmpty;
          }
        }
      } finally {
        client.close(force: true);
      }
    } catch (e) {
      _lastError = e.toString();
    } finally {
      _isChecking = false;
      notifyListeners();
    }
  }

  Future<ApkUpdateOutcome> triggerGatedApkUpdate({
    required bool allowApkDownload,
    required bool requireApkApproval,
    String? overrideApkUrl,
  }) async {
    if (!allowApkDownload) {
      return const ApkUpdateOutcome(
        allowed: false,
        launched: false,
        message: 'APK download is disabled by current manual login parameter.',
      );
    }
    if (requireApkApproval) {
      return const ApkUpdateOutcome(
        allowed: false,
        launched: false,
        message: 'Manual approval flag is active for this session; clear approval lock to download APK.',
      );
    }

    final rawUrl = (overrideApkUrl != null && overrideApkUrl.trim().isNotEmpty)
        ? overrideApkUrl.trim()
        : (_latestManifest?.apkUrl ?? 'https://sde-loan-locator.web.app/sde-loan-locator.apk');
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http')) {
      return const ApkUpdateOutcome(
        allowed: true,
        launched: false,
        message: 'Invalid APK download URL.',
      );
    }

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    return ApkUpdateOutcome(
      allowed: true,
      launched: launched,
      message: launched
          ? 'Launching APK update download...'
          : 'Could not open external APK installer.',
    );
  }
}
