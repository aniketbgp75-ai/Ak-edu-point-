import 'dart:convert';
import 'dart:typed_data';
import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'services/firebase_service.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // A notification permission/plugin failure must never stop the tuition app
  // itself from launching.
  try {
    await AppNotifications.initialize().timeout(const Duration(seconds: 8));
  } catch (_) {}
  runApp(const AkEduPointApp());
}

class AkEduPointApp extends StatelessWidget {
  const AkEduPointApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'AK Edu Point', debugShowCheckedModeBanner: false,
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2457C5)), useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFFF5F7FB)),
    home: const AuthGate());
}


/// Routes authenticated users according to a trusted Firebase custom claim.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: FirebaseService.auth.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final user = snapshot.data;
        if (user == null) return const LoginPage();
        return FutureBuilder(
          future: user.getIdTokenResult(true),
          builder: (context, claimSnapshot) {
            if (claimSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            final isTeacher = claimSnapshot.data?.claims?['teacher'] == true;
            if (isTeacher) return const TuitionHome();
            return FutureBuilder(
              future: FirebaseService.getMyProfile(),
              builder: (context, profileSnapshot) {
                if (profileSnapshot.connectionState == ConnectionState.waiting) {
                  return const Scaffold(body: Center(child: CircularProgressIndicator()));
                }
                final role = profileSnapshot.data?.data()?['role']?.toString();
                if (role == 'parent' || role == 'student') return const FamilyDashboard();
                return AccessPendingPage(email: user.email ?? '');
              },
            );
          },
        );
      },
    );
  }
}

class FamilyDashboard extends StatefulWidget {
  const FamilyDashboard({super.key});
  @override
  State<FamilyDashboard> createState() => _FamilyDashboardState();
}

class _FamilyDashboardState extends State<FamilyDashboard> {
  late Future<List<Map<String, dynamic>>> studentsFuture;
  @override
  void initState() { super.initState(); studentsFuture = FirebaseService.getFamilyStudents(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Family Dashboard'), actions: [
      IconButton(onPressed: () async { await FirebaseService.signOut(); }, icon: const Icon(Icons.logout)),
    ]),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: studentsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return const Center(child: Text('Records load nahi ho paye. Internet connection check karein.'));
        final rows = snapshot.data ?? [];
        if (rows.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Abhi koi student account link nahi hai. Tuition teacher se student account link karwayein.', textAlign: TextAlign.center)));
        return ListView(padding: const EdgeInsets.all(16), children: [
          const Text('Linked Student Records', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
          ...rows.map((student) => Card(child: ExpansionTile(
            leading: CircleAvatar(child: Text((student['name'] ?? 'S').toString().substring(0, 1).toUpperCase())),
            title: Text(student['name']?.toString() ?? 'Student'),
            subtitle: Text('Class ${student['class'] ?? '—'} • ${student['batch'] ?? 'General'}'),
            children: [
              ListTile(title: const Text('Monthly Fee'), trailing: Text('₹${student['fee'] ?? 0}')),
              FutureBuilder<List<Map<String, dynamic>>>(future: FirebaseService.getFamilyRecords('payments', student['id'].toString()), builder: (context, snap) {
                final items = snap.data ?? [];
                final total = items.fold<int>(0, (sum, item) => sum + (int.tryParse(item['amount'].toString()) ?? 0));
                return ListTile(leading: const Icon(Icons.payments_outlined), title: const Text('Payment History'), subtitle: Text('${items.length} payments • Total ₹$total'));
              }),
              FutureBuilder<List<Map<String, dynamic>>>(future: FirebaseService.getFamilyRecords('attendance', student['id'].toString()), builder: (context, snap) {
                final items = snap.data ?? [];
                final present = items.where((x) => x['status'] == 'Present').length;
                return ListTile(leading: const Icon(Icons.fact_check_outlined), title: const Text('Attendance'), subtitle: Text('Present $present / ${items.length} marked'));
              }),
              FutureBuilder<List<Map<String, dynamic>>>(future: FirebaseService.getFamilyRecords('marks', student['id'].toString()), builder: (context, snap) {
                final items = snap.data ?? [];
                return ListTile(leading: const Icon(Icons.assessment_outlined), title: const Text('Exam Results'), subtitle: Text('${items.length} result records'));
              }),
            ],
          ))),
        ]);
      },
    ),
  );
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool busy = false;
  bool hidePassword = true;
  String? error;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> signIn() async {
    if (email.text.trim().isEmpty || password.text.isEmpty) {
      setState(() => error = 'Email aur password dono bhariye.');
      return;
    }
    setState(() { busy = true; error = null; });
    try {
      await FirebaseService.signIn(email: email.text, password: password.text);
      // AuthGate checks the trusted teacher custom claim before opening records.
    } on FirebaseAuthException catch (e) {
      setState(() => error = e.code == 'user-not-found' || e.code == 'wrong-password' || e.code == 'invalid-credential'
        ? 'Email ya password sahi nahi hai.' : (e.message ?? 'Login nahi ho paya.'));
    } catch (_) {
      setState(() => error = 'Login nahi ho paya. Internet connection check karein.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> resetPassword() async {
    if (email.text.trim().isEmpty) {
      setState(() => error = 'Pehle email address likhiye.');
      return;
    }
    try {
      await FirebaseService.auth.sendPasswordResetEmail(email: email.text.trim());
      if (mounted) setState(() => error = 'Password reset link email par bhej diya gaya hai.');
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => error = e.message ?? 'Reset email nahi bheja ja saka.');
    }
  }

  Future<void> registerFamily() async {
    final name = TextEditingController();
    final mail = TextEditingController(text: email.text.trim());
    final pass = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Parent registration'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Full name'),
                    validator: (v) => v == null || v.trim().isEmpty ? 'Name required' : null,
                  ),
                  TextFormField(
                    controller: mail,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email address'),
                    validator: (v) => v == null || !v.contains('@') ? 'Valid email required' : null,
                  ),
                  TextFormField(
                    controller: pass,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Password (minimum 6 characters)'),
                    validator: (v) => v == null || v.length < 6 ? 'At least 6 characters' : null,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) Navigator.pop(ctx, true);
              },
              child: const Text('Create account'),
            ),
          ],
        );
      },
    );
    if (accepted == true) {
      setState(() { busy = true; error = null; });
      try {
        await FirebaseService.registerFamilyAccount(
          name: name.text,
          email: mail.text,
          password: pass.text,
          role: 'parent',
        );
      } on FirebaseAuthException catch (e) {
        setState(() => error = e.code == 'email-already-in-use'
            ? 'Is email se account pehle se bana hai.'
            : (e.message ?? 'Account nahi bana.'));
      } catch (_) {
        setState(() => error = 'Account nahi ban saka. Firestore rules aur internet check karein.');
      } finally {
        if (mounted) setState(() => busy = false);
      }
    }
    name.dispose();
    mail.dispose();
    pass.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Icon(Icons.school_rounded, size: 64, color: Color(0xFF2457C5)),
          const SizedBox(height: 12),
          const Text('AK Edu Point', textAlign: TextAlign.center,
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text('Teacher login', textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54, fontSize: 16)),
          const SizedBox(height: 28),
          TextField(controller: email, keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email address', prefixIcon: Icon(Icons.email_outlined),
              border: OutlineInputBorder())),
          const SizedBox(height: 14),
          TextField(controller: password, obscureText: hidePassword,
            decoration: InputDecoration(labelText: 'Password', prefixIcon: const Icon(Icons.lock_outline),
              border: const OutlineInputBorder(), suffixIcon: IconButton(
                onPressed: () => setState(() => hidePassword = !hidePassword),
                icon: Icon(hidePassword ? Icons.visibility : Icons.visibility_off)))),
          Align(alignment: Alignment.centerRight, child: TextButton(
            onPressed: busy ? null : resetPassword, child: const Text('Forgot password?'))),
          if (error != null) Padding(padding: const EdgeInsets.only(bottom: 12),
            child: Text(error!, style: TextStyle(color: error!.contains('bhej diya') ? Colors.green : Colors.red))),
          FilledButton(onPressed: busy ? null : signIn,
            child: Padding(padding: const EdgeInsets.all(12),
              child: busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Login', style: TextStyle(fontSize: 16)))),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: busy ? null : registerFamily,
            child: const Text('Parent / Student registration')),
          const SizedBox(height: 18),
          const Text('Teacher account owner dwara Firebase mein banaya aur approve kiya jana chahiye.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.black54)),
        ],
      )),
    )),
  ));
}

