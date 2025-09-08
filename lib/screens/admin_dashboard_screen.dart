import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/supabase_service.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _exportCsv({String? onlyEmail}) async {
    setState(() => _loading = true);
    try {
      final client = SupabaseService.instance.client;
      // Fetch users
      List<dynamic> users = await client.from('users').select('id, name, email');
      if (onlyEmail != null && onlyEmail.isNotEmpty) {
        users = users.where((u) => (u['email'] as String?) == onlyEmail).toList();
      }
      // Current month range
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, 1).toUtc();
      final end = DateTime(now.year, now.month + 1, 0, 23, 59, 59).toUtc();
      final attendance = await client
          .from('attendance')
          .select('user_id, clock_in_time')
          .gte('clock_in_time', start.toIso8601String())
          .lte('clock_in_time', end.toIso8601String());

      // Build CSV rows
      final fmtDate = DateFormat('yyyy-MM-dd');
      final fmtTime = DateFormat('HH:mm:ss');
      final rows = <List<String>>[
        ['Name', 'Email', 'Attendance Date', 'Attendance Time'],
      ];
      for (final u in users) {
        final uid = u['id'] as String?;
        final name = (u['name'] ?? '').toString();
        final email = (u['email'] ?? '').toString();
        final records = (attendance as List).where((a) => a['user_id'] == uid).map((a) => DateTime.parse(a['clock_in_time'] as String).toLocal()).toList();
        if (records.isEmpty) {
          rows.add([name, email, '', '']);
        } else {
          for (final dt in records) {
            rows.add([name, email, fmtDate.format(dt), fmtTime.format(dt)]);
          }
        }
      }

      // Write to temp file
      final tmpDir = await getTemporaryDirectory();
      final file = File('${tmpDir.path}/attendance_report_${DateTime.now().millisecondsSinceEpoch}.csv');
      final csv = rows.map((r) => r.map((f) => '"${f.replaceAll('"', '""')}"').join(',')).join('\n');
      await file.writeAsString(csv);
      await Share.shareXFiles([XFile(file.path)], text: 'Attendance report');
    } catch (e) {
      _show('Export failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _search() async {
    setState(() => _loading = true);
    try {
      _results = await SupabaseService.instance.searchUsers(_searchController.text);
    } catch (e) {
      _show('Search error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin Dashboard')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(labelText: 'Search by name or email'),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: _loading ? null : _search, child: const Text('Search')),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _loading ? null : () => _exportCsv(),
                  child: const Text('Export CSV'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: _results.length,
                      itemBuilder: (context, i) {
                        final u = _results[i];
                        return Card(
                          child: ListTile(
                            title: Text(u['name']?.toString() ?? ''),
                            subtitle: Text(u['email']?.toString() ?? ''),
                            trailing: IconButton(
                              onPressed: () async {
                                final ok = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text('Delete user?'),
                                        content: Text('Are you sure you want to delete ${u['email']}?'),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
                                        ],
                                      ),
                                    ) ??
                                    false;
                                if (!ok) return;
                                try {
                                  await SupabaseService.instance.deleteUser(u['id'] as String);
                                  _show('Deleted');
                                  _search();
                                } catch (e) {
                                  _show('Delete failed: $e');
                                }
                              },
                              icon: const Icon(Icons.delete, color: Colors.redAccent),
                            ),
                          ),
                        );
                      },
                    ),
            )
            ,
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _loading ? null : () => Navigator.of(context).pushNamed('/manage-users'),
                    child: const Text('Manage Users'),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  void _show(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }
}
