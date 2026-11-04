import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Authentication and profile access for AK Edu Point.
/// Teacher accounts should be created by the owner in Firebase Console.
/// Parent/student accounts may be created from the app after the login UI is connected.
class FirebaseService {
  FirebaseService._();

  static final FirebaseAuth auth = FirebaseAuth.instance;
  static final FirebaseFirestore db = FirebaseFirestore.instance;

  static User? get currentUser => auth.currentUser;

  static Future<UserCredential> signIn({
    required String email,
    required String password,
  }) {
    return auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  static Future<UserCredential> registerFamilyAccount({
    required String name,
    required String email,
    required String password,
    required String role,
  }) async {
    if (role != 'parent' && role != 'student') {
      throw ArgumentError('Only parent or student self-registration is allowed.');
    }
    final credential = await auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = credential.user;
    if (user == null) {
      throw StateError('Firebase did not return a user account.');
    }
    await db.collection('users').doc(user.uid).set({
      'uid': user.uid,
      'name': name.trim(),
      'email': email.trim(),
      'role': role,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return credential;
  }

  static Future<DocumentSnapshot<Map<String, dynamic>>> getMyProfile() async {
    final user = currentUser;
    if (user == null) throw StateError('Please sign in first.');
    return db.collection('users').doc(user.uid).get();
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> myProfileStream() {
    final user = currentUser;
    if (user == null) return const Stream.empty();
    return db.collection('users').doc(user.uid).snapshots();
  }

  static Future<void> signOut() => auth.signOut();
}