class AccessPendingPage extends StatelessWidget {
  final String email;
  const AccessPendingPage({super.key, required this.email});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('AK Edu Point')),
    body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(
      mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.admin_panel_settings_outlined, size: 56, color: Colors.orange),
        const SizedBox(height: 16),
        const Text('Teacher approval pending', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center),
        const SizedBox(height: 10),
        Text('Signed in as $email, lekin is account ko abhi teacher access nahi mila hai.',
          textAlign: TextAlign.center),
        const SizedBox(height: 10),
        const Text('Owner ko Firebase Admin SDK se teacher permission deni hogi. Sirf app mein role chunne se teacher access nahi milta.',
          textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
        const SizedBox(height: 20),
        FilledButton(onPressed: () => FirebaseService.signOut(), child: const Text('Sign out')),
      ],
    ))),
  );
}

class TuitionHome extends StatefulWidget {
  const TuitionHome({super.key});
  @override
  State<TuitionHome> createState() => _TuitionHomeState();
}

class _TuitionHomeState extends State<TuitionHome> {
  static const storeKey = 'ak_edu_point_v1';
  final GlobalKey<ScaffoldState> scaffoldKey = GlobalKey<ScaffoldState>();
  int tab = 0;
  String studentSearch = '';
  String batchFilter = 'All';
  String get teacherName {
    final user = FirebaseAuth.instance.currentUser;
    final name = user?.displayName?.trim() ?? '';
    if (name.isNotEmpty) return name;
    return user?.email?.split('@').first ?? 'Teacher';
  }
  bool loading = true;
  String academy = 'AK Edu Point';
  String? profilePhotoBase64;
  List<Map<String, dynamic>> students = [], attendance = [], payments = [], marks = [];
  String get today => dateKey(DateTime.now());
  String dateKey(DateTime d) => d.year.toString().padLeft(4, '0') + '-' +
    d.month.toString().padLeft(2, '0') + '-' + d.day.toString().padLeft(2, '0');
  int n(dynamic v) => int.tryParse(v?.toString() ?? '') ?? 0;
  String rupees(int v) => '₹' + v.toString();
  List<Map<String, dynamic>> mapList(dynamic v) => v is List
    ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : [];

  List<Map<String, dynamic>> mergeRecords(
    List<Map<String, dynamic>> local, List<Map<String, dynamic>> cloud) {
    final merged = <String, Map<String, dynamic>>{};
    for (final row in cloud) {
      final id = row['id']?.toString();
      if (id != null && id.isNotEmpty) merged[id] = Map<String, dynamic>.from(row);
    }
    // Prefer this device's version for matching IDs, but retain cloud-only rows.
    for (final row in local) {
      final id = row['id']?.toString();
      if (id != null && id.isNotEmpty) merged[id] = Map<String, dynamic>.from(row);
    }
    return merged.values.toList();
  }

  @override
  void initState() { super.initState(); load(); }

  Future<void> load() async {
    try {
      // Bound local storage initialization too; otherwise the first await can
      // leave the dashboard spinner visible forever if the platform channel fails.
      final p = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 5));
      // Load local data first so the dashboard never waits for the network.
      final raw = p.getString(storeKey);
      profilePhotoBase64 = p.getString('ak_teacher_profile_photo');
      if (raw != null) {
        try {
          final d = jsonDecode(raw) as Map<String, dynamic>;
          academy = d['academy']?.toString() ?? academy;
          students = mapList(d['students']);
          attendance = mapList(d['attendance']);
          payments = mapList(d['payments']);
          marks = mapList(d['marks']);
        } catch (_) {}
      }
      if (mounted) setState(() => loading = false);

      // Notifications and cloud services are optional; failures/timeouts must
      // never leave the main dashboard stuck behind its loading spinner.
      try {
        await AppNotifications.setFeeReminder(p.getBool('ak_fee_alerts') ?? true)
            .timeout(const Duration(seconds: 4));
        await AppNotifications.setAttendanceReminder(p.getBool('ak_attendance_alerts') ?? true)
            .timeout(const Duration(seconds: 4));
        await AppNotifications.setWeeklySummary(p.getBool('ak_weekly_summary') ?? false)
            .timeout(const Duration(seconds: 4));
      } catch (_) {}

      if (profilePhotoBase64 == null) {
        try {
          profilePhotoBase64 = await FirebaseService.getTeacherPhoto()
              .timeout(const Duration(seconds: 6));
          if (profilePhotoBase64 != null) {
            await p.setString('ak_teacher_profile_photo', profilePhotoBase64!);
          }
        } catch (_) {}
      }

      try {
        final cloud = await FirebaseService.downloadTuitionData()
            .timeout(const Duration(seconds: 8));
        academy = academy == 'AK Edu Point'
            ? (cloud['academy']?.toString() ?? academy)
            : academy;
        students = mergeRecords(students, mapList(cloud['students']));
        attendance = mergeRecords(attendance, mapList(cloud['attendance']));
        payments = mergeRecords(payments, mapList(cloud['payments']));
        marks = mergeRecords(marks, mapList(cloud['marks']));
        await p.setString(storeKey, jsonEncode({
          'academy': academy, 'students': students, 'attendance': attendance,
          'payments': payments, 'marks': marks,
        }));
        if (mounted) setState(() {});
        try {
          await FirebaseService.syncTuitionData(
            academy: academy, students: students, attendance: attendance,
            payments: payments, marks: marks,
          ).timeout(const Duration(seconds: 8));
        } catch (_) {}
      } catch (_) {
        // Continue in offline mode with locally saved tuition data.
      }

