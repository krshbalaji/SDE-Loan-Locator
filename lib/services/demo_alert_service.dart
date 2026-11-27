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

  // Configure via --dart-define=TELEGRAM_RELAY_URL=... (recommended) or direct token/chat ID
  static const String _relayUrl = String.fromEnvironment(
    'TELEGRAM_RELAY_URL',
    defaultValue: '',
  );
  static const String _botToken = String.fromEnvironment(
    'TELEGRAM_BOT_TOKEN',
    defaultValue: '',
  );
  static const String _chatId = String.fromEnvironment(
    'TELEGRAM_CHAT_ID',
    defaultValue: '',
  );

  static bool get _hasRelay => _relayUrl.trim().isNotEmpty;
  static bool get _hasDirectBot =>
      _botToken.trim().isNotEmpty && _chatId.trim().isNotEmpty;

  static bool get isConfigured => _hasRelay || _hasDirectBot;

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
        'DemoAlertService skipped: set TELEGRAM_RELAY_URL (or TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID) via --dart-define.',
      );
      return;
    }

    final String endpoint;
    final String payload;
    if (_hasRelay) {
      endpoint = _relayUrl.trim();
      payload = jsonEncode(<String, dynamic>{
        'text': markdownText,
        'parse_mode': 'Markdown',
        'disable_web_page_preview': false,
      });
    } else {
      endpoint = 'https://api.telegram.org/bot${_botToken.trim()}/sendMessage';
      payload = jsonEncode(<String, dynamic>{
        'chat_id': _chatId.trim(),
        'text': markdownText,
        'parse_mode': 'Markdown',
        'disable_web_page_preview': false,
      });
    }

    try {
      if (kIsWeb) {
        await sendWebRelayPost(endpoint, payload);
      } else if (!Platform.environment.containsKey('FLUTTER_TEST')) {
        final client = HttpClient();
        try {
          var currentUri = Uri.parse(endpoint);
          var useGet = false;
          for (var hop = 0; hop < 5; hop++) {
            final request = useGet
                ? await client.getUrl(currentUri)
                : await client.postUrl(currentUri);
            request.followRedirects = false;
            if (!useGet) {
              request.headers.contentType =
                  ContentType('application', 'json', charset: 'utf-8');
              request.write(payload);
            }
            final response =
                await request.close().timeout(const Duration(seconds: 10));
            final bodyText = await response.transform(utf8.decoder).join();
            if (response.statusCode >= 300 && response.statusCode < 400) {
              final loc = response.headers.value('location');
              if (loc != null && loc.isNotEmpty) {
                currentUri = currentUri.resolve(loc);
                if (response.statusCode == 301 ||
                    response.statusCode == 302 ||
                    response.statusCode == 303) {
                  useGet = true;
                }
                continue;
              }
            }
            if (response.statusCode < 200 || response.statusCode >= 300) {
              debugPrint(
                'DemoAlertService HTTP ${response.statusCode}: $bodyText',
              );
            }
            break;
          }
        } finally {
          client.close(force: true);
        }
      }
    } catch (e) {
      debugPrint('DemoAlertService Telegram dispatch error: $e');
    }
  }
}
