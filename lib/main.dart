import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/intl.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'services/finance_service.dart';
import 'models/finance/account.dart';
import 'models/finance/aggregate.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

// ---------------------------------------------------------------------------
// Indian currency formatter: Rs 1,23,456
// ---------------------------------------------------------------------------
String formatINR(double amount) {
  final isNegative = amount < 0;
  final abs = amount.abs();

  if (abs < 1000) {
    final formatted = abs.toStringAsFixed(0);
    return '${isNegative ? '-' : ''}Rs $formatted';
  }

  final intPart = abs.truncate().toString();
  final last3 = intPart.substring(intPart.length - 3);
  String remaining = intPart.substring(0, intPart.length - 3);

  final buffer = StringBuffer();
  while (remaining.length > 2) {
    buffer.write('${remaining.substring(0, remaining.length - 2)},');
    remaining = remaining.substring(remaining.length - 2);
  }
  if (remaining.isNotEmpty) {
    final result = '${buffer.toString()}$remaining,$last3';
    return '${isNegative ? '-' : ''}Rs $result';
  }

  return '${isNegative ? '-' : ''}Rs ${buffer.toString()}$last3';
}

// ---------------------------------------------------------------------------
// App Theme
// ---------------------------------------------------------------------------
const Color kPrimaryColor = Color(0xFF0D47A1);
const Color kPrimaryLight = Color(0xFF1565C0);
const Color kAccentColor = Color(0xFF00897B);
const Color kCreditGreen = Color(0xFF2E7D32);
const Color kDebitRed = Color(0xFFC62828);
const Color kSurfaceLight = Color(0xFFF5F7FA);

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MoneyTest',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: kPrimaryColor,
          primary: kPrimaryColor,
          secondary: kAccentColor,
          surface: Colors.white,
        ),
        scaffoldBackgroundColor: kSurfaceLight,
        appBarTheme: const AppBarTheme(
          backgroundColor: kPrimaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        ),
      ),
      home: const RootPage(),
    );
  }
}

// ===========================================================================
// Root — linear flow controller
// ===========================================================================
class RootPage extends StatefulWidget {
  const RootPage({super.key});

  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  final AuthService _authService = AuthService();
  late final FinanceService _financeService;
  bool _initializing = true;

  @override
  void initState() {
    super.initState();
    _financeService = FinanceService(authService: _authService);
    _initAuth();
  }

  Future<void> _initAuth() async {
    await _authService.init();
    if (mounted) setState(() => _initializing = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_initializing) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_authService.isSignedIn) {
      return SignInPage(
        onSignedIn: () {
          if (mounted) setState(() {});
        },
        authService: _authService,
      );
    }

    // Already signed in — go straight to DOB page (which auto-skips if already set)
    return DOBPage(
      authService: _authService,
      financeService: _financeService,
    );
  }
}

// ===========================================================================
// PAGE 1: Sign In
// ===========================================================================
class SignInPage extends StatefulWidget {
  final VoidCallback onSignedIn;
  final AuthService authService;

