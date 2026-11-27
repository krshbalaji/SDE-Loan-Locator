import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

Future<void> sendWebRelayPost(String endpoint, String payload) async {
  final completer = Completer<void>();
  final req = web.XMLHttpRequest();
  req.open('POST', endpoint);
  req.setRequestHeader('Content-Type', 'text/plain;charset=UTF-8');
  req.onLoadEnd.listen((_) {
    debugPrint('DemoAlertService Web HTTP ${req.status}: ${req.responseText}');
    if (!completer.isCompleted) completer.complete();
  });
  req.onError.listen((_) {
    debugPrint('DemoAlertService Web XHR network/CORS error');
    if (!completer.isCompleted) completer.complete();
  });
  req.send(payload.toJS);
  await completer.future.timeout(const Duration(seconds: 8), onTimeout: () {});
}
