import 'package:flutter/material.dart';

import '../services/supabase_service.dart';

class PasswordRecoveryScreen extends StatefulWidget {
  const PasswordRecoveryScreen({super.key});

  @override
  State<PasswordRecoveryScreen> createState() => _PasswordRecoveryScreenState();
}

class _PasswordRecoveryScreenState extends State<PasswordRecoveryScreen> {
  final _email = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      _show('Please enter your email');
      return;
    }
    if (!email.toLowerCase().endsWith('@itskysolutions.com')) {
      _show('Email must be @itskysolutions.com');
      return;
    }
    setState(() => _loading = true);
    try {
      await SupabaseService.instance.resetPassword(email: email);
      if (!mounted) return;
      _show('Password reset email sent!');
      Navigator.of(context).pushReplacementNamed('/login');
    } catch (e) {
      _show('Failed to send reset email: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _show(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Password Recovery', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFFdc2626))),
              const SizedBox(height: 8),
              const Text('Enter your email to reset your password.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 16),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  hintText: 'Enter your email',
                  border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFFdc2626)),
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFFdc2626), width: 2),
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _send,
                  child: Text(_loading ? 'Sending...' : 'Send Reset Email'),
                ),
              ),
              TextButton(
                onPressed: _loading ? null : () => Navigator.of(context).pushReplacementNamed('/login'),
                child: const Text('Back to Login', style: TextStyle(decoration: TextDecoration.underline, color: Color(0xFFdc2626))),
              )
            ],
          ),
        ),
      ),
    );
  }
}