  const SignInPage({
    super.key,
    required this.onSignedIn,
    required this.authService,
  });

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  bool _isLoading = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final user = await widget.authService.signInWithGoogle();
      if (user != null) {
        widget.onSignedIn();
      } else {
        if (mounted) setState(() => _error = 'Sign in was cancelled');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Sign in failed: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.account_balance_wallet, size: 80, color: kPrimaryColor),
              const SizedBox(height: 24),
              const Text(
                'MoneyTest',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: kPrimaryColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Track your spending from email',
                style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _signIn,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.login),
                  label: Text(
                    _isLoading ? 'Signing in...' : 'Sign in with Google',
                    style: const TextStyle(fontSize: 16),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: const TextStyle(color: kDebitRed, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// PAGE 2: Date of Birth (optional, skippable)
// ===========================================================================
class DOBPage extends StatefulWidget {
  final AuthService authService;
  final FinanceService financeService;

  const DOBPage({
    super.key,
    required this.authService,
    required this.financeService,
  });

  @override
  State<DOBPage> createState() => _DOBPageState();
}

class _DOBPageState extends State<DOBPage> {
  DateTime? _selectedDate;
  bool _isSaving = false;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _checkExistingDOB();
  }

  Future<void> _checkExistingDOB() async {
    final hasDOB = await widget.authService.hasDateOfBirth();
    if (hasDOB && mounted) {
      // Already has DOB, skip straight to scan
      _goToScan();
      return;
    }
    if (mounted) setState(() => _checking = false);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(1995, 1, 1),
      firstDate: DateTime(1940),
      lastDate: DateTime.now(),
      helpText: 'Select your date of birth',
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _saveDOB() async {
    if (_selectedDate == null) return;
    setState(() => _isSaving = true);
    try {
      await widget.authService.storeDateOfBirth(_selectedDate!);
      _goToScan();
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    }
  }

  void _goToScan() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ScanProgressPage(
          authService: widget.authService,
          financeService: widget.financeService,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              const Spacer(),
              Icon(Icons.lock_open, size: 64, color: kPrimaryColor),
              const SizedBox(height: 24),
              const Text(
                'Unlock Bank Statements',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: kPrimaryColor,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Indian banks use your date of birth as the password for PDF statements. '
                'Enter it to auto-unlock them.',
                style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today, color: Colors.grey.shade600),
                      const SizedBox(width: 12),
                      Text(
                        _selectedDate != null
                            ? DateFormat('d MMMM yyyy').format(_selectedDate!)
                            : 'Tap to select date of birth',
                        style: TextStyle(
                          fontSize: 16,
                          color: _selectedDate != null
                              ? Colors.black87
                              : Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _selectedDate == null || _isSaving ? null : _saveDOB,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Save & Continue', style: TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _isSaving ? null : _goToScan,
                child: Text(
                  'Skip for now',
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// PAGE 3: Scan Progress
// ===========================================================================
class ScanProgressPage extends StatefulWidget {
  final AuthService authService;
  final FinanceService financeService;

  const ScanProgressPage({
    super.key,
    required this.authService,
    required this.financeService,
  });

  @override
  State<ScanProgressPage> createState() => _ScanProgressPageState();
}

class _ScanProgressPageState extends State<ScanProgressPage> {
  int _processedCount = 0;
  int _totalEstimate = 0;
  bool _isComplete = false;
  String? _error;
  String _statusText = 'Preparing to scan emails...';

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  Future<void> _startScan() async {
    try {
      setState(() => _statusText = 'Fetching financial emails from the past 6 months...');

      await widget.financeService.analyzeAllFinance(
        batchSize: 10,
        onProgress: (processed, total) {
          if (mounted) {
            setState(() {
              _processedCount = processed;
              _totalEstimate = total;
              _statusText = 'Processing emails... $processed of ~$total';
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _isComplete = true;
          _statusText = 'Scan complete!';
        });

        // Brief delay so user sees "complete" before navigating
        await Future.delayed(const Duration(milliseconds: 800));
        _goToResults();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _statusText = 'Scan failed';
        });
      }
    }
  }

  void _goToResults() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ResultsPage(
          authService: widget.authService,
          financeService: widget.financeService,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final progress = _totalEstimate > 0
        ? (_processedCount / _totalEstimate).clamp(0.0, 1.0)
        : null;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (!_isComplete && _error == null) ...[
                  const SizedBox(
                    width: 64,
                    height: 64,
                    child: CircularProgressIndicator(
                      strokeWidth: 4,
                      color: kPrimaryColor,
                    ),
                  ),
                ] else if (_isComplete) ...[
                  Icon(Icons.check_circle, size: 64, color: kCreditGreen),
                ] else ...[
                  Icon(Icons.error_outline, size: 64, color: kDebitRed),
                ],
                const SizedBox(height: 32),
                Text(
                  _statusText,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: _error != null ? kDebitRed : Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                if (progress != null && !_isComplete && _error == null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 10,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: const AlwaysStoppedAnimation<Color>(kPrimaryColor),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$_processedCount / $_totalEstimate emails',
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                    textAlign: TextAlign.center,
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _error = null;
                            _processedCount = 0;
                            _totalEstimate = 0;
                            _isComplete = false;
                          });
                          _startScan();
                        },
                        child: const Text('Retry'),
                      ),
                      const SizedBox(width: 16),
                      TextButton(
                        onPressed: _goToResults,
                        child: const Text('Skip'),
                      ),
                      const SizedBox(width: 16),
                      TextButton(
                        onPressed: () async {
                          await widget.authService.signOut();
                          if (mounted) {
                            Navigator.of(context).pushAndRemoveUntil(
                              MaterialPageRoute(builder: (_) => const RootPage()),
                              (route) => false,
                            );
                          }
                        },
                        child: const Text('Sign Out'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// PAGE 4: Results — Accounts summary + AI Chat
// ===========================================================================
class ResultsPage extends StatefulWidget {
  final AuthService authService;
  final FinanceService financeService;

  const ResultsPage({
    super.key,
    required this.authService,
    required this.financeService,
  });

  @override
  State<ResultsPage> createState() => _ResultsPageState();
}

class _ResultsPageState extends State<ResultsPage> {
  // Data
  List<Account> _accounts = [];
  MonthlyAggregate? _currentMonth;
  bool _isLoadingData = true;

  // Chat state
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [];
  String? _sessionId;
  bool _isSending = false;

  static const List<String> _suggestedQuestions = [
    'How much did I spend this month?',
    'What are my recurring payments?',
    'Top merchants by spend?',
    'Compare this month with last month',
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final now = DateTime.now();
      final currentPeriod = '${now.year}-${now.month.toString().padLeft(2, '0')}';

      final results = await Future.wait([
        widget.financeService.getAccounts(),
        widget.financeService.getMonthlyAggregate(currentPeriod),
      ]);

      if (mounted) {
        setState(() {
          _accounts = results[0] as List<Account>;
          _currentMonth = results[1] as MonthlyAggregate?;
          _isLoadingData = false;
        });
      }
    } catch (e) {
      debugPrint('[ResultsPage] Error loading data: $e');
      if (mounted) setState(() => _isLoadingData = false);
    }
  }

  // --- Chat methods ---

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    setState(() {
      _messages.add(_ChatMessage(text: text, isUser: true));
      _isSending = true;
    });
    _textController.clear();
    _scrollToBottom();

    try {
      final response = await widget.financeService.askAI(
        text,
        sessionId: _sessionId,
      );

      final answer = response['answer'] as String? ??
          'Sorry, I could not process that question.';
      _sessionId = response['sessionId'] as String? ?? _sessionId;

      if (mounted) {
        setState(() {
          _messages.add(_ChatMessage(text: answer, isUser: false));
          _isSending = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.add(_ChatMessage(
            text: 'Sorry, something went wrong. Please try again.',
            isUser: false,
          ));
          _isSending = false;
        });
        _scrollToBottom();
      }
    }
  }

  Future<void> _signOut() async {
    await widget.authService.signOut();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const RootPage()),
        (route) => false,
      );
    }
  }

  // --- Account helpers ---

  int get _bankAccountCount =>
      _accounts.where((a) => a.type == 'bank_account').length;

  int get _creditCardCount =>
      _accounts.where((a) => a.type == 'credit_card').length;

  int get _upiWalletCount =>
      _accounts.where((a) => a.type == 'upi' || a.type == 'wallet').length;

  IconData _iconForType(String type) {
    switch (type) {
      case 'credit_card':
        return Icons.credit_card;
      case 'bank_account':
        return Icons.account_balance;
      case 'upi':
        return Icons.phone_android;
      case 'wallet':
        return Icons.account_balance_wallet;
      default:
        return Icons.payment;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MoneyTest'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Refresh data',
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'signout') _signOut();
              if (value == 'rescan') {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => ScanProgressPage(
                      authService: widget.authService,
                      financeService: widget.financeService,
                    ),
                  ),
                );
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'rescan',
                child: Row(
                  children: [
                    Icon(Icons.email_outlined, size: 20, color: Colors.black54),
                    SizedBox(width: 8),
                    Text('Re-scan Emails'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'signout',
                child: Row(
                  children: [
                    Icon(Icons.logout, size: 20, color: Colors.black54),
                    SizedBox(width: 8),
                    Text('Sign Out'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Top section: account summary + quick stats (scrollable header)
          if (_isLoadingData)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            _buildSummarySection(),

          const Divider(height: 1),

          // Bottom section: AI Chat
          Expanded(
            child: _messages.isEmpty
                ? _buildChatEmptyState()
                : _buildMessageList(),
          ),

          // Typing indicator
          if (_isSending)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.grey.shade400,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Thinking...',
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),

          // Input bar
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildSummarySection() {
    final spending = _currentMonth?.totalSpending ?? 0;
    final income = _currentMonth?.totalIncome ?? 0;
    final txnCount = _currentMonth?.transactionCount ?? 0;

    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Account summary chips
          if (_accounts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  if (_bankAccountCount > 0)
                    _buildCountChip(
                      Icons.account_balance,
                      '$_bankAccountCount Bank${_bankAccountCount > 1 ? 's' : ''}',
                    ),
                  if (_creditCardCount > 0)
                    _buildCountChip(
                      Icons.credit_card,
                      '$_creditCardCount Card${_creditCardCount > 1 ? 's' : ''}',
                    ),
                  if (_upiWalletCount > 0)
                    _buildCountChip(
                      Icons.phone_android,
                      '$_upiWalletCount UPI',
                    ),
                ],
              ),
            ),

          // Detected accounts list (compact)
          if (_accounts.isNotEmpty)
            SizedBox(
              height: 72,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                itemCount: _accounts.length,
                itemBuilder: (context, index) {
                  final account = _accounts[index];
                  return Container(
                    width: 160,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: kSurfaceLight,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _iconForType(account.type),
                              size: 16,
                              color: kPrimaryColor,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                account.provider,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${account.maskedNumber}  •  ${account.transactionCount} txns',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

          // Quick stats row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                _buildStatPill('Spent', formatINR(spending), kDebitRed),
                const SizedBox(width: 8),
                _buildStatPill('Income', formatINR(income), kCreditGreen),
                const SizedBox(width: 8),
                _buildStatPill('Txns', '$txnCount', kPrimaryColor),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCountChip(IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Chip(
        avatar: Icon(icon, size: 16, color: kPrimaryColor),
        label: Text(label, style: const TextStyle(fontSize: 12)),
        backgroundColor: kPrimaryColor.withAlpha(20),
        padding: EdgeInsets.zero,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _buildStatPill(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withAlpha(15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: color,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatEmptyState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.smart_toy_outlined, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              'Ask me anything about your finances',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: _suggestedQuestions.map((q) {
                return ActionChip(
                  label: Text(q, style: const TextStyle(fontSize: 13)),
                  onPressed: () => _sendMessage(q),
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(color: kPrimaryColor.withAlpha(60)),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: _messages.length,
      itemBuilder: (context, index) => _buildBubble(_messages[index]),
    );
  }

  Widget _buildBubble(_ChatMessage msg) {
    final isUser = msg.isUser;
    final alignment = isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final bgColor = isUser ? kPrimaryColor : Colors.grey.shade200;
    final textColor = isUser ? Colors.white : Colors.black87;
    final borderRadius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: Radius.circular(isUser ? 16 : 4),
      bottomRight: Radius.circular(isUser ? 4 : 16),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: alignment,
        children: [
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: borderRadius,
            ),
            child: Text(
              msg.text,
              style: TextStyle(
                fontSize: 15,
                color: textColor,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            DateFormat('h:mm a').format(msg.timestamp),
            style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 8,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(13),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Ask about your finances...',
                hintStyle: TextStyle(color: Colors.grey.shade400),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: kSurfaceLight,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
              ),
              onSubmitted: _isSending ? null : _sendMessage,
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            onPressed:
                _isSending ? null : () => _sendMessage(_textController.text),
            icon: const Icon(Icons.send_rounded),
            color: kPrimaryColor,
            iconSize: 26,
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Chat message model
// ===========================================================================
class _ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  _ChatMessage({
    required this.text,
    required this.isUser,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}
