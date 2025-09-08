import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _loginAdmin() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final email = _email.text.trim();
      final pwd = _password.text;
      await SupabaseService.instance.signIn(email: email, password: pwd);
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) throw Exception('No session');
      final rec = await client.from('users').select('admin').eq('id', user.id).maybeSingle();
      final isAdmin = (rec != null && rec['admin'] == true);
      if (!mounted) return;
      if (isAdmin) {
        Navigator.of(context).pushReplacementNamed('/admin');
      } else {
        // Not admin: sign out and show error
        await SupabaseService.instance.signOut();
        _show('This account is not an admin.');
      }
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
                Column(
                  children: const [
                    Image(image: AssetImage('itskylogo.png'), width: 120, height: 60),
                    SizedBox(height: 10),
                    Text('Admin Portal', style: TextStyle(fontSize: 16, color: Colors.grey)),
                  ],
                ),
                const SizedBox(height: 40),
                Card(
                  elevation: 5,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Admin Sign In', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFFdc2626))),
                          const SizedBox(height: 24),
                          TextFormField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            decoration: _dec('Email').copyWith(hintText: 'Enter admin email'),
                            validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _password,
                            obscureText: true,
                            decoration: _dec('Password').copyWith(hintText: 'Enter password'),
                            validator: (v) => (v == null || v.length < 6) ? 'Min 6 characters' : null,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _loading ? null : _loginAdmin,
                            child: Text(_loading ? 'Signing In...' : 'Sign In'),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: _loading ? null : () => Navigator.of(context).pushReplacementNamed('/login'),
                            child: const Text('Back to User Login', style: TextStyle(decoration: TextDecoration.underline, color: Color(0xFFdc2626))),
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
