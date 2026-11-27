import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

Future<void> sendWebRelayPost(String endpoint, String payload) async {
  final completer = Completer<void>();
  final req = web.XMLHttpRequest();
  req.open('POST', endpoint);
  req.setRequestHeader('Content-Type', 'text/plain;charset=UTF-8');

  void finish(String statusLabel) {
    debugPrint('$statusLabel: HTTP ${req.status}');
    if (!completer.isCompleted) completer.complete();
  }

  req.addEventListener(
    'loadend',
    ((web.Event _) => finish('DemoAlertService Web loadend')).toJS,
  );
  req.addEventListener(
    'error',
    ((web.Event _) => finish('DemoAlertService Web XHR/CORS error')).toJS,
  );

  req.send(payload.toJS);
  await completer.future.timeout(
    const Duration(seconds: 8),
    onTimeout: () {
      if (!completer.isCompleted) completer.complete();
    },
  );
}
