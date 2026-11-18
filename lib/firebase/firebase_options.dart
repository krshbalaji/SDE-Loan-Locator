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
    apiKey: _placeholder,
    appId: '1:000000000000:web:placeholder',
    messagingSenderId: '000000000000',
    projectId: 'sde-loan-locator-demo',
    authDomain: 'sde-loan-locator-demo.firebaseapp.com',
    storageBucket: 'sde-loan-locator-demo.appspot.com',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: _placeholder,
    appId: '1:000000000000:android:placeholder',
    messagingSenderId: '000000000000',
    projectId: 'sde-loan-locator-demo',
    storageBucket: 'sde-loan-locator-demo.appspot.com',
  );
}
