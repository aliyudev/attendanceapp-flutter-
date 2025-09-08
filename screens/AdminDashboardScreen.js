// AdminDashboardScreen.js - Admin Dashboard
// This screen provides admin users with a dashboard to view, search, and manage user attendance records.
// Uses Supabase for all data operations.
//
// Features:
// - View all users and their attendance statistics
// - Search users by name or email
// - Export attendance data (planned)
// - Delete users (via ManageUsersScreen)
// - Uses Supabase client for all data operations
//
// @author ITSky Solutions
// @version 1.3.0

// Import React and hooks for state and lifecycle management
import React, { useState, useEffect } from 'react';
// Import React Native components for UI
import {
  View,
  Text,
  TouchableOpacity,
  StyleSheet,
  Alert,
  ScrollView,
  RefreshControl,
  ActivityIndicator,
  Image,
  TextInput, // <-- Add TextInput import
} from 'react-native';
// Import AsyncStorage for local storage
import AsyncStorage from '@react-native-async-storage/async-storage';
import { supabase } from '../config/api'; // <-- Use Supabase client
import { Picker } from '@react-native-picker/picker'; // <-- Add picker import
import * as FileSystem from 'expo-file-system'; // <-- Add file system import
import * as Sharing from 'expo-sharing';
// Removed: import { getApiUrl } from '../config/api';

