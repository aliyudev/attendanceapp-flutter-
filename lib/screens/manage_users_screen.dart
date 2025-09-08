import 'package:flutter/material.dart';

import '../services/supabase_service.dart';

class ManageUsersScreen extends StatefulWidget {
  const ManageUsersScreen({super.key});

  @override
  State<ManageUsersScreen> createState() => _ManageUsersScreenState();
}

class _ManageUsersScreenState extends State<ManageUsersScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _users = [];

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  Future<void> _fetchUsers() async {
    setState(() => _loading = true);
    try {
      final client = SupabaseService.instance.client;
      final data = await client.from('users').select('id, name, email').order('email');
      _users = (data as List).cast<Map<String, dynamic>>();
    } catch (e) {
      _show('Failed to load users: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteUser(Map<String, dynamic> user) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete User'),
            content: Text('Are you sure you want to delete ${user['email']}? This cannot be undone!'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    try {
      await SupabaseService.instance.deleteUser(user['id'] as String);
      _show('User deleted');
      _fetchUsers();
    } catch (e) {
      _show('Delete failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage Users')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchUsers,
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                itemCount: _users.length,
                itemBuilder: (context, i) {
                  final u = _users[i];
                  return ListTile(
                    title: Text(u['name']?.toString() ?? ''),
                    subtitle: Text(u['email']?.toString() ?? ''),
                    trailing: IconButton(
                      onPressed: () => _deleteUser(u),
                      icon: const Icon(Icons.delete, color: Colors.redAccent),
                    ),
                  );
                },
                separatorBuilder: (_, __) => const Divider(height: 1),
              ),
            ),
    );
  }

  void _show(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }
}
