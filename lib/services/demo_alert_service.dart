import 'dart:async';
import 'dart:convert';
import 'dart:io' show ContentType, HttpClient, Platform;

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../models/user_model.dart';
import 'location_service.dart';
import '_demo_alert_sender_stub.dart'
    if (dart.library.js_interop) '_demo_alert_sender_web.dart';

class DemoAlertService {
  DemoAlertService._();

  // Configure via --dart-define=TELEGRAM_BOT_TOKEN=... and --dart-define=TELEGRAM_CHAT_ID=...
  static const String _botToken = String.fromEnvironment(
    'TELEGRAM_BOT_TOKEN',
    defaultValue: '',
  );
  static const String _chatId = String.fromEnvironment(
    'TELEGRAM_CHAT_ID',
    defaultValue: '',
  );

  static bool get isConfigured =>
      _botToken.trim().isNotEmpty && _chatId.trim().isNotEmpty;

  static Future<GeoPointResult> captureStartGeo() async {
    try {
      return await LocationService.getCurrentLocation().timeout(
        const Duration(seconds: 6),
        onTimeout: () => const GeoPointResult(
          latitude: LocationService.defaultLat,
          longitude: LocationService.defaultLng,
          isFallback: true,
          statusMessage: 'GPS timed out — using Madurai HQ fallback',
        ),
      );
    } catch (_) {
      return const GeoPointResult(
        latitude: LocationService.defaultLat,
        longitude: LocationService.defaultLng,
        isFallback: true,
        statusMessage: 'GPS unavailable — using fallback',
      );
    }
  }

  static String formatGeoLabel(GeoPointResult? geo) {
    if (geo == null) return 'Not captured';
    final lat = geo.latitude.toStringAsFixed(5);
    final lng = geo.longitude.toStringAsFixed(5);
    final tag = geo.isFallback ? ' (fallback)' : ' (live GPS)';
    return '$lat, $lng$tag';
  }

  static String mapsUrl(GeoPointResult? geo) {
    final lat = geo?.latitude ?? LocationService.defaultLat;
    final lng = geo?.longitude ?? LocationService.defaultLng;
    return 'https://maps.google.com/?q=$lat,$lng';
  }

  static Future<void> sendInitiationAlert({
    required String testerName,
    required String demoRoleLabel,
    required AppUser roleUser,
    required DateTime startedAt,
    required GeoPointResult geo,
  }) async {
    final ts = DateFormat('dd MMM yyyy, hh:mm a').format(startedAt);
    final msg = [
      '🚀 *SDE-Loan-Locator Demo Started*',
      '• *Tester:* ${_escapeMarkdown(testerName)}',
      '• *Role:* ${_escapeMarkdown(demoRoleLabel)} (${roleUser.role.wireValue})',
      '• *Branch / Zone:* ${_escapeMarkdown(roleUser.branch)} / ${_escapeMarkdown(roleUser.zone)}',
      '• *Time:* $ts',
      '• *Location:* `${formatGeoLabel(geo)}`',
      '• *Map:* [Open Location](${mapsUrl(geo)})',
    ].join('\n');

    await _sendTelegramMessage(msg);
  }

  static Future<void> sendCompletionReport({
    required String testerName,
    required String demoRoleLabel,
    required DateTime startedAt,
    required DateTime endedAt,
    required GeoPointResult? startGeo,
    required List<String> eventLines,
  }) async {
    final duration = endedAt.difference(startedAt);
    final mins = duration.inMinutes;
    final secs = duration.inSeconds.remainder(60);
    final startFmt = DateFormat('hh:mm a').format(startedAt);
    final endFmt = DateFormat('hh:mm a').format(endedAt);

    final boundedEvents = eventLines.length > 35
        ? [
            ...eventLines.take(35),
            '... (${eventLines.length - 35} more event(s) truncated)',
          ]
        : eventLines;

    final eventsBlock = boundedEvents.isEmpty
        ? '  • _No feature actions logged during session_'
        : boundedEvents.map((e) => '  • ${_escapeMarkdown(e)}').join('\n');

    final msg = [
      '📋 *SDE-Loan-Locator Demo Completed*',
      '• *Tester:* ${_escapeMarkdown(testerName)}',
      '• *Role:* ${_escapeMarkdown(demoRoleLabel)}',
      '• *Window:* $startFmt – $endFmt (${mins}m ${secs}s)',
      '• *Start GPS:* `${formatGeoLabel(startGeo)}`',
      '• *Activity Log (${eventLines.length}):*',
      eventsBlock,
    ].join('\n');

    await _sendTelegramMessage(msg);
  }

  static String _escapeMarkdown(String input) {
    return input
        .replaceAll('_', '\\_')
        .replaceAll('*', '\\*')
        .replaceAll('[', '\\[')
        .replaceAll('`', '\\`');
  }

  static Future<void> _sendTelegramMessage(String markdownText) async {
    if (!isConfigured) {
      debugPrint(
        'DemoAlertService skipped: set TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID via --dart-define.',
      );
      return;
    }

    final endpoint = 'https://api.telegram.org/bot$_botToken/sendMessage';
    final payload = jsonEncode(<String, dynamic>{
      'chat_id': _chatId,
      'text': markdownText,
      'parse_mode': 'Markdown',
      'disable_web_page_preview': false,
    });

    try {
      if (kIsWeb) {
        final req = web.XMLHttpRequest();
        req.open('POST', endpoint);
        req.setRequestHeader('Content-Type', 'application/json');
        req.send(payload.toJS);
      } else if (!Platform.environment.containsKey('FLUTTER_TEST')) {
        final client = HttpClient();
        try {
          final request = await client.postUrl(Uri.parse(endpoint));
          request.headers.contentType =
              ContentType('application', 'json', charset: 'utf-8');
          request.write(payload);
          final response = await request.close().timeout(const Duration(seconds: 8));
          await response.drain<void>();
        } finally {
          client.close(force: true);
        }
      }
    } catch (e) {
      debugPrint('DemoAlertService Telegram dispatch error: $e');
    }
  }
}
