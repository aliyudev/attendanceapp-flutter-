import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;
  bool _obscurePwd = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _signup() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final email = _email.text.trim();
      final pwd = _password.text;
      final name = _name.text.trim();
      final username = _username.text.trim();

      final res = await SupabaseService.instance.signUp(email: email, password: pwd, name: name);
      if (res.user != null) {
        await SupabaseService.instance.ensureUserRow(email: email, name: name, extra: {'username': username});
        if (!mounted) return;
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Success'),
            content: const Text('Account created successfully! Please sign in.'),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
          ),
        );
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed('/login');
      }
    } on AuthApiException catch (e) {
      _show('Signup failed: ${e.message}');
    } catch (e) {
      _show('Signup failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _show(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  InputDecoration _dec(String label, {String? hint}) => InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
        enabledBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Color(0xFFdc2626)),
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Color(0xFFdc2626), width: 2),
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo section
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
                        const Text('Create Account', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFFdc2626))),
                        const SizedBox(height: 24),
                        TextFormField(
                          controller: _name,
                          decoration: _dec('Full name', hint: 'Enter your full name'),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your full name' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _username,
                          decoration: _dec('Username', hint: 'Enter a username'),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a username' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _email,
                          decoration: _dec('Email', hint: 'Enter your email (@itskysolutions.com)'),
                          keyboardType: TextInputType.emailAddress,
                          validator: (v) {
                            if (v == null || !v.contains('@')) return 'Enter a valid email';
                            if (!v.toLowerCase().endsWith('@itskysolutions.com')) return 'Email must be @itskysolutions.com';
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _password,
                          obscureText: _obscurePwd,
                          decoration: _dec('Password', hint: 'At least 8 chars, 1 uppercase, 1 symbol').copyWith(
                            suffixIcon: IconButton(
                              icon: Icon(_obscurePwd ? Icons.visibility_off : Icons.visibility, color: const Color(0xFFdc2626)),
                              onPressed: () => setState(() => _obscurePwd = !_obscurePwd),
                            ),
                          ),
                          validator: (v) {
                            if (v == null || v.length < 8) return 'Password must be at least 8 characters';
                            if (!RegExp(r'[A-Z]').hasMatch(v)) return 'Include at least one uppercase letter';
                            if (!RegExp(r'[!@#\$%\^&\*(),.?":{}|<>]').hasMatch(v)) return 'Include at least one special symbol';
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _confirm,
                          obscureText: _obscureConfirm,
                          decoration: _dec('Confirm password').copyWith(
                            suffixIcon: IconButton(
                              icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility, color: const Color(0xFFdc2626)),
                              onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                            ),
                          ),
                          validator: (v) => (v != _password.text) ? 'Passwords do not match' : null,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loading ? null : _signup,
                          child: Text(_loading ? 'Creating Account...' : 'Create Account'),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: _loading ? null : () => Navigator.of(context).pushReplacementNamed('/login'),
                          child: const Text("Already have an account? Sign In", style: TextStyle(decoration: TextDecoration.underline, color: Color(0xFFdc2626))),
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
    );
  }
}