// Main AdminDashboardScreen component
export default function AdminDashboardScreen({ navigation }) {
  // State variables for admin email, loading, refreshing, and stats
  const [adminEmail, setAdminEmail] = useState('');
  const [adminName, setAdminName] = useState('Administrator');
  const [isLoading, setIsLoading] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const [stats, setStats] = useState(null);
  const [searchQuery, setSearchQuery] = useState(''); // <-- Add search state
  const [selectedUserEmail, setSelectedUserEmail] = useState('ALL'); // 'ALL' means export all users

  // useEffect to load admin data and stats on mount
  useEffect(() => {
    loadAdminData();
    loadStats();
  }, []);

  // Function to load admin email from storage
  const loadAdminData = async () => {
    try {
      const email = await AsyncStorage.getItem('userEmail');
      setAdminEmail(email);
      console.log('Admin email:', email);
      
      // Try Auth metadata first
      try {
        const { data, error } = await supabase.auth.getUser();
        const metaName = !error ? data?.user?.user_metadata?.name : null;
        console.log('Admin auth metadata name:', metaName);
        if (metaName && typeof metaName === 'string' && metaName.trim()) {
          console.log('Using admin auth metadata name:', metaName.trim());
          setAdminName(metaName.trim());
          return;
        }
      } catch (e) {
        console.log('Error getting auth metadata:', e);
      }

      // Then try users table by email
      if (email) {
        console.log('Trying to get admin username by email:', email);
        const { data: profile, error: profErr } = await supabase
          .from('users')
          .select('name')
          .eq('email', email)
          .single();
        console.log('Admin profile by email result:', { data: profile, error: profErr });
        if (!profErr && profile?.name) {
          console.log('Using admin name from email lookup:', profile.name);
          setAdminName(profile.name);
          return;
        }
        // Fallback: nice name from email local-part
        const local = email.split('@')[0];
        const fallbackName = local.charAt(0).toUpperCase() + local.slice(1);
        console.log('Using admin fallback name:', fallbackName);
        setAdminName(fallbackName);
      }
    } catch (error) {
      console.error('Error loading admin data:', error);
    }
  };

  // Function to load attendance statistics (direct Supabase fetch)
  const loadStats = async () => {
    setIsLoading(true);
    try {
      // Check admin status
      const isAdmin = await AsyncStorage.getItem('isAdmin');
      if (isAdmin !== 'true') {
        Alert.alert('Access Denied', 'You are not an admin.');
        navigation.replace('Login');
        return;
      }

      // Get all users
      const { data: users, error: usersError } = await supabase
        .from('users')
        .select('id, name, email');
      if (usersError) throw usersError;

      // Get all attendance records for this month
      const now = new Date();
      const year = now.getFullYear();
      const month = (now.getMonth() + 1).toString().padStart(2, '0');
      const monthStart = `${year}-${month}-01`;
      const monthEnd = `${year}-${month}-31`;
      const { data: attendance, error: attError } = await supabase
        .from('attendance')
        .select('user_id, clock_in_time')
        .gte('clock_in_time', monthStart)
        .lte('clock_in_time', monthEnd);
      if (attError) throw attError;

      // Calculate working days (Mon-Thu)
      const daysInMonth = new Date(year, parseInt(month), 0).getDate();
      let workingDays = 0;
      for (let day = 1; day <= daysInMonth; day++) {
        const date = new Date(year, parseInt(month) - 1, day);
        const dayOfWeek = date.getDay();
        if (dayOfWeek >= 1 && dayOfWeek <= 4) workingDays++;
      }

      // Aggregate stats per user
      const stats = users.map(user => {
        const userRecords = (attendance || [])
          .filter(r => r.user_id === user.id)
          .map(r => r.clock_in_time);
        return {
          fullname: user.name,
          email: user.email,
          daysPresent: userRecords.length,
          records: userRecords,
        };
      });

      setStats({ stats, daysThisMonth: workingDays });
    } catch (error) {
      console.error('Error loading stats:', error);
      Alert.alert('Error', 'Failed to load attendance statistics');
    } finally {
      setIsLoading(false);
    }
  };

  // Function to handle pull-to-refresh
  const onRefresh = async () => {
    setRefreshing(true);
    await loadStats();
    setRefreshing(false);
  };

  // Function to handle logout logic
  const handleLogout = async () => {
    Alert.alert(
      'Logout',
      'Are you sure you want to logout?',
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Logout',
          style: 'destructive',
          onPress: async () => {
            await AsyncStorage.multiRemove(['userId', 'userToken', 'userEmail', 'isAdmin']);
            navigation.replace('Login');
          },
        },
      ]
    );
  };

  // Function to render user attendance statistics (with search filter)
  const renderUserStats = () => {
    if (!stats || !stats.stats) return null;

    // Filter users by search query (name or email, case-insensitive)
    const filteredUsers = stats.stats.filter(user => {
      const q = searchQuery.trim().toLowerCase();
      if (!q) return true;
      return (
        (user.fullname && user.fullname.toLowerCase().includes(q)) ||
        (user.email && user.email.toLowerCase().includes(q))
      );
    });

    if (filteredUsers.length === 0) {
      return (
        <View style={styles.noResultsContainer}>
          <Text style={styles.noResultsText}>No users found.</Text>
        </View>
      );
    }

    return filteredUsers.map((user, index) => (
      <View key={index} style={styles.userCard}>
        <View style={styles.userHeader}>
          <Text style={styles.userName}>{user.fullname || 'Unknown User'}</Text>
          <Text style={styles.userEmail}>{user.email}</Text>
        </View>
        <View style={styles.userStats}>
          <View style={styles.statItem}>
            <Text style={styles.statLabel}>Days Present</Text>
            <Text style={styles.statValue}>{user.daysPresent}</Text>
          </View>
          <View style={styles.statItem}>
            <Text style={styles.statLabel}>This Month</Text>
            <Text style={styles.statValue}>{stats.daysThisMonth}</Text>
          </View>
          <View style={styles.statItem}>
            <Text style={styles.statLabel}>Attendance Rate</Text>
            <Text style={styles.statValue}>
              {stats.daysThisMonth > 0 
                ? Math.round((user.daysPresent / stats.daysThisMonth) * 100) 
                : 0}%
            </Text>
          </View>
        </View>
        {user.records && user.records.length > 0 && (
          <View style={styles.attendanceDates}>
            <Text style={styles.datesLabel}>Attendance Dates:</Text>
            <Text style={styles.datesText}>
              {user.records.map(record => {
                const date = new Date(record).toLocaleDateString();
                const time = new Date(record).toLocaleTimeString();
                return `${date} ${time}`;
              }).slice(-5).join(', ')}
              {user.records.length > 5 && '...'}
            </Text>
          </View>
        )}
      </View>
    ));
  };

  // Update handleExportReports to export all details
  const handleExportReports = async () => {
    if (!stats || !stats.stats) {
      Alert.alert('Error', 'No data to export.');
      return;
    }
    let rows = [['Name', 'Email', 'Attendance Date', 'Attendance Time']];
    let usersToExport = stats.stats;
    if (selectedUserEmail !== 'ALL') {
      usersToExport = usersToExport.filter(u => u.email === selectedUserEmail);
    }
    usersToExport.forEach(user => {
      if (user.records.length === 0) {
        rows.push([user.fullname, user.email, '', '']);
      } else {
        user.records.forEach(record => {
          const dateObj = new Date(record);
          const date = dateObj.toLocaleDateString();
          const time = dateObj.toLocaleTimeString();
          rows.push([user.fullname, user.email, date, time]);
        });
      }
    });
    // Convert to CSV string
    const csv = rows.map(r => r.map(f => '"' + (f || '') + '"').join(',')).join('\n');
    try {
      const fileUri = FileSystem.documentDirectory + `attendance_report_${Date.now()}.csv`;
      await FileSystem.writeAsStringAsync(fileUri, csv, { encoding: FileSystem.EncodingType.UTF8 });
      await Sharing.shareAsync(fileUri);
    } catch (err) {
      Alert.alert('Error', err.message || 'Failed to export CSV');
    }
  };

  // Render the admin dashboard UI
  return (
    <View style={styles.container}>
      <View style={styles.header}>
        <View style={styles.logoContainer}>
          <Image
            source={require('../assets/itskylogo.png')}
            style={styles.headerLogo}
            resizeMode="contain"
          />
          <Text style={styles.logo}>ITSky</Text>
          <Text style={styles.subtitle}>Admin Dashboard</Text>
        </View>
        <TouchableOpacity style={styles.logoutButton} onPress={handleLogout}>
          <Text style={styles.logoutText}>Logout</Text>
        </TouchableOpacity>
      </View>

      <View style={styles.adminInfo}>
        <Text style={styles.adminText}>Greetings, {adminName}</Text>
        <Text style={styles.adminRole}>Administrator</Text>
      </View>

      <ScrollView
        style={styles.content}
        refreshControl={
          <RefreshControl refreshing={refreshing} onRefresh={onRefresh} />
        }
      >
        <View style={styles.statsHeader}>
          <Text style={styles.statsTitle}>Employee Attendance Statistics</Text>
          <Text style={styles.statsSubtitle}>
            Current Month: {stats?.daysThisMonth || 0} working days
          </Text>
          {/* Search Bar */}
          <TextInput
            style={styles.searchInput}
            placeholder="Search by name or email..."
            placeholderTextColor="#888"
            value={searchQuery}
            onChangeText={setSearchQuery}
            autoCapitalize="none"
            autoCorrect={false}
          />
        </View>

        {isLoading ? (
          <View style={styles.loadingContainer}>
            <ActivityIndicator size="large" color="#dc2626" />
            <Text style={styles.loadingText}>Loading statistics...</Text>
          </View>
        ) : (
          renderUserStats()
        )}

        {/* User Picker for Export */}
        <View style={{ marginBottom: 16 }}>
          <Text style={{ fontSize: 16, fontWeight: 'bold', marginBottom: 4 }}>Export Attendance For:</Text>
          <View style={{ backgroundColor: '#fff', borderRadius: 8, borderWidth: 1, borderColor: '#e5e5e5' }}>
            <Picker
              selectedValue={selectedUserEmail}
              onValueChange={setSelectedUserEmail}
              style={{ height: 52 }}
            >
              <Picker.Item label="All Users" value="ALL" />
              {stats?.stats?.map((user, idx) => (
                <Picker.Item key={user.email || idx} label={user.fullname + ' (' + user.email + ')'} value={user.email} />
              ))}
            </Picker>
          </View>
        </View>

        <View style={styles.actionsContainer}>
          <TouchableOpacity
            style={styles.actionButton}
            onPress={() => navigation.navigate('ManageUsers')}
          >
            <Text style={styles.actionButtonText}>Manage Users</Text>
          </TouchableOpacity>
          
          <TouchableOpacity
            style={styles.exportButton}
            onPress={handleExportReports}
          >
            <Text style={styles.exportButtonText}>Export Reports (CSV)</Text>
          </TouchableOpacity>
        </View>
      </ScrollView>
    </View>
  );
}

