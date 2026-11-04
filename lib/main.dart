import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const AkEduPointApp());
}

class AkEduPointApp extends StatelessWidget {
  const AkEduPointApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'AK Edu Point', debugShowCheckedModeBanner: false,
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2457C5)), useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFFF5F7FB)),
    home: const TuitionHome());
}

class TuitionHome extends StatefulWidget {
  const TuitionHome({super.key});
  @override
  State<TuitionHome> createState() => _TuitionHomeState();
}

class _TuitionHomeState extends State<TuitionHome> {
  static const storeKey = 'ak_edu_point_v1';
  int tab = 0;
  bool loading = true;
  String academy = 'AK Edu Point';
  List<Map<String, dynamic>> students = [], attendance = [], payments = [], marks = [];
  String get today => dateKey(DateTime.now());
  String dateKey(DateTime d) => d.year.toString().padLeft(4, '0') + '-' +
    d.month.toString().padLeft(2, '0') + '-' + d.day.toString().padLeft(2, '0');
  int n(dynamic v) => int.tryParse(v?.toString() ?? '') ?? 0;
  String rupees(int v) => '₹' + v.toString();
  List<Map<String, dynamic>> mapList(dynamic v) => v is List
    ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : [];

  @override
  void initState() { super.initState(); load(); }

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(storeKey);
    if (raw != null) {
      try {
        final d = jsonDecode(raw) as Map<String, dynamic>;
        academy = d['academy']?.toString() ?? academy;
        students = mapList(d['students']); attendance = mapList(d['attendance']);
        payments = mapList(d['payments']); marks = mapList(d['marks']);
      } catch (_) {}
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(storeKey, jsonEncode({'academy': academy, 'students': students,
      'attendance': attendance, 'payments': payments, 'marks': marks}));
    if (mounted) setState(() {});
  }

