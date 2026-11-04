import 'package:flutter/material.dart';

void main() {
  runApp(const AkEduPointApp());
}

class AkEduPointApp extends StatelessWidget {
  const AkEduPointApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AK Edu Point',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2457C5)),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF5F7FB),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int selectedIndex = 0;

  final List<Student> students = [
    Student('Aarav Kumar', 'Class 8', '₹500'),
    Student('Priya Kumari', 'Class 10', '₹700'),
    Student('Rohit Kumar', 'Class 7', '₹500'),
    Student('Neha Kumari', 'Class 9', '₹600'),
  ];

  @override
  Widget build(BuildContext context) {
    final pages = [
      _dashboard(),
      _studentsPage(),
      _simplePage('Attendance', Icons.fact_check_outlined,
          'Mark and review daily student attendance.'),
      _simplePage('Fees', Icons.currency_rupee,
          'Track paid fees and pending balances.'),
      _simplePage('Profile', Icons.person_outline,
          'Manage your AK Edu Point account.'),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('AK Edu Point',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Notifications',
            onPressed: () => _showMessage('Notifications will appear here.'),
            icon: const Icon(Icons.notifications_none),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(child: pages[selectedIndex]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) =>
            setState(() => selectedIndex = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.groups_outlined), label: 'Students'),
          NavigationDestination(
              icon: Icon(Icons.fact_check_outlined), label: 'Attendance'),
          NavigationDestination(
              icon: Icon(Icons.currency_rupee), label: 'Fees'),
          NavigationDestination(
              icon: Icon(Icons.person_outline), label: 'Profile'),
        ],
      ),
    );
  }

  Widget _dashboard() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              colors: [Color(0xFF2457C5), Color(0xFF5287F0)],
            ),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Welcome back!',
                  style: TextStyle(color: Colors.white70, fontSize: 15)),
              SizedBox(height: 8),
              Text('AK Edu Point',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 25,
                      fontWeight: FontWeight.bold)),
              SizedBox(height: 6),
              Text('Your tuition, organised in one place.',
                  style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Text('Overview',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.55,
          children: const [
            SummaryCard(
                title: 'Total Students',
                value: '4',
                icon: Icons.groups,
                color: Color(0xFF2457C5)),
            SummaryCard(
                title: 'Present Today',
                value: '0',
                icon: Icons.how_to_reg,
                color: Color(0xFF16865B)),
            SummaryCard(
                title: 'Fees Collected',
                value: '₹0',
                icon: Icons.payments,
                color: Color(0xFFB56A12)),
            SummaryCard(
                title: 'Pending Fees',
                value: '₹2,300',
                icon: Icons.pending_actions,
                color: Color(0xFFB33A4A)),
          ],
        ),
        const SizedBox(height: 22),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Recent Students',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
            TextButton(
              onPressed: () => setState(() => selectedIndex = 1),
              child: const Text('View all'),
            ),
          ],
        ),
        ...students.take(3).map(_studentTile),
      ],
    );
  }

  Widget _studentsPage() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Students',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            FilledButton.icon(
              onPressed: _addStudent,
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (students.isEmpty)
          const Center(child: Padding(
            padding: EdgeInsets.all(30),
            child: Text('No students added yet. Tap Add to begin.'),
          ))
        else
          ...students.map(_studentTile),
      ],
    );
  }

  Widget _studentTile(Student student) {
    return Card(
      color: Colors.white,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: const Color(0xFFE5ECFF),
          child: Text(student.name.isNotEmpty ? student.name[0] : '?',
              style: const TextStyle(
                  color: Color(0xFF2457C5), fontWeight: FontWeight.bold)),
        ),
        title: Text(student.name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(student.studentClass),
        trailing: Text(student.fee,
            style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _simplePage(String title, IconData icon, String description) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 58, color: const Color(0xFF2457C5)),
            const SizedBox(height: 16),
            Text(title,
                style:
                    const TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(description, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Future<void> _addStudent() async {
    final nameController = TextEditingController();
    final classController = TextEditingController();
    final feeController = TextEditingController();
    final added = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add student'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Student name'),
              ),
              TextField(
                controller: classController,
                decoration: const InputDecoration(labelText: 'Class'),
              ),
              TextField(
                controller: feeController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Monthly fee'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (added == true && nameController.text.trim().isNotEmpty) {
      setState(() {
        students.add(Student(
          nameController.text.trim(),
          classController.text.trim().isEmpty
              ? 'Class not set'
              : classController.text.trim(),
          feeController.text.trim().isEmpty
              ? '₹0'
              : '₹${feeController.text.trim()}',
        ));
      });
    }
    nameController.dispose();
    classController.dispose();
    feeController.dispose();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class Student {
  Student(this.name, this.studentClass, this.fee);

  final String name;
  final String studentClass;
  final String fee;
}

class SummaryCard extends StatelessWidget {
  const SummaryCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, color: color),
            Text(value,
                style:
                    const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
            Text(title,
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ],
        ),
      ),
    );
  }
}
