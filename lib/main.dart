import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:math_expressions/math_expressions.dart';
import 'package:path/path.dart';
import 'package:intl/intl.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    runApp(const CalculatorApp());
  } catch (e) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text('Firebase init failed: $e'),
          ),
        ),
      ),
    );
  }
}

class CalculatorModel with ChangeNotifier{
  String _display = '0';
  final HistoryDatabase _historyDatabase = HistoryDatabase();
  bool _shouldResetDisplay = false;

  String get display => _display;

  Future<void> handleButtonPress(String value) async {
    if (value == 'C') {
      _clearAll();
    } else if (value == '⌫') {
      _backspace();
    } else if (value == '.') {
      _addDecimal();
    } else if (value == '=') {
      await _calculate();
    } else if (_isOperator(value)) {
      _appendOperator(value);
    } else {
      _appendDigit(value);
    }
    notifyListeners();
  }

  bool _isOperator(String value) => ['+', '-', '×', '÷'].contains(value);

  void _clearAll() {
    _display = '0';
    _shouldResetDisplay = false;
  }

  void _backspace() {
    if (_display.length == 1 || (_display.length == 2 && _display.startsWith('-'))) {
      _display = '0';
    } else {
      _display = _display.substring(0, _display.length - 1);
    }
  }

  void _addDecimal() {
    if (_shouldResetDisplay) {
      _display = '0.';
      _shouldResetDisplay = false;
      return;
    }

    // Find the last number in the expression
    final parts = _display.split(RegExp(r'[+\-×÷]'));
    final lastNumber = parts.last;

    if (!lastNumber.contains('.')) {
      _display += '.';
    }
  }

  void _appendDigit(String digit) {
    if (_shouldResetDisplay) {
      _display = digit;
      _shouldResetDisplay = false;
    } else if (_display == '0') {
      _display = digit;
    } else {
      _display += digit;
    }
  }

  void _appendOperator(String operator) {
    if (_shouldResetDisplay) {
      _display = _display.substring(0, _display.length - 1) + operator;
      return;
    }

    // Don't allow operators at the start (except minus)
    if (_display == '0' && operator != '-') return;

    // Replace the last operator if one exists
    final lastChar = _display[_display.length - 1];
    if (_isOperator(lastChar)) {
      _display = _display.substring(0, _display.length - 1) + operator;
    } else {
      _display += operator;
    }
  }

  Future<void> _calculate() async {
    try {
      String expression = _display
          .replaceAll('×', '*')
          .replaceAll('÷', '/');

      Parser p = Parser();
      Expression exp = p.parse(expression);
      ContextModel cm = ContextModel();
      double result = exp.evaluate(EvaluationType.REAL, cm);

      await _historyDatabase.insertHistory(
        HistoryItem(
          calculation: '$_display = $result',
          timestamp: DateTime.now(),
        ),
      );

      if (result % 1 == 0) {
        _display = result.toInt().toString();
      } else {
        _display = result.toString();
      }

      _shouldResetDisplay = true;
    } catch (e) {
      _display = 'Error';
      _shouldResetDisplay = true;
    }
  }
}

class HistoryItem {
  final String? id;
  final String calculation;
  final DateTime timestamp;

  HistoryItem({
    this.id,
    required this.calculation,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'calculation': calculation,
      'timestamp': timestamp,
    };
  }

  factory HistoryItem.fromMap(Map<String, dynamic> map) {
    return HistoryItem(
      id: map['id'],
      calculation: map['calculation'],
      timestamp: DateTime.parse(map['timestamp']),
    );
  }

  String get formattedDate {
    return DateFormat('yyyy-MM-dd HH:mm').format(timestamp);
  }
}

class HistoryDatabase {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<void> insertHistory(HistoryItem item) async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('calculator_history')
        .add({
      'calculation': item.calculation,
      'timestamp': item.timestamp,
    });
  }

  Future<List<HistoryItem>> getAllHistory() async {
    final user = _auth.currentUser;
    if (user == null) return [];

    final snapshot = await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('calculator_history')
        .orderBy('timestamp', descending: true)
        .get();

    return snapshot.docs.map((doc) {
      return HistoryItem(
        id: doc.id,
        calculation: doc['calculation'],
        timestamp: (doc['timestamp'] as Timestamp).toDate(),
      );
    }).toList();
  }

  Future<void> deleteHistory(String id) async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('calculator_history')
        .doc(id)
        .delete();
  }

  Future<void> clearAllHistory() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final snapshot = await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('calculator_history')
        .get();

    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }
}

class CalculatorUI extends StatefulWidget {
  const CalculatorUI({super.key});

