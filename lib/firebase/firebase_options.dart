import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Firebase options for Saro Devi Enterprises — Loan Locator & Lending System.
/// Replace the placeholder values by running `flutterfire configure`, or paste
/// your project keys from the Firebase Console.
class DefaultFirebaseOptions {
  static const String _placeholder = 'YOUR_API_KEY';

  /// Returns true once real Firebase keys have been configured.
  static bool get isConfigured =>
      web.apiKey != _placeholder && android.apiKey != _placeholder;

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return web;
      default:
        return web;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAAYbXhzIcX8sqAaPttowdYYe2mBneLwsw',
    appId: '1:190103819067:web:4271dbb3324966db4add1e',
    messagingSenderId: '190103819067',
    projectId: 'sde-loan-locator',
    authDomain: 'sde-loan-locator.firebaseapp.com',
    storageBucket: 'sde-loan-locator.firebasestorage.app',
    measurementId: 'G-NB7ZH11ZWG',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCslKg4tRM2v2R9UnZYqtz9xzploBMsZ6o',
    appId: '1:190103819067:android:0988d712fd8f4db74add1e',
    messagingSenderId: '190103819067',
    projectId: 'sde-loan-locator',
    storageBucket: 'sde-loan-locator.firebasestorage.app',
  );
}