      try {
        await FirebaseService.createAutomaticBackup(
          academy: academy, students: students, attendance: attendance,
          payments: payments, marks: marks,
        ).timeout(const Duration(seconds: 8));
      } catch (_) {}
    } catch (_) {
      // Keep the app usable even if local preferences or an optional service fails.
    } finally {
      if (mounted && loading) setState(() => loading = false);
    }
  }

  Future<void> save() async {
    final encoded = jsonEncode({'academy': academy, 'students': students,
      'attendance': attendance, 'payments': payments, 'marks': marks});
    // Commit to device storage first. Cloud failure must never discard a record.
    final p = await SharedPreferences.getInstance()
        .timeout(const Duration(seconds: 8));
    final stored = await p.setString(storeKey, encoded)
        .timeout(const Duration(seconds: 8));
    if (!stored) throw StateError('Phone storage could not save the records.');
    if (profilePhotoBase64 == null) {
      await p.remove('ak_teacher_profile_photo');
    } else {
      await p.setString('ak_teacher_profile_photo', profilePhotoBase64!);
    }
    if (mounted) setState(() {});
    try {
      await FirebaseService.syncTuitionData(academy: academy, students: students,
        attendance: attendance, payments: payments, marks: marks)
          .timeout(const Duration(seconds: 12));
      await FirebaseService.createAutomaticBackup(academy: academy,
        students: students, attendance: attendance, payments: payments, marks: marks)
          .timeout(const Duration(seconds: 12));
    } catch (_) {
      if (mounted) notice('Phone par save ho gaya. Cloud sync pending hai; internet/Firebase rules check karein.');
    }
  }

  int get present => attendance.where((a) => a['date'] == today && a['status'] == 'Present').length;
  int get absent => attendance.where((a) => a['date'] == today && a['status'] == 'Absent').length;
  int get collection {
    final month = today.substring(0, 7);
    return payments.where((p) => (p['date']?.toString() ?? '').startsWith(month))
      .fold(0, (v, p) => v + n(p['amount']));
  }
  int get cashCollection => payments.where((p) => (p['date']?.toString() ?? '').startsWith(today.substring(0, 7)) && (p['mode'] ?? 'Cash') == 'Cash').fold(0, (v, p) => v + n(p['amount']));
  int get onlineCollection => payments.where((p) => (p['date']?.toString() ?? '').startsWith(today.substring(0, 7)) && p['mode'] == 'Online').fold(0, (v, p) => v + n(p['amount']));
  int get yearlyCollection => payments.where((p) => (p['date']?.toString() ?? '').startsWith(today.substring(0, 4))).fold(0, (v, p) => v + n(p['amount']));
  int get batchCount => students.map((s) => (s['batch'] ?? 'General').toString()).toSet().length;
  int get classCount => students.map((s) => (s['class'] ?? '').toString()).toSet().length;
  int get due => students.fold(0, (sum, s) {
    final paid = payments.where((p) => p['studentId'] == s['id'] &&
      (p['date']?.toString() ?? '').startsWith(today.substring(0, 7)))
      .fold(0, (v, p) => v + n(p['amount']));
    final balance = n(s['fee']) - paid;
    return sum + (balance > 0 ? balance : 0);
  });
  String studentName(String id) {
    final list = students.where((s) => s['id'] == id);
    return list.isEmpty ? 'Removed student' : list.first['name'].toString();
  }
  void notice(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  Future<void> shareText(String text) => Share.share(text, subject: academy);

  Widget teacherAvatar(double radius) {
    final encoded = profilePhotoBase64;
    if (encoded != null && encoded.isNotEmpty) {
      try {
        return CircleAvatar(radius: radius, backgroundImage: MemoryImage(base64Decode(encoded)));
      } catch (_) {}
    }
    return CircleAvatar(radius: radius, backgroundColor: const Color(0xFF2580E8),
      child: Icon(Icons.person, color: Colors.white, size: radius * 1.1));
  }

  Future<void> changeTeacherPhoto() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.image, withData: true, allowMultiple: false,
      );
      if (picked == null || picked.files.isEmpty) return;
      final bytes = picked.files.single.bytes;
      if (bytes == null || bytes.isEmpty) {
        notice('Photo file phone se read nahi ho payi. Dusri image select karein.');
        return;
      }
      // Save the selected image locally first. Cloud photo sync is optional
      // and must not prevent the profile photo from appearing on this device.
      if (bytes.length > 3 * 1024 * 1024) {
        notice('Photo 3 MB se chhoti select karein.');
        return;
      }
      final encoded = base64Encode(bytes);
      profilePhotoBase64 = encoded;
      final p = await SharedPreferences.getInstance();
      final localSaved = await p.setString('ak_teacher_profile_photo', encoded);
      if (!localSaved) throw StateError('Phone storage rejected the photo.');
      if (mounted) setState(() {});
      if (bytes.length <= 480 * 1024) {
        try {
          await FirebaseService.saveTeacherPhoto(encoded)
              .timeout(const Duration(seconds: 10));
          if (mounted) notice('Profile photo phone aur cloud dono par save ho gayi.');
        } catch (e) {
          if (mounted) notice('Photo phone par save hai; cloud sync nahi hua: $e');
        }
      } else {
        if (mounted) notice('Photo phone par save ho gayi. Cloud sync ke liye 480 KB se chhoti image chahiye.');
      }
    } catch (e) {
      if (mounted) notice('Photo save nahi hui: $e');
    }
  }

  Future<void> editAcademy() async {
    final c = TextEditingController(text: academy);
    final v = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Tuition name'), content: TextField(controller: c),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Save'))]));
    if (v != null && v.isNotEmpty) { academy = v; await save(); }
    c.dispose();
  }

  Widget input(TextEditingController c, String label, {bool required = false, TextInputType type = TextInputType.text}) =>
    TextFormField(controller: c, keyboardType: type, decoration: InputDecoration(labelText: label),
      validator: (v) => required && (v == null || v.trim().isEmpty) ? 'Required' : null);

  Future<void> studentForm({Map<String, dynamic>? old}) async {
    final name = TextEditingController(text: old?['name']?.toString() ?? '');
    final cls = TextEditingController(text: old?['class']?.toString() ?? '');
    final phone = TextEditingController(text: old?['phone']?.toString() ?? '');
    final guardian = TextEditingController(text: old?['guardian']?.toString() ?? '');
    final parentEmail = TextEditingController(text: old?['parentEmail']?.toString() ?? '');
    final fee = TextEditingController(text: old?['fee']?.toString() ?? '');
    final batch = TextEditingController(text: old?['batch']?.toString() ?? 'General');
    final joiningDate = TextEditingController(
      text: old?['joiningDate']?.toString() ?? today,
    );
    final key = GlobalKey<FormState>();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: Text(old == null ? 'Add student' : 'Edit student'),
      content: Form(key: key, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        input(name, 'Student name', required: true), input(cls, 'Class', required: true),
        input(phone, 'Mobile number', type: TextInputType.phone), input(guardian, 'Parent / guardian'),
        input(parentEmail, 'Parent account email (optional)'),
        input(batch, 'Batch / Program'),
        TextFormField(
          controller: joiningDate,
          readOnly: true,
          decoration: const InputDecoration(
            labelText: 'Joining date',
            prefixIcon: Icon(Icons.calendar_month),
            hintText: 'YYYY-MM-DD',
          ),
          onTap: () async {
            final parts = joiningDate.text.split('-');
            final initial = parts.length == 3
                ? DateTime.tryParse(joiningDate.text) ?? DateTime.now()
                : DateTime.now();
            final picked = await showDatePicker(
              context: ctx,
              initialDate: initial,
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (picked != null) {
              joiningDate.text = dateKey(picked);
            }
          },
        ),
        input(fee, 'Monthly fee ₹', type: TextInputType.number)]))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () { if (key.currentState!.validate()) Navigator.pop(ctx, true); }, child: const Text('Save'))]));
    if (ok == true) {
      final id = old?['id']?.toString() ?? DateTime.now().microsecondsSinceEpoch.toString();
      String? parentUid;
      try { parentUid = await FirebaseService.findFamilyUidByEmail(parentEmail.text); } catch (_) {}
      final row = <String, dynamic>{'id': id, 'name': name.text.trim(), 'class': cls.text.trim(),
        'phone': phone.text.trim(), 'guardian': guardian.text.trim(), 'parentEmail': parentEmail.text.trim().toLowerCase(),
        if (parentUid != null) 'parentUid': parentUid,
        'batch': batch.text.trim().isEmpty ? 'General' : batch.text.trim(),
        'joiningDate': joiningDate.text.trim().isEmpty ? today : joiningDate.text.trim(),
        'fee': n(fee.text)};
      final i = students.indexWhere((s) => s['id'] == id);
      if (i < 0) { students.add(row); } else { students[i] = row; }
      try {
        await save();
        if (mounted) notice(old == null ? 'Student phone par save ho gaya.' : 'Student details update ho gayi.');
      } catch (e) {
        if (mounted) notice('Student save nahi hua: ${e.toString()}');
      }
    }
    name.dispose(); cls.dispose(); phone.dispose(); guardian.dispose(); parentEmail.dispose(); fee.dispose(); batch.dispose(); joiningDate.dispose();
  }

  Future<void> deleteStudent(Map<String, dynamic> s) async {
    final yes = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Delete student?'), content: Text('Remove ' + s['name'].toString() + '?'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete'))]));
    if (yes == true) {
      final id = s['id'].toString();
      try {
        // Remove the cloud copy first so the family dashboard cannot keep
        // showing a deleted student's private records.
        await FirebaseService.deleteStudentRecords(id);
        students.removeWhere((x) => x['id'] == id);
        attendance.removeWhere((x) => x['studentId'] == id);
        payments.removeWhere((x) => x['studentId'] == id);
        marks.removeWhere((x) => x['studentId'] == id);
        await save();
        if (mounted) notice('Student aur uske attendance, fees, marks records delete ho gaye.');
      } catch (_) {
        if (mounted) notice('Delete nahi hua. Internet/Firebase connection check karke dobara try karein.');
      }
    }
  }

  String statusOf(Map<String, dynamic> s) {
    final a = attendance.where((x) => x['studentId'] == s['id'] && x['date'] == today);
    return a.isEmpty ? 'Not marked' : a.first['status'].toString();
  }
  Future<void> setAttendance(Map<String, dynamic> s, String status) async {
    final i = attendance.indexWhere((a) => a['studentId'] == s['id'] && a['date'] == today);
    final row = <String, dynamic>{'id': '${s['id']}_$today', 'studentId': s['id'], 'date': today, 'status': status};
    if (i < 0) { attendance.add(row); } else { attendance[i] = row; }
    await save();
  }

  Future<String?> chooseStudent(String title) async {
    if (students.isEmpty) { notice('Add a student first.'); return null; }
    String id = students.first['id'].toString();
    return showDialog<String>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, refresh) =>
      AlertDialog(title: Text(title), content: DropdownButtonFormField<String>(
        value: id, isExpanded: true,
        items: students.map((s) => DropdownMenuItem(value: s['id'].toString(), child: Text(s['name'].toString()))).toList(),
        onChanged: (v) { if (v != null) refresh(() => id = v); }),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, id), child: const Text('Continue'))])));
  }

  Future<void> addPayment() async {
    final id = await chooseStudent('Select student');
    if (id == null) return;
    final amount = TextEditingController(), note = TextEditingController(text: 'Monthly fee');
    final key = GlobalKey<FormState>();
    String mode = 'Cash';
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, refresh) => AlertDialog(
      title: const Text('Record fee'), content: Form(key: key, child: Column(mainAxisSize: MainAxisSize.min, children: [
        input(amount, 'Amount ₹', required: true, type: TextInputType.number), input(note, 'Note'),
        const SizedBox(height: 8), DropdownButtonFormField<String>(value: mode, decoration: const InputDecoration(labelText: 'Payment mode'),
          items: const [DropdownMenuItem(value: 'Cash', child: Text('Cash')), DropdownMenuItem(value: 'Online', child: Text('Online'))],
          onChanged: (v) { if (v != null) refresh(() => mode = v); })])),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () { if (key.currentState!.validate() && n(amount.text) > 0) Navigator.pop(ctx, true); }, child: const Text('Save'))])));
    if (ok == true) {
      payments.add({'id': DateTime.now().microsecondsSinceEpoch.toString(), 'studentId': id,
        'amount': n(amount.text), 'note': note.text.trim(), 'mode': mode, 'date': today});
      await save(); notice('Payment saved.');
    }
    amount.dispose(); note.dispose();
  }

  Future<void> addMarks() async {
    final id = await chooseStudent('Select student');
    if (id == null) return;
    final exam = TextEditingController(), subject = TextEditingController();
    final got = TextEditingController(), total = TextEditingController(text: '100');
    final key = GlobalKey<FormState>();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Add exam marks'), content: Form(key: key, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        input(exam, 'Exam name', required: true), input(subject, 'Subject', required: true),
        input(got, 'Marks obtained', required: true, type: TextInputType.number),
        input(total, 'Maximum marks', required: true, type: TextInputType.number)]))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () { if (key.currentState!.validate() && n(total.text) > 0 && n(got.text) <= n(total.text)) Navigator.pop(ctx, true); }, child: const Text('Save'))]));
    if (ok == true) {
      marks.add({'id': DateTime.now().microsecondsSinceEpoch.toString(), 'studentId': id,
        'exam': exam.text.trim(), 'subject': subject.text.trim(), 'obtained': n(got.text),
        'total': n(total.text), 'date': today});
      await save();
    }
    exam.dispose(); subject.dispose(); got.dispose(); total.dispose();
  }

  Future<void> openBatchManager() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) =>
      StatefulBuilder(builder: (pageContext, refresh) {
        final groups = <String, List<Map<String, dynamic>>>{};
        for (final s in students) {
          final batchName = (s['batch'] ?? 'General').toString().trim();
          groups.putIfAbsent(batchName.isEmpty ? 'General' : batchName, () => []).add(s);
        }
        Future<void> createBatch() async {
          final controller = TextEditingController();
          final key = GlobalKey<FormState>();
          final ok = await showDialog<bool>(context: pageContext, builder: (dialogContext) =>
            AlertDialog(title: const Text('Create batch'),
              content: Form(key: key, child: TextFormField(controller: controller,
                autofocus: true, decoration: const InputDecoration(labelText: 'Batch name'),
                validator: (v) => v == null || v.trim().isEmpty ? 'Enter batch name' : null)),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
                FilledButton(onPressed: () {
                  if (key.currentState!.validate()) Navigator.pop(dialogContext, true);
                }, child: const Text('Create')),
              ]));
          if (ok == true) {
            final name = controller.text.trim();
            if (groups.keys.any((x) => x.toLowerCase() == name.toLowerCase())) {
              if (mounted) notice('This batch already exists.');
            } else {
              // A batch is represented by the batch field on its students.
              // Keep an empty batch visible by assigning it to a dedicated
              // empty-batch registry in the academy settings.
              final p = await SharedPreferences.getInstance();
              final saved = (p.getStringList('ak_empty_batches') ?? <String>[]);
              saved.add(name);
              await p.setStringList('ak_empty_batches', saved.toSet().toList());
              if (mounted) notice('Batch created. Add students and select "$name" in Batch / Program.');
            }
            refresh(() {});
          }
          controller.dispose();
        }
        Future<void> renameBatch(String oldName) async {
          final controller = TextEditingController(text: oldName);
          final ok = await showDialog<bool>(context: pageContext, builder: (dialogContext) =>
            AlertDialog(title: const Text('Rename batch'),
              content: TextField(controller: controller, autofocus: true,
                decoration: const InputDecoration(labelText: 'New batch name')),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim().isNotEmpty), child: const Text('Save')),
              ]));
          if (ok == true) {
            final newName = controller.text.trim();
            if (groups.keys.any((x) => x.toLowerCase() == newName.toLowerCase() && x != oldName)) {
              if (mounted) notice('A batch with this name already exists.');
            } else {
              for (final s in students) {
                if ((s['batch'] ?? 'General').toString() == oldName) s['batch'] = newName;
              }
              final p = await SharedPreferences.getInstance();
              final saved = p.getStringList('ak_empty_batches') ?? <String>[];
              await p.setStringList('ak_empty_batches', saved.map((x) => x == oldName ? newName : x).toSet().toList());
              await save();
              if (mounted) notice('Batch renamed.');
            }
            refresh(() {});
          }
          controller.dispose();
        }
        Future<void> deleteBatch(String name) async {
          final yes = await showDialog<bool>(context: pageContext, builder: (dialogContext) =>
            AlertDialog(title: const Text('Delete batch?'),
              content: Text('Students in "$name" will be moved to General. Student records will not be deleted.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Delete batch')),
              ]));
          if (yes == true) {
            for (final s in students) {
              if ((s['batch'] ?? 'General').toString() == name) s['batch'] = 'General';
            }
            final p = await SharedPreferences.getInstance();
            final saved = p.getStringList('ak_empty_batches') ?? <String>[];
            await p.setStringList('ak_empty_batches', saved.where((x) => x != name).toList());
            await save();
            if (mounted) notice('Batch deleted. Students moved to General.');
            refresh(() {});
          }
        }
        final emptyBatches = <String>{
          ...(SharedPreferences.getInstance() == null ? <String>[] : <String>[]),
        };
        return Scaffold(
          appBar: AppBar(title: const Text('Batches & Programs')),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: createBatch, icon: const Icon(Icons.add), label: const Text('Create batch')),
          body: FutureBuilder<List<String>>(
            future: SharedPreferences.getInstance().then((p) => p.getStringList('ak_empty_batches') ?? <String>[]),
            builder: (ctx, snapshot) {
              final names = <String>{...groups.keys, ...(snapshot.data ?? <String>[])}.toList()..sort();
              if (names.isEmpty) return const Center(child: Text('Create a batch or add students first.'));
              return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 90), children: [
                ...names.map((name) {
                  final members = groups[name] ?? <Map<String, dynamic>>[];
                  return Card(child: ExpansionTile(
                    leading: const Icon(Icons.groups_2_outlined),
                    title: Text(name),
                    subtitle: Text('${members.length} students'),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) { if (v == 'rename') renameBatch(name); if (v == 'delete') deleteBatch(name); },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'rename', child: Text('Rename batch')),
                        PopupMenuItem(value: 'delete', child: Text('Delete batch')),
                      ]),
                    children: [
                      if (members.isEmpty) const ListTile(title: Text('No students assigned yet')),
                      ...members.map((s) => ListTile(
                        title: Text(s['name'].toString()),
                        subtitle: Text('Class ${s['class']} • Fee ${rupees(n(s['fee']))}'),
                        trailing: IconButton(icon: const Icon(Icons.edit_outlined),
                          onPressed: () async { await studentForm(old: s); refresh(() {}); }),
                      )),
                      Padding(padding: const EdgeInsets.all(12), child: OutlinedButton.icon(
                        onPressed: () async {
                          final available = students.where((s) => (s['batch'] ?? 'General').toString() != name).toList();
                          if (available.isEmpty) { notice('No unassigned students. Add a student or edit an existing student.'); return; }
                          String? selectedId = available.first['id'].toString();
                          final chosen = await showDialog<String>(context: pageContext, builder: (dialogContext) =>
                            AlertDialog(title: Text('Add student to $name'),
                              content: DropdownButtonFormField<String>(
                                value: selectedId, isExpanded: true,
                                items: available.map((s) => DropdownMenuItem(
                                  value: s['id'].toString(), child: Text(s['name'].toString()))).toList(),
                                onChanged: (v) => selectedId = v),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
                                FilledButton(onPressed: () => Navigator.pop(dialogContext, selectedId), child: const Text('Add')),
                              ]));
                          if (chosen != null) {
                            final index = students.indexWhere((s) => s['id'].toString() == chosen);
                            if (index >= 0) {
                              students[index]['batch'] = name;
                              await save();
                              if (mounted) notice('Student added to $name.');
                              refresh(() {});
                            }
                          }
                        },
                        icon: const Icon(Icons.person_add_alt_1), label: const Text('Add student to batch'))),
                    ],
                  ));
                }),
              ]);
            },
          ),
        );
      })));
  }

  Future<void> openLogBook() async {
    DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
    DateTime? selected;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => StatefulBuilder(builder: (ctx, refresh) {
      final firstWeekday = DateTime(month.year, month.month, 1).weekday;
      final days = DateTime(month.year, month.month + 1, 0).day;
      final selectedKey = selected == null ? null : dateKey(selected!);
      final selectedRows = selectedKey == null ? <Map<String, dynamic>>[] : attendance.where((a) => a['date'] == selectedKey).toList();
      int countFor(int day, String status) => attendance.where((a) => a['date'] == dateKey(DateTime(month.year, month.month, day)) && a['status'] == status).length;
      return Scaffold(appBar: AppBar(title: const Text('Monthly Attendance LogBook')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            IconButton(onPressed: () => refresh(() { month = DateTime(month.year, month.month - 1); selected = null; }), icon: const Icon(Icons.chevron_left)),
            Text('${month.month.toString().padLeft(2, '0')}/${month.year}', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
            IconButton(onPressed: () => refresh(() { month = DateTime(month.year, month.month + 1); selected = null; }), icon: const Icon(Icons.chevron_right)),
          ]),
          const Row(children: [Expanded(child: Center(child: Text('Mon'))), Expanded(child: Center(child: Text('Tue'))), Expanded(child: Center(child: Text('Wed'))), Expanded(child: Center(child: Text('Thu'))), Expanded(child: Center(child: Text('Fri'))), Expanded(child: Center(child: Text('Sat'))), Expanded(child: Center(child: Text('Sun')))]),
          const SizedBox(height: 8),
          GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: days + firstWeekday - 1,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, mainAxisSpacing: 5, crossAxisSpacing: 5),
            itemBuilder: (context, index) {
              final day = index - firstWeekday + 2;
              if (day < 1 || day > days) return const SizedBox.shrink();
              final presentCount = countFor(day, 'Present'), absentCount = countFor(day, 'Absent');
              final active = selected?.day == day && selected?.month == month.month && selected?.year == month.year;
              return InkWell(onTap: () => refresh(() => selected = DateTime(month.year, month.month, day)),
                child: Container(decoration: BoxDecoration(color: active ? Theme.of(ctx).colorScheme.primaryContainer : (presentCount + absentCount > 0 ? Colors.green.withValues(alpha: .10) : Colors.transparent), borderRadius: BorderRadius.circular(10), border: Border.all(color: active ? Theme.of(ctx).colorScheme.primary : Colors.black12)),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text('$day', style: const TextStyle(fontWeight: FontWeight.w600)), if (presentCount + absentCount > 0) Text('$presentCount P • $absentCount A', style: const TextStyle(fontSize: 8))])));
            }),
          const SizedBox(height: 16),
          if (selected != null) ...[
            Text(dateKey(selected!), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            if (selectedRows.isEmpty) const Text('No attendance marked for this date.')
            else ...selectedRows.map((r) => ListTile(dense: true, title: Text(studentName(r['studentId'].toString())), trailing: Text(r['status'].toString(), style: TextStyle(color: r['status'] == 'Present' ? Colors.green : Colors.red)))),
          ] else const Text('Calendar date select karke attendance details dekhein.'),
        ]));
    })));
  }

  Future<void> openSettings() async {
    final prefs = await SharedPreferences.getInstance();
    bool feeAlerts = prefs.getBool('ak_fee_alerts') ?? true;
    bool attendanceAlerts = prefs.getBool('ak_attendance_alerts') ?? true;
    bool weeklySummary = prefs.getBool('ak_weekly_summary') ?? false;
    await showDialog<void>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, refresh) =>
      AlertDialog(title: const Text('Settings & Notification Preferences'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Fee reminder preferences'), value: feeAlerts, onChanged: (v) async { refresh(() => feeAlerts = v); await prefs.setBool('ak_fee_alerts', v); await AppNotifications.setFeeReminder(v); }),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Attendance reminder preferences'), value: attendanceAlerts, onChanged: (v) async { refresh(() => attendanceAlerts = v); await prefs.setBool('ak_attendance_alerts', v); await AppNotifications.setAttendanceReminder(v); }),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Weekly summary preference'), value: weeklySummary, onChanged: (v) async { refresh(() => weeklySummary = v); await prefs.setBool('ak_weekly_summary', v); await AppNotifications.setWeeklySummary(v); }),
          const Text('Scheduled reminders are delivered on this device. Allow notifications in Android settings.', style: TextStyle(fontSize: 12, color: Colors.black54)),
        ]), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))])));
  }

  Future<void> refreshDashboardFromLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 5));
      final raw = prefs.getString(storeKey);
      if (raw == null || raw.isEmpty) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final localStudents = mapList(data['students']);
      final localAttendance = mapList(data['attendance']);
      final localPayments = mapList(data['payments']);
      final localMarks = mapList(data['marks']);
      if (!mounted) return;
      setState(() {
        academy = data['academy']?.toString() ?? academy;
        students = localStudents;
        attendance = localAttendance;
        payments = localPayments;
        marks = localMarks;
      });
    } catch (e) {
      if (mounted) notice('Dashboard refresh failed: $e');
    }
  }

  Future<void> feeReminder(Map<String, dynamic> s) async {
    final month = today.substring(0, 7);
    final paid = payments.where((p) => p['studentId'] == s['id'] && (p['date']?.toString() ?? '').startsWith(month))
      .fold(0, (v, p) => v + n(p['amount']));
    final fee = n(s['fee']), balance = n(s['fee']) - paid;
    final who = (s['guardian']?.toString().isNotEmpty ?? false) ? s['guardian'].toString() : s['name'].toString();
    await shareText('Namaste ' + who + ' ji, ' + s['name'].toString() + ' ki is mahine ki fee ₹' +
      fee.toString() + '. Jama: ₹' + paid.toString() + ', baki: ₹' + (balance > 0 ? balance : 0).toString() + '. - ' + academy);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [dashboard(), studentPage(), attendancePage(), feePage(), marksPage(), reportPage()];
    return Scaffold(
      key: scaffoldKey,
      drawer: buildAppDrawer(),
      appBar: AppBar(
        leading: IconButton(onPressed: () => scaffoldKey.currentState?.openDrawer(),
          icon: const Icon(Icons.menu_rounded, color: Color(0xFF123B70))),
        title: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(['Dashboard', 'Students', 'Attendance', 'Fees', 'Marks', 'Reports'][tab],
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18)),
          const Text('AK Edu Point', style: TextStyle(fontSize: 11, color: Colors.black54)),
        ]),
        centerTitle: true,
        actions: [Padding(padding: const EdgeInsets.only(right: 10), child: IconButton(
          tooltip: 'My profile', onPressed: openProfile,
          icon: const CircleAvatar(radius: 18, backgroundColor: Color(0xFF2580E8),
            child: Icon(Icons.person, color: Colors.white, size: 23))))],
      ),
      body: loading ? const Center(child: CircularProgressIndicator()) : IndexedStack(index: tab, children: pages),
      floatingActionButton: tab == 1 ? FloatingActionButton.extended(onPressed: () => studentForm(), icon: const Icon(Icons.person_add), label: const Text('Add student'))
        : tab == 3 ? FloatingActionButton.extended(onPressed: addPayment, icon: const Icon(Icons.add), label: const Text('Add fee'))
        : tab == 4 ? FloatingActionButton.extended(onPressed: addMarks, icon: const Icon(Icons.add), label: const Text('Add marks')) : null,
      bottomNavigationBar: NavigationBar(selectedIndex: tab, onDestinationSelected: (v) async {
        if (v == 0) await refreshDashboardFromLocal();
        if (mounted) setState(() => tab = v);
      },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.groups_outlined), label: 'Students'),
          NavigationDestination(icon: Icon(Icons.fact_check_outlined), label: 'Attendance'),
          NavigationDestination(icon: Icon(Icons.currency_rupee), label: 'Fees'),
          NavigationDestination(icon: Icon(Icons.assignment_outlined), label: 'Marks'),
          NavigationDestination(icon: Icon(Icons.bar_chart_outlined), label: 'Reports')]),
    );
  }


  Widget buildAppDrawer() => Drawer(child: SafeArea(child: ListView(padding: EdgeInsets.zero, children: [
    Container(padding: const EdgeInsets.all(20), color: const Color(0xFFE8EEF9),
      child: Row(children: [
        teacherAvatar(30),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(teacherName, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          Text(academy, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.black54)),
          const SizedBox(height: 5),
          const Chip(label: Text('Teacher', style: TextStyle(color: Colors.white, fontSize: 12)),
            backgroundColor: Color(0xFF123B70), visualDensity: VisualDensity.compact),
        ])),
      ])),
    ListTile(leading: const Icon(Icons.person_outline), title: const Text('Profile'),
      trailing: const Icon(Icons.chevron_right), onTap: () { Navigator.pop(context); openProfile(); }),
    ListTile(leading: const Icon(Icons.groups_2_outlined), title: const Text('Batches & Programs'), trailing: const Icon(Icons.chevron_right), onTap: () { Navigator.pop(context); openBatchManager(); }),
    ListTile(leading: const Icon(Icons.calendar_month), title: const Text('LogBook'), trailing: const Icon(Icons.chevron_right), onTap: () { Navigator.pop(context); openLogBook(); }),
    ListTile(leading: const Icon(Icons.storage_outlined), title: const Text('Data & Storage'),
      trailing: const Icon(Icons.chevron_right), onTap: () { Navigator.pop(context); openDataStorage(); }),
    ListTile(leading: const Icon(Icons.currency_rupee), title: const Text('Currency'),
      trailing: const Icon(Icons.chevron_right), onTap: () { Navigator.pop(context); notice('Currency: Indian Rupee (₹)'); }),
    ListTile(leading: const Icon(Icons.settings_outlined), title: const Text('Settings'),
      trailing: const Icon(Icons.chevron_right), onTap: () { Navigator.pop(context); openSettings(); }),
    ListTile(leading: const Icon(Icons.feedback_outlined), title: const Text('Feedback'),
      trailing: const Icon(Icons.chevron_right), onTap: () { Navigator.pop(context); shareText('AK Edu Point feedback'); }),
    ListTile(leading: const Icon(Icons.info_outline), title: const Text('App Details'),
      trailing: const Icon(Icons.chevron_right), onTap: () { Navigator.pop(context); showAboutDialog(context: context, applicationName: 'AK Edu Point', applicationVersion: '1.0.0'); }),
    const Divider(indent: 18, endIndent: 18),
    ListTile(leading: const Icon(Icons.apps), title: const Text('App Features'),
      trailing: const Icon(Icons.chevron_right), onTap: () { Navigator.pop(context); showDialog<void>(context: context,
        builder: (ctx) => AlertDialog(title: const Text('App Features'),
          content: const Text('Student records\\nAttendance tracking\\nFee management\\nExam marks\\nReports\\nBackup and restore'),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))])); }),
    ListTile(leading: const Icon(Icons.logout, color: Colors.red), title: const Text('Sign out'),
      onTap: () async { Navigator.pop(context); await FirebaseService.signOut(); }),
  ])));

  Future<void> openProfile() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(
      appBar: AppBar(title: const Text('My Profile'), centerTitle: true),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Card(child: Padding(padding: const EdgeInsets.all(22), child: Column(children: [
          GestureDetector(onTap: changeTeacherPhoto, child: Stack(alignment: Alignment.bottomRight, children: [
            teacherAvatar(52), const CircleAvatar(radius: 15, child: Icon(Icons.camera_alt, size: 16)),
          ])),
          const SizedBox(height: 6), const Text('Tap photo to change', style: TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 18),
          Text(teacherName, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Chip(label: Text(academy), avatar: const Icon(Icons.apartment, size: 18)),
          const Chip(label: Text('Teacher'), backgroundColor: Color(0xFFDCE8FA)),
          const Divider(height: 28),
          ListTile(leading: const Icon(Icons.email_outlined), title: const Text('Email address'),
            subtitle: Text(FirebaseAuth.instance.currentUser?.email ?? 'Not available')),
          ListTile(leading: const Icon(Icons.school_outlined), title: const Text('Tuition / Academy'), subtitle: Text(academy)),
        ]))),
        const SizedBox(height: 18),
        const Text('ACCOUNT & SETTINGS', style: TextStyle(color: Color(0xFF123B70), fontWeight: FontWeight.w600)),
        Card(child: Column(children: [
          ListTile(leading: const Icon(Icons.person_outline), title: const Text('Edit Profile'),
            subtitle: const Text('Update your name'), trailing: const Icon(Icons.chevron_right), onTap: editTeacherName),
          ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Change profile photo'),
            subtitle: const Text('Choose an image up to 3 MB'), trailing: const Icon(Icons.chevron_right), onTap: changeTeacherPhoto),
          const Divider(height: 1),
          ListTile(leading: const Icon(Icons.settings_outlined), title: const Text('Preferences & Settings'),
            subtitle: const Text('Notifications and app preferences'), trailing: const Icon(Icons.chevron_right), onTap: openSettings),
          ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Tuition / Academy Name'), subtitle: Text(academy), onTap: editAcademy),
        ])),
        const SizedBox(height: 18),
        Card(child: ListTile(leading: const Icon(Icons.lock_reset), title: const Text('Change password'),
          subtitle: const Text('Send password reset link to your email'),
          trailing: const Icon(Icons.chevron_right), onTap: sendPasswordReset)),
        const SizedBox(height: 18),
        OutlinedButton.icon(onPressed: () async { await FirebaseService.signOut(); if (context.mounted) Navigator.pop(context); },
          icon: const Icon(Icons.logout), label: const Text('Sign out')),
      ]),
    )));
  }

  Future<void> editTeacherName() async {
    final user = FirebaseAuth.instance.currentUser;
    final controller = TextEditingController(text: teacherName);
    final value = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Edit profile name'),
      content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: 'Your name')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Save')),
      ],
    ));
    if (value != null && value.isNotEmpty && user != null) {
      await user.updateDisplayName(value);
      if (mounted) setState(() {});
    }
    controller.dispose();
  }

  Future<void> sendPasswordReset() async {
    final email = FirebaseAuth.instance.currentUser?.email;
    if (email == null) { notice('Account email not available.'); return; }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) notice('Password reset link sent to $email');
    } on FirebaseAuthException catch (e) {
      if (mounted) notice(e.message ?? 'Password reset email could not be sent.');
    }
  }

  Future<void> openDataStorage() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(
      appBar: AppBar(title: const Text('Data & Storage')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        const Text('Tuition records are saved on this phone and synced to your teacher account when internet is available. Keep a separate backup too.',
          style: TextStyle(color: Colors.black54)),
        const SizedBox(height: 18),
        Card(child: ListTile(leading: const Icon(Icons.cloud_sync_outlined), title: const Text('Sync now'), subtitle: const Text('Upload this device data to your teacher account'), onTap: () async { Navigator.pop(context); try { await FirebaseService.syncTuitionData(academy: academy, students: students, attendance: attendance, payments: payments, marks: marks); if (mounted) notice('Cloud sync completed.'); } catch (_) { if (mounted) notice('Sync nahi hua. Internet aur Firebase rules check karein.'); } })),
        Card(child: ListTile(leading: const Icon(Icons.backup_outlined), title: const Text('Create backup'),
          subtitle: const Text('Save or share students, attendance, fees and marks'),
          onTap: () { Navigator.pop(context); backupData(); })),
        Card(child: ListTile(leading: const Icon(Icons.restore), title: const Text('Restore backup'),
          subtitle: const Text('Restore records from an AK Edu Point JSON backup'),
          onTap: () { Navigator.pop(context); restoreData(); })),
        const Card(child: ListTile(leading: Icon(Icons.phone_android), title: Text('Storage location'),
          subtitle: Text('Local device cache plus teacher Firestore cloud copy after a successful sync. Keep a separate JSON backup too.'))),
      ]),
    )));
  }

  Widget stat(String title, String value, IconData icon, Color color) => Card(child: Padding(
    padding: const EdgeInsets.all(13), child: Column(crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Icon(icon, color: color),
        Text(value, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
        Text(title, style: const TextStyle(fontSize: 12, color: Colors.black54))])));
  Widget empty(String title, String hint) => Card(child: Padding(padding: const EdgeInsets.all(22),
    child: Column(children: [const Icon(Icons.inbox_outlined, size: 40), const SizedBox(height: 8),
      Text(title, style: const TextStyle(fontWeight: FontWeight.bold)), Text(hint, textAlign: TextAlign.center)])));
  Widget quick(String label, IconData icon, VoidCallback action) =>
    ActionChip(avatar: Icon(icon, size: 18), label: Text(label), onPressed: action);

  Widget dashboard() => ListView(padding: const EdgeInsets.all(16), children: [
    Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(borderRadius: BorderRadius.circular(18),
      gradient: const LinearGradient(colors: [Color(0xFF2457C5), Color(0xFF5287F0)])),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Welcome back!', style: TextStyle(color: Colors.white70)),
        const SizedBox(height: 8), Text(academy, style: const TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.bold)),
        Text('Today: ' + today, style: const TextStyle(color: Colors.white))])),
    const SizedBox(height: 16), const Text('Overview', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
    const SizedBox(height: 8), GridView.count(crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 1.5,
      children: [stat('Students', students.length.toString(), Icons.groups, Colors.blue),
        stat('Present today', present.toString(), Icons.how_to_reg, Colors.green),
        stat('Fee collected', rupees(collection), Icons.payments, Colors.orange),
        stat('Fee due', rupees(due), Icons.pending_actions, Colors.red)]),
    const SizedBox(height: 10), GridView.count(crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 1.8,
      children: [stat('Classes', classCount.toString(), Icons.menu_book_outlined, Colors.indigo), stat('Batches', batchCount.toString(), Icons.groups_2_outlined, Colors.teal), stat('Yearly collection', rupees(yearlyCollection), Icons.calendar_month, Colors.green), stat('Cash this month', rupees(cashCollection), Icons.money, Colors.brown), stat('Online this month', rupees(onlineCollection), Icons.phone_android, Colors.blue)]),
    const SizedBox(height: 16), const Text('Quick actions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    Wrap(spacing: 6, runSpacing: 6, children: [
      quick('Add student', Icons.person_add, () => studentForm()),
      quick('Attendance', Icons.fact_check, () => setState(() => tab = 2)),
      quick('Collect fee', Icons.currency_rupee, addPayment),
      quick('Add marks', Icons.assignment, addMarks), quick('LogBook', Icons.calendar_month, openLogBook), quick('Batches', Icons.groups_2, openBatchManager)]),
    const SizedBox(height: 16), const Text('Recent students', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    if (students.isEmpty) empty('No students yet', 'Add your first student to begin.')
      else ...students.take(4).map(studentTile)]);

  Widget studentPage() {
    final batches = <String>{'All', ...students.map((s) => (s['batch'] ?? 'General').toString())}.toList()..sort();
    final filtered = students.where((s) {
      final q = studentSearch.toLowerCase();
      final matches = s['name'].toString().toLowerCase().contains(q) ||
        s['class'].toString().toLowerCase().contains(q) ||
        (s['phone'] ?? '').toString().contains(q);
      return matches && (batchFilter == 'All' || (s['batch'] ?? 'General') == batchFilter);
    }).toList();
    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 90), children: [
      Text('Students • ${students.length}', style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
      const SizedBox(height: 10),
      TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search name, class or mobile', border: OutlineInputBorder()),
        onChanged: (v) => setState(() => studentSearch = v)),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(value: batches.contains(batchFilter) ? batchFilter : 'All',
        decoration: const InputDecoration(labelText: 'Filter by batch'),
        items: batches.map((b) => DropdownMenuItem(value: b, child: Text(b))).toList(),
        onChanged: (v) => setState(() => batchFilter = v ?? 'All')),
      const SizedBox(height: 10),
      if (filtered.isEmpty) empty('No students found', 'Add a student or change your search/filter.')
      else ...filtered.map(studentTile),
    ]);
  }

  Widget studentTile(Map<String, dynamic> s) => Card(margin: const EdgeInsets.only(bottom: 8), child: ListTile(
    onTap: () => openStudentDetails(s),
    leading: CircleAvatar(child: Text(s['name'].toString().isEmpty ? '?' : s['name'].toString()[0].toUpperCase())),
    title: Text(s['name'].toString(), style: const TextStyle(fontWeight: FontWeight.w600)),
    subtitle: Text('Class ${s['class']} • ${s['batch'] ?? 'General'} • Fee ${rupees(n(s['fee']))}'),
    trailing: PopupMenuButton<String>(onSelected: (v) {
      if (v == 'edit') studentForm(old: s);
      if (v == 'delete') deleteStudent(s);
      if (v == 'remind') feeReminder(s);
    }, itemBuilder: (_) => const [
      PopupMenuItem(value: 'edit', child: Text('Edit')),
      PopupMenuItem(value: 'remind', child: Text('Share fee reminder')),
      PopupMenuItem(value: 'delete', child: Text('Delete'))])));

  Future<void> openStudentDetails(Map<String, dynamic> s) async {
    final sid = s['id'];
    final paid = payments.where((p) => p['studentId'] == sid).fold(0, (v, p) => v + n(p['amount']));
    final history = attendance.where((a) => a['studentId'] == sid).toList()..sort((a,b) => b['date'].toString().compareTo(a['date'].toString()));
    final examRows = marks.where((m) => m['studentId'] == sid).toList();
    await Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(
      appBar: AppBar(title: const Text('Student Details'), actions: [
        IconButton(onPressed: () { Navigator.pop(context); studentForm(old: s); }, icon: const Icon(Icons.edit_outlined)),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(children: [
          CircleAvatar(radius: 34, child: Text(s['name'].toString().isEmpty ? '?' : s['name'].toString()[0].toUpperCase(), style: const TextStyle(fontSize: 26))),
          const SizedBox(height: 10), Text(s['name'].toString(), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          Text('Class ${s['class']} • ${s['batch'] ?? 'General'}'),
          Text('Parent: ${s['guardian'] ?? '—'} • Mobile: ${s['phone'] ?? '—'}'),
          const SizedBox(height: 6),
          Text('Joining date: ${s['joiningDate'] ?? 'Not recorded'}',
            style: const TextStyle(color: Colors.black54)),
        ]))),
        Row(children: [
          Expanded(child: stat('Monthly fee', rupees(n(s['fee'])), Icons.currency_rupee, Colors.blue)),
          Expanded(child: stat('Paid total', rupees(paid), Icons.payments, Colors.green)),
        ]),
        const Text('Attendance history', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        if (history.isEmpty) empty('No attendance records', 'Attendance will appear here.')
          else ...history.take(20).map((a) => ListTile(leading: Icon(a['status'] == 'Present' ? Icons.check_circle : Icons.cancel,
            color: a['status'] == 'Present' ? Colors.green : Colors.red), title: Text(a['date'].toString()), trailing: Text(a['status'].toString()))),
        const SizedBox(height: 12),
        const Text('Exam results', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        if (examRows.isEmpty) empty('No exam marks', 'Exam marks will appear here.')
          else ...examRows.map((m) => ListTile(title: Text('${m['exam']} • ${m['subject']}'), trailing: Text('${m['obtained']}/${m['total']}'))),
        OutlinedButton.icon(onPressed: () => feeReminder(s), icon: const Icon(Icons.share), label: const Text('Share fee reminder')),
      ]),
    )));
  }

  Widget attendancePage() => ListView(padding: const EdgeInsets.all(16), children: [
    const Text('Daily attendance', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
    Text('Date: ' + today, style: const TextStyle(color: Colors.black54)),
    Row(children: [Expanded(child: stat('Present', present.toString(), Icons.check_circle, Colors.green)),
      Expanded(child: stat('Absent', absent.toString(), Icons.cancel, Colors.red))]),
    if (students.isEmpty) empty('No students', 'Add students first.')
    else ...students.map((s) {
      final st = statusOf(s);
      return Card(child: ListTile(title: Text(s['name'].toString()), subtitle: Text('Class ' + s['class'].toString() + ' • ' + st),
        trailing: Wrap(children: [
          IconButton(onPressed: () => setAttendance(s, 'Present'), icon: Icon(Icons.check_circle, color: st == 'Present' ? Colors.green : Colors.grey)),
          IconButton(onPressed: () => setAttendance(s, 'Absent'), icon: Icon(Icons.cancel, color: st == 'Absent' ? Colors.red : Colors.grey))])));
    }),
    OutlinedButton.icon(onPressed: () => shareText(academy + ' attendance ' + today + '\nPresent: ' + present.toString() + '\nAbsent: ' + absent.toString()),
      icon: const Icon(Icons.share), label: const Text('Share attendance report'))]);

  Widget feePage() => ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 90), children: [
    const Text('Fee management', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
    Row(children: [Expanded(child: stat('Collected this month', rupees(collection), Icons.payments, Colors.green)),
      Expanded(child: stat('Fee due', rupees(due), Icons.pending, Colors.red))]),
    const Text('Payment history', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    if (payments.isEmpty) empty('No payments yet', 'Use Add fee to record a payment.')
    else ...payments.reversed.map((p) => Card(child: ListTile(
      leading: const CircleAvatar(child: Icon(Icons.currency_rupee)),
      title: Text(studentName(p['studentId'].toString())),
      subtitle: Text(p['note'].toString() + ' • ' + p['date'].toString() + ' • ' + (p['mode'] ?? 'Cash').toString()),
      trailing: Text(rupees(n(p['amount'])), style: const TextStyle(fontWeight: FontWeight.bold))))),
    OutlinedButton.icon(onPressed: () => shareText(academy + '\nCollected: ' + rupees(collection) + '\nDue: ' + rupees(due)),
      icon: const Icon(Icons.share), label: const Text('Share fee summary'))]);

  Widget marksPage() => ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 90), children: [
    const Text('Exam marks', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
    if (marks.isEmpty) empty('No marks yet', 'Tap Add marks to enter exam results.')
    else ...marks.reversed.map((m) {
      final total = n(m['total']), got = n(m['obtained']);
      final pct = total == 0 ? 0.0 : got * 100 / total;
      return Card(child: ListTile(leading: CircleAvatar(child: Text(pct.toStringAsFixed(0) + '%')),
        title: Text(studentName(m['studentId'].toString()) + ' • ' + m['subject'].toString()),
        subtitle: Text(m['exam'].toString() + ' • ' + m['date'].toString()),
        trailing: Text(got.toString() + '/' + total.toString())));
    })]);

  Widget reportLine(String title, String value) => Card(child: ListTile(title: Text(title), trailing: Text(value, style: const TextStyle(fontWeight: FontWeight.bold))));
  Widget reportPage() {
    final max = marks.fold<int>(0, (v, m) => v + n(m['total']));
    final got = marks.fold<int>(0, (v, m) => v + n(m['obtained']));
    final pct = max == 0 ? 0.0 : got * 100 / max;
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Reports', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
      reportLine('Total students', students.length.toString()),
      reportLine('Present today', present.toString()),
      reportLine('Absent today', absent.toString()),
      reportLine('Fee collected this month', rupees(collection)),
      reportLine('Outstanding fees', rupees(due)),
      reportLine('Exam records', marks.length.toString()),
      reportLine('Combined marks percentage', pct.toStringAsFixed(1) + '%'),
      OutlinedButton.icon(onPressed: backupData, icon: const Icon(Icons.backup_outlined), label: const Text('Backup data (save/share file)')),
      const SizedBox(height: 8),
      OutlinedButton.icon(onPressed: restoreData, icon: const Icon(Icons.restore), label: const Text('Restore from backup file')),
      const SizedBox(height: 8),
      FilledButton.icon(onPressed: () {
        final b = StringBuffer(academy + ' report\nDate: ' + today + '\n');
        b.writeln('Students: ' + students.length.toString());
        b.writeln('Present: ' + present.toString() + ' | Absent: ' + absent.toString());
        b.writeln('Fee collected: ' + rupees(collection) + ' | Due: ' + rupees(due));
        for (final s in students) { b.writeln(s['name'].toString() + ' - Class ' + s['class'].toString()); }
        shareText(b.toString());
      }, icon: const Icon(Icons.share), label: const Text('Share full report')),
      const SizedBox(height: 8),
      OutlinedButton.icon(onPressed: clearData, icon: const Icon(Icons.delete_outline), label: const Text('Clear all local data')),
      const Text('Records are cached on this phone and can sync to Firestore. Parent access requires the teacher to link the registered family email to a student.',
        style: TextStyle(fontSize: 12, color: Colors.black54))]);
  }

  Future<void> backupData() async {
    try {
      final backup = <String, dynamic>{
        'app': 'AK Edu Point', 'backupVersion': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'academy': academy, 'students': students, 'attendance': attendance,
        'payments': payments, 'marks': marks,
      };
      final bytes = Uint8List.fromList(utf8.encode(jsonEncode(backup)));
      await Share.shareXFiles(
        [XFile.fromData(bytes, name: 'ak-edu-point-backup.json', mimeType: 'application/json')],
        subject: 'AK Edu Point data backup',
        text: 'Keep this backup file safe. It contains student and tuition records.',
      );
    } catch (e) { notice('Backup share nahi ho saka: $e'); }
  }

  Future<void> restoreData() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['json'], withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;
      final bytes = picked.files.single.bytes;
      if (bytes == null) { notice('Backup file read nahi ho payi.'); return; }
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic> || decoded['app'] != 'AK Edu Point' ||
          decoded['backupVersion'] != 1 || decoded['students'] is! List ||
          decoded['attendance'] is! List || decoded['payments'] is! List ||
          decoded['marks'] is! List) {
        notice('Ye valid AK Edu Point backup file nahi hai.'); return;
      }
      final yes = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Restore backup?'),
        content: const Text('Current app data replace ho jayega. Pehle current data ka backup zaroor bana lein.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Restore')),
        ],
      ));
      if (yes != true) return;
      academy = decoded['academy']?.toString() ?? 'AK Edu Point';
      profilePhotoBase64 = decoded['profilePhotoBase64']?.toString();
      students = mapList(decoded['students']); attendance = mapList(decoded['attendance']);
      payments = mapList(decoded['payments']); marks = mapList(decoded['marks']);
      await save();
      if (mounted) notice('Backup restore ho gaya. Records: ${students.length} students.');
    } catch (_) { notice('Restore nahi ho saka. Sahi backup JSON file select karein.'); }
  }

  Future<void> clearData() async {
    final yes = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Clear all data?'),
      content: const Text('This permanently removes students, attendance, fees and marks from this phone.'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear all'))]));
    if (yes == true) { students.clear(); attendance.clear(); payments.clear(); marks.clear(); await save(); notice('Data cleared.'); }
  }
}