// Styles for the admin dashboard screen
const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f5f5f5',
  },
  header: {
    backgroundColor: 'white', // Changed from '#dc2626' (red) to white
    paddingTop: 50,
    paddingBottom: 20,
    paddingHorizontal: 20,
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  logoContainer: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
  },
  headerLogo: {
    width: 40,
    height: 20,
    marginRight: 10,
  },
  logo: {
    fontSize: 24,
    fontWeight: 'bold',
    color: '#222', // Changed from 'white' to dark for contrast
  },
  subtitle: {
    fontSize: 14,
    color: '#333', // Changed from 'rgba(255, 255, 255, 0.8)' to dark
    marginTop: 2,
  },
  logoutButton: {
    padding: 8,
  },
  logoutText: {
    color: '#222', // Changed from 'white' to dark
    fontSize: 16,
    fontWeight: '600',
  },
  adminInfo: {
    backgroundColor: 'white',
    padding: 20,
    borderBottomWidth: 1,
    borderBottomColor: '#e5e5e5',
  },
  adminText: {
    fontSize: 18,
    fontWeight: 'bold',
    color: '#333',
  },
  adminRole: {
    fontSize: 14,
    color: '#dc2626',
    marginTop: 4,
  },
  content: {
    flex: 1,
    padding: 20,
  },
  statsHeader: {
    marginBottom: 20,
  },
  statsTitle: {
    fontSize: 20,
    fontWeight: 'bold',
    color: '#222', // Changed from red to dark
    marginBottom: 4,
  },
  statsSubtitle: {
    fontSize: 14,
    color: '#666', // Use a neutral color
    marginBottom: 12,
  },
  loadingContainer: {
    alignItems: 'center',
    padding: 40,
  },
  loadingText: {
    marginTop: 10,
    fontSize: 16,
    color: '#666',
  },
  userCard: {
    backgroundColor: 'white',
    borderRadius: 12,
    padding: 16,
    marginBottom: 16,
    shadowColor: '#000',
    shadowOffset: {
      width: 0,
      height: 2,
    },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 3,
  },
  userHeader: {
    marginBottom: 12,
  },
  userName: {
    fontSize: 18,
    fontWeight: 'bold',
    color: '#333',
  },
  userEmail: {
    fontSize: 14,
    color: '#666',
    marginTop: 2,
  },
  userStats: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginBottom: 12,
  },
  statItem: {
    alignItems: 'center',
    flex: 1,
  },
  statLabel: {
    fontSize: 12,
    color: '#666',
    marginBottom: 4,
  },
  statValue: {
    fontSize: 18,
    fontWeight: 'bold',
    color: '#dc2626',
  },
  attendanceDates: {
    borderTopWidth: 1,
    borderTopColor: '#e5e5e5',
    paddingTop: 12,
  },
  datesLabel: {
    fontSize: 14,
    fontWeight: '600',
    color: '#333',
    marginBottom: 4,
  },
  datesText: {
    fontSize: 12,
    color: '#666',
    lineHeight: 16,
  },
  actionsContainer: {
    marginTop: 20,
    marginBottom: 40,
  },
  actionButton: {
    backgroundColor: '#dc2626',
    padding: 16,
    borderRadius: 8,
    alignItems: 'center',
    marginBottom: 12,
  },
  actionButtonText: {
    color: '#222', // Changed from red to dark
    fontSize: 16,
    fontWeight: 'bold',
  },
  searchInput: {
    backgroundColor: '#fff',
    borderRadius: 8,
    borderWidth: 1,
    borderColor: '#e5e5e5',
    paddingHorizontal: 12,
    paddingVertical: 8,
    fontSize: 16,
    marginTop: 8,
    marginBottom: 8,
    color: '#222',
  },
  noResultsContainer: {
    alignItems: 'center',
    padding: 32,
  },
  noResultsText: {
    fontSize: 16,
    color: '#888',
  },
  manageUsersButton: {
    backgroundColor: '#4CAF50', // A different color for manage users
    padding: 16,
    borderRadius: 8,
    alignItems: 'center',
    marginBottom: 12,
  },
  manageUsersButtonText: {
    color: '#fff', // White text
    fontSize: 16,
    fontWeight: 'bold',
  },
  exportButton: {
    backgroundColor: '#2196F3',
    padding: 16,
    borderRadius: 8,
    alignItems: 'center',
    marginBottom: 12,
  },
  exportButtonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: 'bold',
  },
}); 