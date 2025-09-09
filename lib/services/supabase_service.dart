import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:postgrest/postgrest.dart';

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

  /// Resolve a login identifier to an email address.
  /// If the input contains '@', it is treated as an email and returned as-is.
  /// Otherwise, the input is treated as a username and we look up the
  /// corresponding user's email in the `users` table.
  Future<String> resolveEmailForLogin(String identifier) async {
    final value = identifier.trim();
    if (value.isEmpty) {
      throw Exception('Please enter your email or username');
    }
    if (value.contains('@')) {
      return value;
    }
    try {
      final rec = await client
          .from('users')
          .select('email')
          .eq('username', value)
          .maybeSingle();
      final email = rec != null ? rec['email'] as String? : null;
      if (email == null || email.isEmpty) {
        throw Exception('No user found for username "$value"');
      }
      return email;
    } on PostgrestException catch (e) {
      // Column missing or not accessible (e.g., PGRST204). Fallback to requiring email.
      throw Exception('Username login is not available. Please use your email address. (${e.code ?? 'error'})');
    }
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
      final full = <String, dynamic>{
        'id': uid,
        'email': email,
        if (name != null) 'name': name,
        'admin': isAdminEmail(email),
        if (extra != null) ...extra,
      };
      try {
        await client.from('users').insert(full);
      } on PostgrestException {
        // Retry with minimal columns, but ensure NOT NULL constraints like 'name' are satisfied.
        final minimal = <String, dynamic>{
          'id': uid,
          'email': email,
          // Many schemas require 'name' NOT NULL; provide a fallback if not supplied.
          'name': name ?? 'Unknown',
        };
        await client.from('users').insert(minimal);
      }
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

  // Face embedding persistence (stored per user row)
  Future<void> saveFaceEmbedding(List<double> embedding) async {
    final uid = currentUser?.id;
    if (uid == null) throw Exception('Not authenticated');
    try {
      await client.from('users').update({'face_embedding': embedding}).eq('id', uid);
    } on PostgrestException catch (e) {
      // Column missing or RLS issue
      throw Exception('Failed to save face embedding (${e.code ?? 'error'}). Ensure the users.face_embedding column exists and policies allow update.');
    }
  }

  Future<List<double>?> fetchFaceEmbedding() async {
    final uid = currentUser?.id;
    if (uid == null) return null;
    try {
      final rec = await client.from('users').select('face_embedding').eq('id', uid).maybeSingle();
      if (rec == null) return null;
      final val = rec['face_embedding'];
      if (val == null) return null;
      final list = (val as List).map((e) => (e as num).toDouble()).toList();
      return list;
    } on PostgrestException catch (_) {
      return null;
    }
  }
}