  int get present => attendance.where((a) => a['date'] == today && a['status'] == 'Present').length;
  int get absent => attendance.where((a) => a['date'] == today && a['status'] == 'Absent').length;
  int get collection {
    final month = today.substring(0, 7);
    return payments.where((p) => (p['date']?.toString() ?? '').startsWith(month))
      .fold(0, (v, p) => v + n(p['amount']));
  }
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
    final fee = TextEditingController(text: old?['fee']?.toString() ?? '');
    final key = GlobalKey<FormState>();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: Text(old == null ? 'Add student' : 'Edit student'),
      content: Form(key: key, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        input(name, 'Student name', required: true), input(cls, 'Class', required: true),
        input(phone, 'Mobile number', type: TextInputType.phone), input(guardian, 'Parent / guardian'),
        input(fee, 'Monthly fee ₹', type: TextInputType.number)]))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () { if (key.currentState!.validate()) Navigator.pop(ctx, true); }, child: const Text('Save'))]));
    if (ok == true) {
      final id = old?['id']?.toString() ?? DateTime.now().microsecondsSinceEpoch.toString();
      final row = <String, dynamic>{'id': id, 'name': name.text.trim(), 'class': cls.text.trim(),
        'phone': phone.text.trim(), 'guardian': guardian.text.trim(), 'fee': n(fee.text)};
      final i = students.indexWhere((s) => s['id'] == id);
      if (i < 0) { students.add(row); } else { students[i] = row; }
      await save();
    }
    name.dispose(); cls.dispose(); phone.dispose(); guardian.dispose(); fee.dispose();
  }

  Future<void> deleteStudent(Map<String, dynamic> s) async {
    final yes = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Delete student?'), content: Text('Remove ' + s['name'].toString() + '?'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete'))]));
    if (yes == true) { students.removeWhere((x) => x['id'] == s['id']); await save(); }
  }

  String statusOf(Map<String, dynamic> s) {
    final a = attendance.where((x) => x['studentId'] == s['id'] && x['date'] == today);
    return a.isEmpty ? 'Not marked' : a.first['status'].toString();
  }
  Future<void> setAttendance(Map<String, dynamic> s, String status) async {
    final i = attendance.indexWhere((a) => a['studentId'] == s['id'] && a['date'] == today);
    final row = <String, dynamic>{'studentId': s['id'], 'date': today, 'status': status};
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
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Record fee'), content: Form(key: key, child: Column(mainAxisSize: MainAxisSize.min, children: [
        input(amount, 'Amount ₹', required: true, type: TextInputType.number), input(note, 'Note')])),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () { if (key.currentState!.validate() && n(amount.text) > 0) Navigator.pop(ctx, true); }, child: const Text('Save'))]));
    if (ok == true) {
      payments.add({'id': DateTime.now().microsecondsSinceEpoch.toString(), 'studentId': id,
        'amount': n(amount.text), 'note': note.text.trim(), 'date': today});
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
      appBar: AppBar(title: Text(academy, style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [IconButton(onPressed: editAcademy, icon: const Icon(Icons.settings_outlined))]),
      body: loading ? const Center(child: CircularProgressIndicator()) : IndexedStack(index: tab, children: pages),
      floatingActionButton: tab == 1 ? FloatingActionButton.extended(onPressed: () => studentForm(), icon: const Icon(Icons.person_add), label: const Text('Add student'))
        : tab == 3 ? FloatingActionButton.extended(onPressed: addPayment, icon: const Icon(Icons.add), label: const Text('Add fee'))
        : tab == 4 ? FloatingActionButton.extended(onPressed: addMarks, icon: const Icon(Icons.add), label: const Text('Add marks')) : null,
      bottomNavigationBar: NavigationBar(selectedIndex: tab, onDestinationSelected: (v) => setState(() => tab = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.groups_outlined), label: 'Students'),
          NavigationDestination(icon: Icon(Icons.fact_check_outlined), label: 'Attendance'),
          NavigationDestination(icon: Icon(Icons.currency_rupee), label: 'Fees'),
          NavigationDestination(icon: Icon(Icons.assignment_outlined), label: 'Marks'),
          NavigationDestination(icon: Icon(Icons.bar_chart_outlined), label: 'Reports')]),
    );
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
    const SizedBox(height: 16), const Text('Quick actions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    Wrap(spacing: 6, runSpacing: 6, children: [
      quick('Add student', Icons.person_add, () => studentForm()),
      quick('Attendance', Icons.fact_check, () => setState(() => tab = 2)),
      quick('Collect fee', Icons.currency_rupee, addPayment),
      quick('Add marks', Icons.assignment, addMarks)]),
    const SizedBox(height: 16), const Text('Recent students', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    if (students.isEmpty) empty('No students yet', 'Add your first student to begin.')
      else ...students.take(4).map(studentTile)]);

  Widget studentPage() => ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 90), children: [
    Text('Students • ' + students.length.toString(), style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
    const SizedBox(height: 10), if (students.isEmpty) empty('No students', 'Tap Add student to begin.')
      else ...students.map(studentTile)]);

  Widget studentTile(Map<String, dynamic> s) => Card(margin: const EdgeInsets.only(bottom: 8), child: ListTile(
    leading: CircleAvatar(child: Text(s['name'].toString().isEmpty ? '?' : s['name'].toString()[0].toUpperCase())),
    title: Text(s['name'].toString(), style: const TextStyle(fontWeight: FontWeight.w600)),
    subtitle: Text('Class ' + s['class'].toString() + ' • Fee ' + rupees(n(s['fee']))),
    trailing: PopupMenuButton<String>(onSelected: (v) {
      if (v == 'edit') studentForm(old: s);
      if (v == 'delete') deleteStudent(s);
      if (v == 'remind') feeReminder(s);
    }, itemBuilder: (_) => const [
      PopupMenuItem(value: 'edit', child: Text('Edit')),
      PopupMenuItem(value: 'remind', child: Text('Share fee reminder')),
      PopupMenuItem(value: 'delete', child: Text('Delete'))])));

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
      subtitle: Text(p['note'].toString() + ' • ' + p['date'].toString()),
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
      const Text('Data is saved on this phone only. Cloud sync and secure parent login require backend setup.',
        style: TextStyle(fontSize: 12, color: Colors.black54))]);
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
