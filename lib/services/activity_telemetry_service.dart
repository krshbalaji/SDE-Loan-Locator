import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/user_model.dart';
import 'demo_alert_service.dart';
import 'location_service.dart';

class ActivityEventRecord {
  final DateTime timestamp;
  final String type;
  final String label;
  final String? detail;

  const ActivityEventRecord({
    required this.timestamp,
    required this.type,
    required this.label,
    this.detail,
  });

  Map<String, dynamic> toMap() => <String, dynamic>{
        'timestamp': timestamp.toIso8601String(),
        'type': type,
        'label': label,
        if (detail != null) 'detail': detail,
      };

  factory ActivityEventRecord.fromMap(Map<String, dynamic> map) {
    return ActivityEventRecord(
      timestamp: DateTime.tryParse(map['timestamp']?.toString() ?? '') ??
          DateTime.now(),
      type: map['type']?.toString() ?? 'action',
      label: map['label']?.toString() ?? '',
      detail: map['detail']?.toString(),
    );
  }
}

class TesterSessionRecord {
  final String sessionId;
  final String uid;
  final String displayName;
  final String email;
  final String roleLabel;
  final String branch;
  final String platform;
  final bool isDemoSession;
  final DateTime loginAt;
  DateTime lastActiveAt;
  DateTime? logoutAt;
  int activeSeconds;
  final List<String> screensVisited;
  final List<String> itemsReviewed;
  final List<ActivityEventRecord> events;

  TesterSessionRecord({
    required this.sessionId,
    required this.uid,
    required this.displayName,
    required this.email,
    required this.roleLabel,
    required this.branch,
    required this.platform,
    required this.isDemoSession,
    required this.loginAt,
    required this.lastActiveAt,
    this.logoutAt,
    this.activeSeconds = 0,
    List<String>? screensVisited,
    List<String>? itemsReviewed,
    List<ActivityEventRecord>? events,
  })  : screensVisited = screensVisited ?? <String>[],
        itemsReviewed = itemsReviewed ?? <String>[],
        events = events ?? <ActivityEventRecord>[];

  Map<String, dynamic> toMap() => <String, dynamic>{
        'sessionId': sessionId,
        'uid': uid,
        'displayName': displayName,
        'email': email,
        'roleLabel': roleLabel,
        'branch': branch,
        'platform': platform,
        'isDemoSession': isDemoSession,
        'loginAt': loginAt.toIso8601String(),
        'lastActiveAt': lastActiveAt.toIso8601String(),
        'logoutAt': logoutAt?.toIso8601String(),
        'activeSeconds': activeSeconds,
        'screensVisited': screensVisited,
        'itemsReviewed': itemsReviewed,
        'events': events.map((e) => e.toMap()).toList(),
      };

