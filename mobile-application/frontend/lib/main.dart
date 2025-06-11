import 'package:flutter/material.dart';
import 'package:frontend/services/noti_serve.dart';
import 'package:frontend/services/medication_log_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dashboard_screen.dart';
import 'signup.dart';
import 'package:frontend/constants.dart';
import 'theme_constants.dart';
import 'package:flutter/services.dart';
import 'expiry-date-check.dart';
import 'medicine-name-reader.dart';
import 'services/auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize services in the same context to ensure synchronization
  print('📱 Initializing services in main context...');
  
  // Initialize MedicationLogService first to establish SharedPreferences context
  await MedicationLogService.initialize();
  
  // Initialize NotificationService in same context
  final notiService = NotiService();
  await notiService.initNotification();
  
  // Force a context marker to verify notification/UI synchronization
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('main_context_init', DateTime.now().toIso8601String());
    print('✅ Main context marker set');
    
    // Verify we can see all expected keys
    final allKeys = prefs.getKeys();
    print('📱 MAIN CONTEXT KEYS: $allKeys');
  } catch (e) {
    print('❌ Error setting main context marker: $e');
  }
  
  print('✅ All services initialized in main context');

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    // DeviceOrientation.portraitDown,
  ]).then((_) {
    runApp(const MyApp());
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Medicine Adherence Assistant',
      theme: ThemeData(
        primaryColor: ThemeConstants.primaryColor,
        colorScheme:
            ColorScheme.fromSeed(seedColor: ThemeConstants.primaryColor),
        useMaterial3: true,
      ),
      routes: {
        '/signup': (context) => const SignUpScreen(),
        '/main': (context) => const MyHomePage(),
        '/expiry-check': (context) => const ExpiryDateCheck(),
        '/medicine-name': (context) => const MedicineNameCheck(),
        // add other routes here
      },
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, this.title = 'Medicine Adherence Assistant'});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isPasswordVisible = false;
  bool _isCheckingStoredCredentials = true;

  @override
  void initState() {
    super.initState();
    _checkStoredCredentials();
  }
  Future<void> _checkStoredCredentials() async {
    final credentials = await AuthService.getStoredCredentials();
    
    if (credentials != null) {
      // Auto-login with stored credentials
      await _performLogin(credentials['username']!, credentials['password']!, isAutoLogin: true);
    } else {
      setState(() {
        _isCheckingStoredCredentials = false;
      });
    }
  }
  Future<void> _saveCredentials(String username, String password) async {
    await AuthService.saveCredentials(username, password);
  }
  @override
  Widget build(BuildContext context) {
    // Show loading screen while checking stored credentials
    if (_isCheckingStoredCredentials) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(
                color: ThemeConstants.primaryColor,
              ),
              const SizedBox(height: 16),
              Text(
                'Checking login status...',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 100),

                // Image placeholder
                Container(
                  height: 180,
                  margin: const EdgeInsets.only(bottom: 24),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.asset(
                      'assets/logo.png',
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: Colors.grey[100],
                        child: Icon(
                          Icons.medication,
                          size: 80,
                          color: ThemeConstants.primaryColor.withOpacity(0.3),
                        ),
                      ),
                    ),
                  ),
                ),

                // Welcome Text
                Column(
                  children: [
                    RichText(
                      text: TextSpan(
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[800],
                        ),
                        children: const [
                          TextSpan(text: 'Welcome to '),
                          TextSpan(
                            text: 'Cure',
                            style: TextStyle(
                              color: ThemeConstants.primaryColor,
                            ),
                          ),
                          TextSpan(
                            text: 'Cue',
                            style: TextStyle(
                              color: ThemeConstants.secondaryColor, 
                            ),
                          ),
                        ],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Please sign in to continue',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // Username field - Updated with dark grey border
                TextFormField(
                  controller: _usernameController,
                  decoration: InputDecoration(
                    labelText: 'Username',
                    labelStyle: TextStyle(color: Colors.grey[600]),
                    prefixIcon: Icon(Icons.person, color: Colors.grey[500]),
                    filled: true,
                    fillColor: Colors.grey[50],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Colors.grey[400]!, // Dark grey border
                        width: 1.5,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Colors.grey[400]!, // Dark grey border
                        width: 1.5,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: ThemeConstants
                            .primaryColor, // Primary color when focused
                        width: 1.5,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        vertical: 16, horizontal: 20),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your username';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Password field - Updated with dark grey border
                TextFormField(
                  controller: _passwordController,
                  obscureText: !_isPasswordVisible,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    labelStyle: TextStyle(color: Colors.grey[600]),
                    prefixIcon: Icon(Icons.lock, color: Colors.grey[500]),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _isPasswordVisible
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: Colors.grey[500],
                      ),
                      onPressed: () {
                        setState(
                            () => _isPasswordVisible = !_isPasswordVisible);
                      },
                    ),
                    filled: true,
                    fillColor: Colors.grey[50],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Colors.grey[400]!, // Dark grey border
                        width: 1.5,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Colors.grey[400]!, // Dark grey border
                        width: 1.5,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: ThemeConstants
                            .primaryColor, // Primary color when focused
                        width: 1.5,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        vertical: 16, horizontal: 20),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your password';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {},
                    child: const Text(
                      'Forgot Password?',
                      style: TextStyle(
                        color: ThemeConstants.primaryColor,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Sign In button
                ElevatedButton(
                  onPressed: _handleSignIn,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ThemeConstants.primaryColor,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Sign In',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Divider with "or"
                Row(
                  children: [
                    Expanded(child: Divider(color: Colors.grey[300])),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'OR',
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    ),
                    Expanded(child: Divider(color: Colors.grey[300])),
                  ],
                ),
                const SizedBox(height: 16),

                // Sign Up text
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Don't have an account?",
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pushNamed(context, '/signup'),
                      child: const Text(
                        'Sign Up',
                        style: TextStyle(
                          color: ThemeConstants.primaryColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  void _handleSignIn() async {
    if (_formKey.currentState!.validate()) {
      await _performLogin(_usernameController.text, _passwordController.text);
    }
  }

  Future<void> _performLogin(String username, String password, {bool isAutoLogin = false}) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'password': password,
        }),
      );

      if (response.statusCode == 200) {
        final userData = jsonDecode(response.body);
        
        // Save credentials for future auto-login
        await _saveCredentials(username, password);
        
        // Navigate to dashboard
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => DashboardScreen(
              username: userData["username"] ?? username,
              password: userData["password"] ?? password,
            ),
          ),
        );
      } else {        if (isAutoLogin) {
          // If auto-login fails, clear stored credentials and show login screen
          await AuthService.clearStoredCredentials();
          if (mounted) {
            setState(() {
              _isCheckingStoredCredentials = false;
            });
          }
        } else {
          // Show error for manual login
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Invalid username or password')),
            );
          }
        }
      }
    } catch (e) {      if (isAutoLogin) {
        // If auto-login fails due to connection error, clear credentials and show login screen
        await AuthService.clearStoredCredentials();
        if (mounted) {
          setState(() {
            _isCheckingStoredCredentials = false;
          });
        }
      } else {
        // Show error for manual login
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Connection error')),
          );
        }
      }
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
