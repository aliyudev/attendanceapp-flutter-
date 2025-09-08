import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  SupabaseService._();
  static final SupabaseService instance = SupabaseService._();

  final SupabaseClient client = Supabase.instance.client;

  // Admin domain check
  bool isAdminEmail(String email) {
    return email.toLowerCase().endsWith('@itskysolutions.com');
  }

  Session? get currentSession => client.auth.currentSession;
  User? get currentUser => client.auth.currentUser;

  Future<AuthResponse> signIn({required String email, required String password}) {
    return client.auth.signInWithPassword(email: email, password: password);
  }

  Future<AuthResponse> signUp({required String email, required String password, String? name}) async {
    final res = await client.auth.signUp(email: email, password: password, data: {
      if (name != null) 'name': name,
    });
    return res;
  }

  Future<void> signOut() => client.auth.signOut();

  Future<void> resetPassword({required String email}) => client.auth.resetPasswordForEmail(email);

  // Database operations
  Future<void> ensureUserRow({required String email, String? name, Map<String, dynamic>? extra}) async {
    final uid = currentUser?.id;
    if (uid == null) return;
    final existing = await client
        .from('users')
        .select('id')
        .eq('id', uid)
        .maybeSingle();
    if (existing == null) {
      await client.from('users').insert({
        'id': uid,
        'email': email,
        if (name != null) 'name': name,
        'admin': isAdminEmail(email),
        if (extra != null) ...extra,
      });
    }
  }

  Future<void> recordAttendance({
    required DateTime clockInTimeUtc,
    double? lat,
    double? lng,
    double? accuracy,
  }) async {
    final uid = currentUser?.id;
    if (uid == null) throw 'Not authenticated';
    await client.from('attendance').insert({
      'user_id': uid,
      'clock_in_time': clockInTimeUtc.toIso8601String(),
      'location_lat': lat,
      'location_lng': lng,
      'accuracy': accuracy,
    });
  }

  Stream<List<Map<String, dynamic>>> attendanceStreamForUser(String userId) {
    // Realtime on the attendance table for a specific user
    final stream = client
        .from('attendance:user_id=eq.$userId')
        .stream(primaryKey: ['id'])
        .order('clock_in_time');
    return stream;
  }

  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    return await client
        .from('users')
        .select('id, email, name, admin')
        .or('email.ilike.%$q%,name.ilike.%$q%')
        .limit(50);
  }

  Future<void> deleteUser(String userId) async {
    await client.from('users').delete().eq('id', userId);
  }
}
