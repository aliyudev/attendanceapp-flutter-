import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/location.dart';
import '../services/supabase_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _busy = false;
  String _clockInMessage = '';
  String _locationStatus = '';
  Color _statusColor = const Color(0xFFFFA500); // orange
  bool _alreadyClockedIn = false;
  bool _hasFaceRegistered = false;
  String _username = 'User';

  // Calendar data
  late DateTime _now;
  late int _year;
  late int _month;
  List<DateTime> _presentDates = [];
  int _workingDaysThisMonth = 0;
  final Map<int, DateTime> _presentMap = {}; // day -> full datetime
  int? _selectedDay; // selected day in month
  DateTime? _selectedFull; // full DateTime of clock-in if present

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _year = _now.year;
    _month = _now.month;
    _loadCalendar();
    _loadFaceFlag();
    _loadUsername();
  }

  Future<void> _loadFaceFlag() async {
    final prefs = await SharedPreferences.getInstance();
    // Read cached flag first for fast UI
    bool cached = prefs.getBool('has_face_registered') ?? false;
    _hasFaceRegistered = cached;
    if (mounted) setState(() {});
    // Verify with backend (source of truth)
    try {
      final emb = await SupabaseService.instance.fetchFaceEmbedding();
      final has = (emb != null && emb.isNotEmpty);
      _hasFaceRegistered = has;
      if (mounted) setState(() {});
      await prefs.setBool('has_face_registered', has);
    } catch (_) {
      // keep cached value on failure
    }
  }

  Future<void> _loadUsername() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('cached_username');
      if (cached != null && cached.trim().isNotEmpty) {
        if (mounted) setState(() => _username = cached.trim());
      }

      final email = SupabaseService.instance.currentUser?.email;
      if (email == null || email.isEmpty) return;
      final data = await Supabase.instance.client
          .from('users')
          .select('name')
          .eq('email', email)
          .maybeSingle();
      final fetched = (data != null && data['name'] != null && (data['name'] as String).trim().isNotEmpty)
          ? (data['name'] as String).trim()
          : email; // fallback to email if no name
      if (mounted) setState(() => _username = fetched);
      await prefs.setString('cached_username', fetched);
    } catch (_) {
      // ignore and keep existing username
    }
  }

  Future<void> _loadCalendar() async {
    try {
      final userId = SupabaseService.instance.currentUser?.id;
      if (userId == null) return;
      final monthStart = DateTime(_year, _month, 1).toUtc().toIso8601String();
      final monthEnd = DateTime(_year, _month + 1, 0, 23, 59, 59).toUtc().toIso8601String();
      final rows = await Supabase.instance.client
          .from('attendance')
          .select('clock_in_time')
          .eq('user_id', userId)
          .gte('clock_in_time', monthStart)
          .lte('clock_in_time', monthEnd);
      final dates = <DateTime>[];
      _presentMap.clear();
      for (final r in rows as List) {
        final ts = DateTime.parse(r['clock_in_time'] as String).toLocal();
        dates.add(ts);
        _presentMap[ts.day] = ts;
      }
      _presentDates = dates;
      _alreadyClockedIn = _presentDates.any((d) => d.year == _now.year && d.month == _now.month && d.day == _now.day);
      // Compute Mon-Thu working days
      final daysInMonth = DateTime(_year, _month + 1, 0).day;
      int working = 0;
      for (int day = 1; day <= daysInMonth; day++) {
        final dow = DateTime(_year, _month, day).weekday; // Mon=1
        if (dow >= 1 && dow <= 4) working++;
      }
      _workingDaysThisMonth = working;
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  Future<void> _clockInFlow() async {
    if (_alreadyClockedIn) {
      _show('Already clocked in today.');
      return;
    }
    setState(() {
      _busy = true;
      _clockInMessage = '';
      _locationStatus = '';
      _statusColor = const Color(0xFFFFA500);
    });
    try {
      // Request permission
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        _show('Location permission required');
        return;
      }
      _locationStatus = 'Requesting GPS location...';
      setState(() {});
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);

      // Proximity check
      bool within = true;
      double? distance;
      if (OfficeConfig.lat != null && OfficeConfig.lng != null) {
        distance = _haversine(pos.latitude, pos.longitude, OfficeConfig.lat!, OfficeConfig.lng!);
        _locationStatus = 'Distance to office: ${distance.round()} m';
        within = distance <= OfficeConfig.radiusMeters;
        if (!within) {
          _statusColor = const Color(0xFFdc2626);
          setState(() {});
          _show('Too far from office. Move within ${OfficeConfig.radiusMeters.round()} m to clock in.');
          return;
        }
      } else {
        _locationStatus = 'GPS acquired';
      }

      // Record attendance
      await SupabaseService.instance.recordAttendance(
        clockInTimeUtc: DateTime.now().toUtc(),
        lat: pos.latitude,
        lng: pos.longitude,
        accuracy: pos.accuracy,
      );
      _clockInMessage = '✅ Clock-in successful!';
      _statusColor = const Color(0xFF4CAF50);
      _alreadyClockedIn = true;
      await _loadCalendar();
    } catch (e) {
      _clockInMessage = '❌ Clock-in failed.';
      _statusColor = const Color(0xFFdc2626);
      _show('Clock-in failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0;
    final dLat = _degToRad(lat2 - lat1);
    final dLon = _degToRad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) + math.cos(_degToRad(lat1)) * math.cos(_degToRad(lat2)) * math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  double _degToRad(double deg) => deg * math.pi / 180.0;

  @override
  Widget build(BuildContext context) {
    final user = SupabaseService.instance.currentUser;
    final email = user?.email ?? '';

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header with logo, welcome, actions
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Color(0xFFeeeeee))))
              ,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Image.asset('itskylogo.png', width: 60, height: 30, fit: BoxFit.contain),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Welcome, ${_username.isEmpty ? 'User' : _username}!', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFF111111))),
                  ),
                  // Enroll/Update Face button
                  Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4CAF50), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                      onPressed: () async {
                        // Route based on flag
                        if (_hasFaceRegistered) {
                          final ok = await Navigator.of(context).pushNamed('/face-verify') as bool?;
                          if (ok == true) {
                            _show('Face verified');
                          }
                        } else {
                          final registered = await Navigator.of(context).pushNamed('/face-enroll') as bool?;
                          if (registered == true) {
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setBool('has_face_registered', true);
                            setState(() => _hasFaceRegistered = true);
                            _show('Face registered');
                          }
                        }
                      },
                      child: Text(_hasFaceRegistered ? '👤' : '➕👤'),
                    ),
                  ),
                  // Admin button removed from user dashboard per spec
                  TextButton(
                    onPressed: () async {
                      await SupabaseService.instance.signOut();
                      if (context.mounted) Navigator.of(context).pushReplacementNamed('/login');
                    },
                    child: const Text('Logout', style: TextStyle(color: Color(0xFFdc2626), fontWeight: FontWeight.w600)),
                  )
                ],
              ),
            ),

            // Content scroll
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // Stats section with calendar
                    Container(
                      margin: const EdgeInsets.all(20),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: const Color(0xFFF8F8F8), borderRadius: BorderRadius.circular(8)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Attendance Calendar (This Month)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF111111))),
                          const SizedBox(height: 12),
                          _buildCalendar(),
                          if (_selectedDay != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Text(
                                    '${_year.toString().padLeft(4, '0')}-${_month.toString().padLeft(2, '0')}-${_selectedDay!.toString().padLeft(2, '0')}',
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 4),
                                  if (_selectedFull != null)
                                    Text('Clocked in at: ${_selectedFull!.toLocal().toIso8601String().substring(11, 19)}', style: const TextStyle(fontSize: 15, color: Color(0xFF4CAF50)))
                                  else
                                    const Text('Not clocked in', style: TextStyle(fontSize: 15, color: Color(0xFFdc2626))),
                                ],
                              ),
                            ),
                          const SizedBox(height: 8),
                          Text('Days Present: ${_presentCount()} / $_workingDaysThisMonth', style: const TextStyle(fontSize: 16, color: Color(0xFF111111))),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Bottom section with clock-in button and status
            Container(
              decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Color(0xFFeeeeee))))
              ,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _busy || _alreadyClockedIn ? null : () async {
                        // If no face enrolled, enroll first
                        if (!_hasFaceRegistered) {
                          final registered = await Navigator.of(context).pushNamed('/face-enroll') as bool?;
                          if (registered == true) {
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setBool('has_face_registered', true);
                            setState(() => _hasFaceRegistered = true);
                          } else {
                            _show('Face enrollment required to clock in.');
                            return;
                          }
                        }
                        // Then verify before GPS
                        final ok = await Navigator.of(context).pushNamed('/face-verify') as bool?;
                        if (ok == true) {
                          await _clockInFlow();
                        } else {
                          _show('Face verification required to clock in.');
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _alreadyClockedIn ? const Color(0xFF4CAF50) : const Color(0xFFdc2626),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(_busy ? 'Processing...' : (_alreadyClockedIn ? 'Already Clocked In' : 'Clock In'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  if (_clockInMessage.isNotEmpty)
                    const SizedBox(height: 8),
                  if (_clockInMessage.isNotEmpty)
                    Text(_clockInMessage, style: const TextStyle(color: Color(0xFF198754), fontWeight: FontWeight.w600, fontSize: 14), textAlign: TextAlign.center),
                  if (_locationStatus.isNotEmpty)
                    const SizedBox(height: 8),
                  if (_locationStatus.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: const Color(0xFFF8F9FA), borderRadius: BorderRadius.circular(8)),
                      child: Row(
                        children: [
                          Container(width: 20, height: 20, decoration: BoxDecoration(color: _statusColor, borderRadius: BorderRadius.circular(10))),
                          const SizedBox(width: 10),
                          Expanded(child: Text(_locationStatus, style: const TextStyle(fontSize: 14, color: Color(0xFF666666)))),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _presentCount() => _presentDates.length;

  Widget _buildCalendar() {
    final daysInMonth = DateTime(_year, _month + 1, 0).day;
    final firstDay = DateTime(_year, _month, 1).weekday % 7; // Sunday=0
    final weekDays = const ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

    List<Widget> rows = [];
    // header
    rows.add(Row(
      children: weekDays
          .map((d) => Expanded(
                child: Container(
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: const Color(0xFFF3F3F3), border: Border.all(color: const Color(0xFFEEEEEE))),
                  child: Text(d, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF111111))),
                ),
              ))
          .toList(),
    ));

    List<Widget> currentRow = [];
    // leading empties
    for (int i = 0; i < firstDay; i++) {
      currentRow.add(Expanded(child: Container(height: 36, decoration: BoxDecoration(border: Border.all(color: const Color(0xFFEEEEEE))),)));
    }

    for (int day = 1; day <= daysInMonth; day++) {
      final index = (firstDay + day - 1) % 7;
      final date = DateTime(_year, _month, day);
      final dow = date.weekday; // Mon=1..Sun=7
      final isWorkingDay = dow >= 1 && dow <= 4;
      final isFriday = dow == 5;
      final present = _presentDates.any((d) => d.year == _year && d.month == _month && d.day == day);
      final isSelected = _selectedDay == day;

      Color bg = Colors.white;
      Color border = const Color(0xFFEEEEEE);
      double borderWidth = 1;
      List<BoxShadow> shadows = const [];
      TextStyle text = const TextStyle(fontSize: 14, color: Color(0xFF111111));
      if (present) {
        bg = const Color(0xFFdc2626);
        text = const TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.w700);
        if (isSelected) {
          border = const Color(0xFFb91c1c); // darker red outline
          borderWidth = 2;
          shadows = const [BoxShadow(color: Color(0x33dc2626), blurRadius: 6, offset: Offset(0, 2))];
        }
      } else if (isWorkingDay) {
        bg = const Color(0xFFFEF2F2);
        border = const Color(0xFFdc2626);
        if (isSelected) {
          // Slightly darker red tint and emphasis border
          bg = const Color(0xFFFCE8E8);
          border = const Color(0xFFb91c1c);
          borderWidth = 2;
          shadows = const [BoxShadow(color: Color(0x33dc2626), blurRadius: 6, offset: Offset(0, 2))];
        }
      } else if (isFriday) {
        bg = const Color(0xFFF5F5F5);
        text = const TextStyle(fontSize: 14, color: Color(0xFFAAAAAA));
        if (isSelected) {
          border = const Color(0xFFb91c1c);
          borderWidth = 2;
          shadows = const [BoxShadow(color: Color(0x33dc2626), blurRadius: 6, offset: Offset(0, 2))];
        }
      } else {
        bg = const Color(0xFFF0F0F0);
        text = const TextStyle(fontSize: 14, color: Color(0xFF888888), fontStyle: FontStyle.italic);
        if (isSelected) {
          border = const Color(0xFFb91c1c);
          borderWidth = 2;
          shadows = const [BoxShadow(color: Color(0x33dc2626), blurRadius: 6, offset: Offset(0, 2))];
        }
      }

      currentRow.add(Expanded(
        child: GestureDetector(
          onTap: () {
            if (!(dow >= 1 && dow <= 4)) return; // only interactive for working days
            setState(() {
              _selectedDay = day;
              _selectedFull = _presentMap[day];
            });
          },
          child: Container(
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: bg, border: Border.all(color: border, width: borderWidth), boxShadow: shadows),
            child: Text('$day', style: text),
          ),
        ),
      ));

      if (index == 6 || day == daysInMonth) {
        // complete row
        rows.add(Row(children: currentRow));
        currentRow = [];
      }
    }

    // month title
    final monthNames = const ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    return Column(
      children: [
        Text('${monthNames[_month - 1]} $_year', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF666666))),
        const SizedBox(height: 12),
        ...rows,
      ],
    );
  }

  void _show(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }
}
