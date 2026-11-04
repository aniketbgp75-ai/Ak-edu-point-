# AK Edu Point

A Flutter tuition-management app starter for Android and iOS.

## Features currently implemented
- Add, edit and delete student records
- Store student class, parent/guardian name, phone number and monthly fee
- Mark daily attendance as present or absent
- Record fee payments and calculate current-month fee balance
- Record exam marks by student, subject and exam
- Dashboard and shareable attendance, fee and summary reports
- Local on-device persistence using SharedPreferences
- Share fee reminders through the phone's share menu (choose WhatsApp if installed)

## Run locally
1. Install Flutter SDK and Android Studio (Android) or Xcode (iOS).
2. Clone this repository.
3. From the project directory run:
   `flutter create . --platforms=android,ios`
   This generates the native Android/iOS project folders.
4. Run `flutter pub get`.
5. Run `flutter run` with a connected device or emulator.

## Important limitations
This version stores records on the current device only. It does not yet include secure teacher/parent accounts, multi-device cloud sync, online backup, or direct WhatsApp Business messaging. Those require a backend (for example Firebase) and project credentials/configuration. Do not use this local-only version as a multi-user production system until those are added.

## Build
After generating the native platform folders, run `flutter build apk --release` for an Android APK. iOS builds require macOS and Xcode.
