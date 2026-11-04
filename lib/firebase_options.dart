// Generated for the AK Edu Point Android Firebase app.
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError(
          'Firebase options are not configured for this platform yet. '
          'Register the platform in Firebase and regenerate firebase_options.dart.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDuIVOgnjr0SxOUNLPl8UseN0cyMa-a_Jg',
    appId: '1:378949741453:android:23b7e9b58689a0f42aebc4',
    messagingSenderId: '378949741453',
    projectId: 'ak-edu-point',
    storageBucket: 'ak-edu-point.firebasestorage.app',
  );
}
