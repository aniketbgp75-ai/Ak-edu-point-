# AK Edu Point — Firebase setup (Hindi)

यह repository Firebase integration की तैयारी रखती है। Firebase project और platform config owner के Google account में बनाना जरूरी है; इस repository में अभी कोई API key या service-account secret शामिल नहीं है।

## 1. Firebase project बनाएं
1. https://console.firebase.google.com/ खोलें और अपने Google account से sign in करें।
2. **Add project** चुनें और नाम `AK Edu Point` रखें।
3. Project बनने के बाद Android app जोड़ें।
4. Android package name वही रखें जो Flutter app में final तय होगा। Android package name `com.aniketbgp75.akedupoint` final है और Firebase में इसी नाम से register किया गया है। `firebase/google-services.json` को GitHub Actions build के दौरान `android/app/` में copy किया जाता है।
5. Firebase Authentication → Sign-in method → **Email/Password** enable करें।
6. Firestore Database → Create database चुनें। शुरुआत में test mode न रखें; नीचे दिए rules deploy करें।

## 2. FlutterFire configuration
Computer पर Flutter SDK और Firebase CLI install करें, फिर:
```bash
dart pub global activate flutterfire_cli
firebase login
flutterfire configure
```
अपने Firebase project और Android/iOS apps चुनें। Android Firebase options `lib/firebase_options.dart` में रखे गए हैं। iOS के लिए अलग Firebase app registration और options अभी बाकी हैं। Service-account JSON या private credentials कभी commit न करें।

## 3. Firestore rules deploy करें
Firebase CLI से project चुनने के बाद:
```bash
firebase deploy --only firestore:rules
```
Repository का `firestore.rules` शुरुआती rules देता है। Teacher authorization trusted custom claim `teacher: true` पर आधारित है। Teacher account owner द्वारा Firebase Authentication में बनाया जाना चाहिए। Teacher अधिकार केवल trusted Firebase Admin SDK से custom claim `teacher: true` सेट करने पर मिलेंगे; केवल Firestore profile में role लिखना पर्याप्त नहीं है। Admin SDK की private service-account key कभी GitHub या app में upload न करें। App self-registration केवल parent/student role के लिए रखता है।

## 4. Run
```bash
flutter pub get
flutter run
```

## Data model
- `users/{uid}`: name, email, role (teacher/parent/student)
- `students/{studentId}`: name, class, monthlyFee, parentUid
- `attendance/{recordId}`: studentId, date, status
- `payments/{paymentId}`: studentId, amount, date, note
- `marks/{markId}`: studentId, exam, subject, obtained, total, date

## Important
Current app screens still use local SharedPreferences for tuition records. Firebase auth/profile service and Firestore rules are groundwork only; cloud CRUD, login screens, account linking/invitations, password reset, and migration from local records still need implementation and testing. Never publish or store real student data until access rules and account linking have been tested with separate teacher and parent accounts.
