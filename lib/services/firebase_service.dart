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
      email: email.trim().toLowerCase(),
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
      'email': email.trim().toLowerCase(),
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

    final parentByStudent = <String, String>{
      for (final row in students)
        if (row['parentUid'] != null && row['id'] != null)
          row['id'].toString(): row['parentUid'].toString(),
    };
    final writes = <({DocumentReference<Map<String, dynamic>> ref, Map<String, dynamic> data})>[];
    final collections = <String, List<Map<String, dynamic>>>{
      'students': students,
      'attendance': attendance,
      'payments': payments,
      'marks': marks,
    };

    for (final entry in collections.entries) {
      for (final row in entry.value) {
        final studentId = row['studentId']?.toString();
        // Older attendance entries did not have an id. Give them a stable
        // document key so they can be synced without creating duplicates.
        final id = row['id']?.toString() ??
            (entry.key == 'attendance' && studentId != null && row['date'] != null
                ? '${studentId}_${row['date']}'
                : null);
        if (id == null || id.isEmpty) continue;
        final data = Map<String, dynamic>.from(row)
          ..['ownerUid'] = user.uid
          ..['updatedAt'] = FieldValue.serverTimestamp();
        if (entry.key == 'attendance' && row['id'] == null) data['id'] = id;
        final linkedParent = entry.key == 'students'
            ? row['parentUid']?.toString()
            : parentByStudent[studentId];
        if (linkedParent != null && linkedParent.isNotEmpty) {
          data['parentUid'] = linkedParent;
        }
        writes.add((
          ref: db.collection(entry.key).doc(id),
          data: data,
        ));
      }
    }

    // Firestore limits a batch to 500 writes. Keep a safety margin and
    // commit in chunks so larger tuition datasets do not fail as one batch.
    for (var offset = 0; offset < writes.length; offset += 400) {
      final batch = db.batch();
      final end = (offset + 400 < writes.length) ? offset + 400 : writes.length;
      for (final write in writes.sublist(offset, end)) {
        batch.set(write.ref, write.data, SetOptions(merge: true));
      }
      await batch.commit();
    }

    await db.collection('users').doc(user.uid).set({
      'uid': user.uid,
      'academy': academy,
      'lastSyncAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
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


  static Future<String?> findFamilyUidByEmail(String email) async {
    final value = email.trim().toLowerCase();
    if (value.isEmpty) return null;
    final snap = await db.collection('users').where('email', isEqualTo: value).limit(1).get();
    if (snap.docs.isEmpty) return null;
    final data = snap.docs.first.data();
    if (data['role'] != 'parent' && data['role'] != 'student') return null;
    return snap.docs.first.id;
  }

  static Future<List<Map<String, dynamic>>> getFamilyStudents() async {
    final user = currentUser;
    if (user == null) throw StateError('Please sign in first.');
    final snap = await db.collection('students').where('parentUid', isEqualTo: user.uid).get();
    return snap.docs.map((d) => <String, dynamic>{...d.data(), 'id': d.id}).toList();
  }

  static Future<List<Map<String, dynamic>>> getFamilyRecords(String collection, String studentId) async {
    final user = currentUser;
    if (user == null) throw StateError('Please sign in first.');
    final snap = await db.collection(collection).where('parentUid', isEqualTo: user.uid).where('studentId', isEqualTo: studentId).get();
    return snap.docs.map((d) => <String, dynamic>{...d.data(), 'id': d.id}).toList();
  }


  /// Delete a student and all of that student's teacher-owned records.
  /// Called only after the teacher confirms deletion in the app.
  static Future<void> deleteStudentRecords(String studentId) async {
    final user = currentUser;
    if (user == null) throw StateError('Please sign in first.');
    final studentRef = db.collection('students').doc(studentId);
    final student = await studentRef.get();
    if (student.exists && student.data()?['ownerUid'] == user.uid) {
      await studentRef.delete();
    }
    for (final name in ['attendance', 'payments', 'marks']) {
      final snap = await db.collection(name)
          .where('ownerUid', isEqualTo: user.uid)
          .where('studentId', isEqualTo: studentId)
          .get();
      for (var offset = 0; offset < snap.docs.length; offset += 400) {
        final batch = db.batch();
        final end = (offset + 400 < snap.docs.length) ? offset + 400 : snap.docs.length;
        for (final doc in snap.docs.sublist(offset, end)) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }
    }
  }


  /// Create one point-in-time cloud snapshot at most once every 24 hours.
  /// Records are stored as separate documents to avoid Firestore's 1 MiB limit.
  static Future<bool> createAutomaticBackup({
    required String academy,
    required List<Map<String, dynamic>> students,
    required List<Map<String, dynamic>> attendance,
    required List<Map<String, dynamic>> payments,
    required List<Map<String, dynamic>> marks,
  }) async {
    final user = currentUser;
    if (user == null) return false;
    final userRef = db.collection('users').doc(user.uid);
    final profile = await userRef.get();
    final last = profile.data()?['lastAutoBackupAt'];
    if (last is Timestamp &&
        DateTime.now().toUtc().difference(last.toDate().toUtc()) <
            const Duration(hours: 24)) {
      return false;
    }

    final backupId = DateTime.now().toUtc().toIso8601String()
        .replaceAll(':', '-').replaceAll('.', '-');
    final backupRef = userRef.collection('backups').doc(backupId);
    final collections = <String, List<Map<String, dynamic>>>{
      'students': students,
      'attendance': attendance,
      'payments': payments,
      'marks': marks,
    };
    for (final entry in collections.entries) {
      for (var offset = 0; offset < entry.value.length; offset += 400) {
        final batch = db.batch();
        final end = (offset + 400 < entry.value.length)
            ? offset + 400
            : entry.value.length;
        for (final row in entry.value.sublist(offset, end)) {
          final id = row['id']?.toString();
          if (id == null || id.isEmpty) continue;
          batch.set(backupRef.collection(entry.key).doc(id), {
            ...row,
            'backupOwnerUid': user.uid,
          });
        }
        await batch.commit();
      }
    }
    await backupRef.set({
      'ownerUid': user.uid,
      'academy': academy,
      'createdAt': FieldValue.serverTimestamp(),
      'studentCount': students.length,
      'attendanceCount': attendance.length,
      'paymentCount': payments.length,
      'marksCount': marks.length,
    });
    await userRef.set({
      'lastAutoBackupAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return true;
  }

  /// Store a compact teacher profile photo in the teacher's own profile doc.
  /// Keep the encoded image below Firestore's 1 MiB document limit.
  static Future<void> saveTeacherPhoto(String photoBase64) async {
    final user = currentUser;
    if (user == null) throw StateError('Please sign in first.');
    if (photoBase64.length > 650000) {
      throw ArgumentError('Photo is too large for secure profile sync.');
    }
    await db.collection('users').doc(user.uid).set({
      'uid': user.uid,
      'profilePhotoBase64': photoBase64,
    }, SetOptions(merge: true));
  }

  static Future<String?> getTeacherPhoto() async {
    final user = currentUser;
    if (user == null) return null;
    final doc = await db.collection('users').doc(user.uid).get();
    final value = doc.data()?['profilePhotoBase64']?.toString();
    return value == null || value.isEmpty ? null : value;
  }

  static Future<void> signOut() => auth.signOut();
}
