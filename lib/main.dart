import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

// ---------------------------------------------------------------------------
// App Theme
// ---------------------------------------------------------------------------
const Color kPrimaryColor = Color(0xFF0D47A1);
const Color kPrimaryLight = Color(0xFF1565C0);
const Color kAccentColor = Color(0xFF00897B);
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
// Root — auth flow controller
// ===========================================================================
class RootPage extends StatefulWidget {
  const RootPage({super.key});

  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  final AuthService _authService = AuthService();
  bool _initializing = true;

  @override
  void initState() {
    super.initState();
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

    return HomePage(authService: _authService);
  }
}

// ===========================================================================
// Sign In Page
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
                'Sign in to get started',
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
                  style: const TextStyle(color: Colors.red, fontSize: 14),
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
// Home Page — signed in, Gmail connected
// ===========================================================================
class HomePage extends StatelessWidget {
  final AuthService authService;

  const HomePage({super.key, required this.authService});

  @override
  Widget build(BuildContext context) {
    final user = authService.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('MoneyTest'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await authService.signOut();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const RootPage()),
                  (route) => false,
                );
              }
            },
            tooltip: 'Sign out',
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle, size: 64, color: kAccentColor),
              const SizedBox(height: 24),
              const Text(
                'Gmail Connected',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                user?.email ?? '',
                style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 8),
              Text(
                'Gmail access and push notifications are set up.',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
