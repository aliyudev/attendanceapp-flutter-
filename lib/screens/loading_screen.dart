import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> {
  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await Future.delayed(const Duration(milliseconds: 300));
    final client = Supabase.instance.client;
    final session = client.auth.currentSession;
    if (!mounted) return;
    if (session != null) {
      try {
        final user = session.user;
        final rec = await client.from('users').select('admin').eq('id', user.id).maybeSingle();
        final isAdmin = (rec != null && rec['admin'] == true);
        Navigator.of(context).pushReplacementNamed(isAdmin ? '/admin' : '/dashboard');
      } catch (_) {
        Navigator.of(context).pushReplacementNamed('/dashboard');
      }
    } else {
      Navigator.of(context).pushReplacementNamed('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        color: Colors.white,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Image.asset('itskylogo.png', width: 150, height: 75, fit: BoxFit.contain),
            const SizedBox(height: 20),
            const Text('Attendance System', style: TextStyle(fontSize: 16, color: Colors.grey)),
            const SizedBox(height: 40),
            const CircularProgressIndicator(color: Color(0xFFdc2626)),
            const SizedBox(height: 20),
            const Text('Loading...', style: TextStyle(fontSize: 16, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
