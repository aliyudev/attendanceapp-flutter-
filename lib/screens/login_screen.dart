import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifier = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _identifier.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      // Allow either email or username. Resolve to email if username provided.
      final identifier = _identifier.text.trim();
      final email = await SupabaseService.instance.resolveEmailForLogin(identifier);
      final pwd = _password.text;
      await SupabaseService.instance.signIn(email: email, password: pwd);
      await SupabaseService.instance.ensureUserRow(email: email);
      // Determine admin or user route
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      bool isAdmin = false;
      if (user != null) {
        try {
          final rec = await client.from('users').select('admin').eq('id', user.id).maybeSingle();
          isAdmin = (rec != null && rec['admin'] == true);
        } on PostgrestException {
          // If the 'admin' column doesn't exist or is not accessible, default to false.
          isAdmin = false;
        } catch (_) {}
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(isAdmin ? '/admin' : '/dashboard');
    } on AuthApiException catch (e) {
      _show('Login failed: ${e.message}');
    } catch (e) {
      _show('Login failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _show(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  InputDecoration _dec(String hint) => const InputDecoration(
        hintText: '',
        border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Color(0xFFdc2626)),
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Color(0xFFdc2626), width: 2),
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo & subtitle
                Column(
                  children: const [
                    Image(image: AssetImage('itskylogo.png'), width: 120, height: 60),
                    SizedBox(height: 10),
                    Text('Attendance System', style: TextStyle(fontSize: 16, color: Colors.grey)),
                  ],
                ),
                const SizedBox(height: 40),
                // Card form
                Card(
                  elevation: 5,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text('Sign In', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFFdc2626))),
                          const SizedBox(height: 24),
                          TextFormField(
                            controller: _identifier,
                            keyboardType: TextInputType.emailAddress,
                            decoration: _dec('Email or username').copyWith(hintText: 'Enter your email or username'),
                            validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your email or username' : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _password,
                            obscureText: _obscure,
                            decoration: _dec('Enter your password').copyWith(
                              hintText: 'Enter your password',
                              suffixIcon: IconButton(
                                icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, color: const Color(0xFFdc2626)),
                                onPressed: () => setState(() => _obscure = !_obscure),
                              ),
                            ),
                            validator: (v) => (v == null || v.length < 6) ? 'Min 6 characters' : null,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _loading ? null : _login,
                            child: Text(_loading ? 'Signing In...' : 'Sign In'),
                          ),
                          const SizedBox(height: 12),
                          const Text('Location verification will be required when you clock in', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                          const SizedBox(height: 16),
                          TextButton(
                            onPressed: _loading ? null : () => Navigator.of(context).pushReplacementNamed('/signup'),
                            child: const Text("Don't have an account? Sign Up", style: TextStyle(decoration: TextDecoration.underline, color: Color(0xFFdc2626))),
                          ),
                          TextButton(
                            onPressed: _loading
                                ? null
                                : () => Navigator.of(context).pushNamed('/password-recovery'),
                            child: const Text('Forgot password? Reset', style: TextStyle(decoration: TextDecoration.underline, color: Color(0xFFdc2626))),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