  factory TesterSessionRecord.fromMap(Map<String, dynamic> map) {
    final rawEvents = map['events'] is List ? (map['events'] as List) : const [];
    final rawScreens =
        map['screensVisited'] is List ? (map['screensVisited'] as List) : const [];
    final rawReviewed =
        map['itemsReviewed'] is List ? (map['itemsReviewed'] as List) : const [];
    return TesterSessionRecord(
      sessionId: map['sessionId']?.toString() ?? '',
      uid: map['uid']?.toString() ?? 'unknown',
      displayName: map['displayName']?.toString() ?? 'Unknown User',
      email: map['email']?.toString() ?? '',
      roleLabel: map['roleLabel']?.toString() ?? '',
      branch: map['branch']?.toString() ?? 'Unassigned',
      platform: map['platform']?.toString() ?? 'Unknown',
      isDemoSession: map['isDemoSession'] == true,
      loginAt: DateTime.tryParse(map['loginAt']?.toString() ?? '') ??
          DateTime.now(),
      lastActiveAt: DateTime.tryParse(map['lastActiveAt']?.toString() ?? '') ??
          DateTime.now(),
      logoutAt: map['logoutAt'] != null
          ? DateTime.tryParse(map['logoutAt'].toString())
          : null,
      activeSeconds: (map['activeSeconds'] as num?)?.toInt() ?? 0,
      screensVisited: rawScreens.map((e) => e.toString()).toList(),
      itemsReviewed: rawReviewed.map((e) => e.toString()).toList(),
      events: rawEvents
          .whereType()
          .map((e) => ActivityEventRecord.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

class _TelemetryNavigatorObserver extends NavigatorObserver {
  _TelemetryNavigatorObserver(this._service);
  final ActivityTelemetryService _service;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    final name = route.settings.name;
    if (name != null && name.trim().isNotEmpty && name != '/') {
      _service.logScreenView(name.trim());
    }
  }
}

class ActivityTelemetryService extends ChangeNotifier
    with WidgetsBindingObserver {
  ActivityTelemetryService({required this.useFirebase}) {
    WidgetsBinding.instance.addObserver(this);
    _navigatorObserver = _TelemetryNavigatorObserver(this);
  }

  static const String _collectionName = 'tester_activity_sessions';

  final bool useFirebase;
  late final NavigatorObserver _navigatorObserver;
  NavigatorObserver get navigatorObserver => _navigatorObserver;

  final List<TesterSessionRecord> _sessions = <TesterSessionRecord>[];
  TesterSessionRecord? _activeSession;
  String? _demoTesterName;
  String? _demoRoleLabel;
  GeoPointResult? _demoStartGeo;
  DateTime? _demoStartedAt;

  void setDemoTesterContext({
    required String testerName,
    required String demoRoleLabel,
    required GeoPointResult startGeo,
    required DateTime startedAt,
  }) {
    _demoTesterName = testerName;
    _demoRoleLabel = demoRoleLabel;
    _demoStartGeo = startGeo;
    _demoStartedAt = startedAt;
  }
  Timer? _heartbeatTimer;
  DateTime? _lastTickAt;
  bool _isForeground = true;
  bool _isSyncing = false;

  List<TesterSessionRecord> get sessions => List.unmodifiable(_sessions);
  TesterSessionRecord? get activeSession => _activeSession;
  bool get isSyncing => _isSyncing;

  String _detectPlatform() {
    if (kIsWeb) return 'Web Browser';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'Android';
      case TargetPlatform.iOS:
        return 'iOS';
      case TargetPlatform.windows:
        return 'Windows';
      case TargetPlatform.macOS:
        return 'macOS';
      case TargetPlatform.linux:
        return 'Linux';
      default:
        return 'Device';
    }
  }

  Future<void> _pushSessionToFirestore(TesterSessionRecord session) async {
    if (!useFirebase) return;
    try {
      await FirebaseFirestore.instance
          .collection(_collectionName)
          .doc(session.sessionId)
          .set(session.toMap(), SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> syncFromFirestore() async {
    if (!useFirebase) return;
    _isSyncing = true;
    notifyListeners();
    try {
      final snap = await FirebaseFirestore.instance
          .collection(_collectionName)
          .orderBy('loginAt', descending: true)
          .limit(150)
          .get();
      final byId = <String, TesterSessionRecord>{
        for (final s in _sessions) s.sessionId: s,
      };
      for (final doc in snap.docs) {
        final remote = TesterSessionRecord.fromMap(doc.data());
        if (_activeSession != null &&
            remote.sessionId == _activeSession!.sessionId) {
          continue;
        }
        byId[remote.sessionId] = remote;
      }
      _sessions
        ..clear()
        ..addAll(byId.values);
      _sessions.sort((a, b) => b.loginAt.compareTo(a.loginAt));
    } catch (_) {
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<void> startSession(
    AppUser user, {
    required bool isDemoSession,
  }) async {
    if (_activeSession != null &&
        _activeSession!.uid == user.uid &&
        _activeSession!.logoutAt == null) {
      return;
    }
    await endSession();

    final now = DateTime.now();
    final sessionId = '${user.uid}_${now.millisecondsSinceEpoch}';
    final session = TesterSessionRecord(
      sessionId: sessionId,
      uid: user.uid,
      displayName: user.displayName,
      email: user.email,
      roleLabel: user.role.name,
      branch: user.branch.isNotEmpty ? user.branch : 'All Branches',
      platform: _detectPlatform(),
      isDemoSession: isDemoSession,
      loginAt: now,
      lastActiveAt: now,
      screensVisited: <String>[
        user.isAdminOrAbove ? 'Executive BI' : 'Agent Home',
      ],
      events: <ActivityEventRecord>[
        ActivityEventRecord(
          timestamp: now,
          type: 'action',
          label: 'Logged in (${isDemoSession ? "Demo" : "Live"})',
        ),
      ],
    );

    _activeSession = session;
    _sessions.insert(0, session);
    _lastTickAt = now;
    _isForeground = true;

    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _flushElapsedTime(persistRemote: true);
    });

    notifyListeners();
    await _pushSessionToFirestore(session);
  }

  void _flushElapsedTime({bool persistRemote = false}) {
    final session = _activeSession;
    if (session == null) return;
    final now = DateTime.now();
    if (_isForeground && _lastTickAt != null) {
      final delta = now.difference(_lastTickAt!).inSeconds;
      if (delta > 0 && delta < 300) {
        session.activeSeconds += delta;
      }
    }
    _lastTickAt = now;
    session.lastActiveAt = now;
    notifyListeners();
    if (persistRemote) {
      _pushSessionToFirestore(session);
    }
  }

  Future<void> endSession() async {
    final session = _activeSession;
    if (session == null) return;
    _flushElapsedTime(persistRemote: false);
    final now = DateTime.now();
    session.logoutAt = now;
    session.events.add(
      ActivityEventRecord(
        timestamp: now,
        type: 'action',
        label: 'Session ended',
      ),
    );
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _activeSession = null;
    _lastTickAt = null;
    notifyListeners();
    await _pushSessionToFirestore(session);
  }

  void logScreenView(String screenName) {
    final session = _activeSession;
    if (session == null || screenName.trim().isEmpty) return;
    _flushElapsedTime();
    final clean = screenName.trim();
    if (!session.screensVisited.contains(clean)) {
      session.screensVisited.add(clean);
    }
    session.events.add(
      ActivityEventRecord(
        timestamp: DateTime.now(),
        type: 'screen',
        label: 'Opened $clean',
      ),
    );
    notifyListeners();
  }

  void logFeatureReviewed(String label, {String? detail}) {
    final session = _activeSession;
    if (session == null || label.trim().isEmpty) return;
    _flushElapsedTime();
    final entry = detail != null && detail.trim().isNotEmpty
        ? '${label.trim()}: ${detail.trim()}'
        : label.trim();
    if (!session.itemsReviewed.contains(entry)) {
      session.itemsReviewed.add(entry);
    }
    session.events.add(
      ActivityEventRecord(
        timestamp: DateTime.now(),
        type: 'action',
        label: label.trim(),
        detail: detail?.trim(),
      ),
    );
    notifyListeners();
    _pushSessionToFirestore(session);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _isForeground = true;
      _lastTickAt = DateTime.now();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _flushElapsedTime(persistRemote: true);
      _isForeground = false;
    }
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  String buildAuditCsv(List<TesterSessionRecord> targetSessions) {
    final buf = StringBuffer();
    buf.writeln('timestamp_iso,session_id,display_name,user_email,role,branch,platform,event_type,label,detail');
    String esc(String? v) {
      final safe = (v ?? '').replaceAll('"', '""');
      return '"$safe"';
    }
    for (final session in targetSessions) {
      for (final ev in session.events) {
        buf.writeln([
          esc(ev.timestamp.toIso8601String()),
          esc(session.sessionId),
          esc(session.displayName),
          esc(session.email),
          esc(session.roleLabel),
          esc(session.branch),
          esc(session.platform),
          esc(ev.type),
          esc(ev.label),
          esc(ev.detail),
        ].join(','));
      }
    }
    return buf.toString();
  }

}