  @override
  _CalculatorUIState createState() => _CalculatorUIState();
}

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<User?> signInAnonymously() async {
    try {
      final userCredential = await _auth.signInAnonymously();
      return userCredential.user;
    } catch (e) {
      print("Error signing in anonymously: $e");
      return null;
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  User? get currentUser => _auth.currentUser;
}

class _CalculatorUIState extends State<CalculatorUI> {
  final CalculatorModel _model = CalculatorModel();
  final AuthService _auth = AuthService();
  bool _isSignedIn = false;

  @override
  void initState() {
    super.initState();
    _checkAuthState();
    _model.addListener(_updateUI);
  }

  @override
  void dispose() {
    _model.removeListener(_updateUI);
    super.dispose();
  }

  void _updateUI() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _checkAuthState() async {
    await _auth.signInAnonymously();
    setState(() {
      _isSignedIn = _auth.currentUser != null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isSignedIn) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calculator'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const HistoryScreen()),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              alignment: Alignment.bottomRight,
              padding: const EdgeInsets.all(24),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Text(
                  _model.display,
                  style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w300),
                ),
              ),
            ),
          ),
          GridView.count(
            shrinkWrap: true,
            crossAxisCount: 4,
            childAspectRatio: 1.2,
            padding: const EdgeInsets.all(8),
            children: _buildButtons(),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const KilometerToMileConverter()),
                );
              },
              child: const Text('Go to Kilometer to Mile Converter'),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildButtons() {
    const buttonTexts = [
      'C', '⌫', '÷', '×',
      '7', '8', '9', '-',
      '4', '5', '6', '+',
      '1', '2', '3', '=',
      '.', '0', '', '',
    ];

    return buttonTexts.map((text) {
      if (text.isEmpty) {
        return const SizedBox.shrink();
      }

      return Padding(
        padding: const EdgeInsets.all(4.0),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: _getButtonColor(text),
            foregroundColor: _getTextColor(text),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            textStyle: const TextStyle(fontSize: 24),
          ),
          onPressed: () => _model.handleButtonPress(text),  // Remove setState here
          child: Text(text),
        ),
      );
    }).toList();
  }

  Color _getButtonColor(String text) {
    if (text == 'C') return Colors.redAccent;
    if (text == '⌫' || text == '÷' || text == '×' || text == '-' || text == '+') return Colors.blueGrey;
    if (text == '=') return Colors.blueAccent;
    return Colors.grey[200]!;
  }

  Color _getTextColor(String text) {
    if (text == 'C' || text == '⌫' || text == '=') return Colors.white;
    return Colors.black;
  }
}

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  _HistoryScreenState createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final HistoryDatabase _database = HistoryDatabase();
  late Future<List<HistoryItem>> _historyFuture;

  @override
  void initState() {
    super.initState();
    _historyFuture = _database.getAllHistory();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calculation History'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: _confirmClearHistory,
          ),
        ],
      ),
      body: FutureBuilder<List<HistoryItem>>(
        future: _historyFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No history yet'));
          } else {
            return ListView.builder(
              itemCount: snapshot.data!.length,
              itemBuilder: (context, index) {
                final item = snapshot.data![index];
                return Dismissible(
                  key: Key(item.id.toString()),
                  background: Container(color: Colors.red),
                  onDismissed: (direction) {
                    _database.deleteHistory(item.id! as String);
                    setState(() {
                      _historyFuture = _database.getAllHistory();
                    });
                  },
                  child: ListTile(
                    title: Text(item.calculation),
                    subtitle: Text(item.formattedDate),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                    },
                  ),
                );
              },
            );
          }
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.pop(context);
        },
        child: const Icon(Icons.arrow_back),
      ),
    );
  }

  Future<void> _confirmClearHistory() async {
    final BuildContext currentContext = context as BuildContext;

    final confirmed = await showDialog<bool>(
      context: currentContext,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Clear History'),
        content: const Text('Are you sure you want to delete all history?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _database.clearAllHistory();
      if (mounted) {
        setState(() {
          _historyFuture = _database.getAllHistory();
        });
      }
    }
  }
}

class CalculatorApp extends StatelessWidget {
  const CalculatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Calculator',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const CalculatorUI(),
    );
  }
}

class KilometerToMileConverter extends StatefulWidget {
  const KilometerToMileConverter({super.key});

  @override
  _KilometerToMileConverterState createState() => _KilometerToMileConverterState();
}

class _KilometerToMileConverterState extends State<KilometerToMileConverter> {
  final TextEditingController _kmController = TextEditingController();
  String result = '';
  bool isConverting = false;

  void convertToMiles() {
    setState(() {
      isConverting = true;
    });

    double km = double.tryParse(_kmController.text) ?? 0;
    setState(() {
      result = '${(km * 0.621371).toStringAsFixed(2)} miles';
      isConverting = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kilometer to Mile Converter'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _kmController,
              decoration: const InputDecoration(
                labelText: 'Enter distance in kilometers',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.straighten),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: isConverting ? null : convertToMiles,
              child: isConverting
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Convert'),
            ),
            const SizedBox(height: 20),
            if (result.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    result,
                    style: const TextStyle(fontSize: 24),
                  ),
                ),
              ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                backgroundColor: Colors.grey[300],
                foregroundColor: Colors.black,
              ),
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Back to Calculator'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _kmController.dispose();
    super.dispose();
  }
}