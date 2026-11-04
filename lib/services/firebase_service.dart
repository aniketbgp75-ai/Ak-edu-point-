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

  /// Sync the teacher's tuition records to Firestore. Local storage remains the
  /// primary offline cache; every record is scoped to the signed-in teacher.
  static Future<void> syncTuitionData({
    required String academy,
    required List<Map<String, dynamic>> students,
    required List<Map<String, dynamic>> attendance,
    required List<Map<String, dynamic>> payments,
    required List<Map<String, dynamic>> marks,
  }) async {
    final user = currentUser;
    if (user == null) throw StateError('Please sign in first.');
    final batch = db.batch();
    final collections = <String, List<Map<String, dynamic>>>{
      'students': students,
      'attendance': attendance,
      'payments': payments,
      'marks': marks,
    };
    for (final entry in collections.entries) {
      for (final row in entry.value) {
        final id = row['id']?.toString();
        if (id == null || id.isEmpty) continue;
        final data = Map<String, dynamic>.from(row)
          ..['ownerUid'] = user.uid
          ..['updatedAt'] = FieldValue.serverTimestamp();
        batch.set(db.collection(entry.key).doc(id), data, SetOptions(merge: true));
      }
    }
    batch.set(db.collection('users').doc(user.uid), {
      'uid': user.uid,
      'academy': academy,
      'lastSyncAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await batch.commit();
  }

  static Future<Map<String, dynamic>> downloadTuitionData() async {
    final user = currentUser;
    if (user == null) throw StateError('Please sign in first.');
    Future<List<Map<String, dynamic>>> read(String name) async {
      final snap = await db.collection(name).where('ownerUid', isEqualTo: user.uid).get();
      return snap.docs.map((d) => <String, dynamic>{...d.data(), 'id': d.id}).toList();
    }
    final profile = await db.collection('users').doc(user.uid).get();
    return {
      'academy': profile.data()?['academy']?.toString() ?? 'AK Edu Point',
      'students': await read('students'),
      'attendance': await read('attendance'),
      'payments': await read('payments'),
      'marks': await read('marks'),
    };
  }

  static Future<void> signOut() => auth.signOut();
}
