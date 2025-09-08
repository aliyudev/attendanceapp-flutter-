// DashboardScreen.js - Main User Dashboard
// This is the primary screen for authenticated users in the ITSky Attendance mobile app.
// It provides a comprehensive interface for clocking in, viewing attendance statistics,
// and managing user sessions. Uses Supabase for all attendance and user data.
//
// Features:
// - GPS-based clock-in with location verification
// - Real-time attendance calendar display
// - User authentication status management
// - Admin role detection and redirection
// - Offline data persistence with AsyncStorage
//
// @author ITSky Solutions
// @version 1.4.0

import React, { useState, useEffect, useCallback } from 'react';
import {
  View,
  Text,
  TouchableOpacity,
  StyleSheet,
  Alert,
  ScrollView,
  Image,
  SafeAreaView,
} from 'react-native';
import AsyncStorage from '@react-native-async-storage/async-storage';
import * as Location from 'expo-location';
import { supabase } from '../config/api';
import { OFFICE, OFFICE_RADIUS_METERS, isOfficeConfigSet } from '../config/location';
import faceRecognitionService from '../services/faceRecognitionService';

function formatUtcTime(isoString) {
  try {
    const date = new Date(isoString);
    return `${date.toISOString().slice(11, 19)} UTC`;
  } catch (e) {
    return isoString;
  }
}

function haversineMeters(pointA, pointB) {
  try {
    const toRadians = (deg) => (deg * Math.PI) / 180;
    const earthRadiusMeters = 6371000;
    const dLat = toRadians(pointB.lat - pointA.lat);
    const dLng = toRadians(pointB.lng - pointA.lng);
    const lat1 = toRadians(pointA.lat);
    const lat2 = toRadians(pointB.lat);
    const a = Math.sin(dLat / 2) ** 2 + Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2;
    const c = 2 * Math.asin(Math.sqrt(a));
    return earthRadiusMeters * c;
  } catch (e) {
    return Number.POSITIVE_INFINITY;
  }
}

export default function DashboardScreen({ navigation }) {
  const [userEmail, setUserEmail] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [clockInMessage, setClockInMessage] = useState('');
  const [locationStatus, setLocationStatus] = useState('');
  const [statusIndicator, setStatusIndicator] = useState('#ffa500');
  const [attendanceStats, setAttendanceStats] = useState(null);
  const [alreadyClockedIn, setAlreadyClockedIn] = useState(false);
  const [selectedDayInfo, setSelectedDayInfo] = useState(null);
  const [username, setUsername] = useState('User');
  const [hasFaceRegistered, setHasFaceRegistered] = useState(false);
  const [faceVerificationData, setFaceVerificationData] = useState(null);

  const loadCalendar = useCallback(async () => {
    try {
      const { data: { user } } = await supabase.auth.getUser();
      const userId = user?.id || await AsyncStorage.getItem('userId');
      const now = new Date();
      const year = now.getFullYear();
      const month = now.getMonth();
      const monthStart = `${year}-${(month + 1).toString().padStart(2, '0')}-01`;
      const monthEnd = `${year}-${(month + 1).toString().padStart(2, '0')}-31`;
      const { data, error } = await supabase
        .from('attendance')
        .select('id, clock_in_time')
        .eq('user_id', userId)
        .gte('clock_in_time', monthStart)
        .lte('clock_in_time', monthEnd);
      if (error) throw error;
      const attendanceRecords = (data || []).map(r => ({
        date: r.clock_in_time.slice(0, 10),
        time: r.clock_in_time.slice(11, 19),
        full: r.clock_in_time
      }));
      const daysInMonth = new Date(year, month + 1, 0).getDate();
      let workingDays = 0;
      for (let day = 1; day <= daysInMonth; day++) {
        const date = new Date(year, month, day);
        const dayOfWeek = date.getDay();
        if (dayOfWeek >= 1 && dayOfWeek <= 4) workingDays++;
      }
      const daysPresent = attendanceRecords.length;
      setAttendanceStats({ daysPresent, daysThisMonth: workingDays, records: attendanceRecords });
      const today = new Date().toISOString().slice(0, 10);
      const todayRecord = attendanceRecords.find(record => record.date === today);
      setAlreadyClockedIn(!!todayRecord);
      if (todayRecord) {
        setClockInMessage(`✅ Already clocked in today at ${formatUtcTime(todayRecord.full)}`);
        setStatusIndicator('#4CAF50');
      }
    } catch (error) {
      console.error('Error loading stats:', error);
      try {
        const now = new Date();
        const year = now.getFullYear();
        const month = now.getMonth();
        const daysInMonth = new Date(year, month + 1, 0).getDate();
        let workingDays = 0;
        for (let day = 1; day <= daysInMonth; day++) {
          const date = new Date(year, month, day);
          const dayOfWeek = date.getDay();
          if (dayOfWeek >= 1 && dayOfWeek <= 4) workingDays++;
        }
        setAttendanceStats({ daysPresent: 0, daysThisMonth: workingDays, records: [] });
      } catch (e) {
        // no-op: if fallback calculation fails for any reason, suppress to avoid blocking UI
      }
    }
  }, []);

  const requestLocationPermission = async () => {
    const { status } = await Location.requestForegroundPermissionsAsync();
    if (status !== 'granted') {
      Alert.alert(
        'Location Permission Required',
        'This app needs location access to verify you are at the office for attendance.',
        [{ text: 'OK' }]
      );
      return false;
    }
    return true;
  };

  const getGPSLocation = async () => {
    try {
      const location = await Location.getCurrentPositionAsync({
        accuracy: Location.Accuracy.High,
        timeout: 10000,
      });
      return location;
    } catch (error) {
      console.error('Error getting location:', error);
      return null;
    }
  };

  const proceedWithClockIn = useCallback(async () => {
    try {
      setLocationStatus('Requesting GPS location...');
      const hasPermission = await requestLocationPermission();
      if (!hasPermission) {
        setIsLoading(false);
        return;
      }
      const position = await getGPSLocation();
      if (!position) {
        throw new Error('GPS location is required. Please allow location access.');
      }
      const { coords } = position;
      
      if (isOfficeConfigSet()) {
        const distance = haversineMeters(
          { lat: coords.latitude, lng: coords.longitude },
          OFFICE
        );
        setLocationStatus(`Distance to office: ${Math.round(distance)} m`);
        if (distance > OFFICE_RADIUS_METERS) {
          setStatusIndicator('#dc2626');
          Alert.alert(
            'Too far from office',
            `You are ${Math.round(distance)} m away. Move within ${OFFICE_RADIUS_METERS} m to clock in.`,
            [{ text: 'OK' }]
          );
          setIsLoading(false);
          return;
        }
      } else {
        setLocationStatus('GPS acquired');
      }

      // Attach user_id to satisfy RLS WITH CHECK (user_id = auth.uid())
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) throw new Error('Not authenticated');

      const attendanceData = {
        user_id: user.id,
        clock_in_time: new Date().toISOString(),
        location_lat: coords.latitude,
        location_lng: coords.longitude,
        accuracy: coords.accuracy,
      };

      if (faceVerificationData) {
        attendanceData.face_match_confidence = faceVerificationData.confidence;
        attendanceData.face_template_id = faceVerificationData.templateId;
        attendanceData.liveness_passed = true;
      }

      const { error } = await supabase
        .from('attendance')
        .insert([attendanceData]);
        
      if (error) throw error;
      
      setClockInMessage('✅ Clock-in successful!');
      setStatusIndicator('#4CAF50');
      setAlreadyClockedIn(true);
      loadCalendar();
    } catch (error) {
      setClockInMessage('❌ Clock-in failed.');
      setStatusIndicator('#dc2626');
      Alert.alert('Clock-in Failed', error.message || 'Unable to clock in.');
    } finally {
      setIsLoading(false);
      setFaceVerificationData(null);
    }
  }, [faceVerificationData, loadCalendar]);

  const handleFaceVerificationSuccess = useCallback((verificationData) => {
    setFaceVerificationData(verificationData);
    setLocationStatus('Face verified successfully');
    setStatusIndicator('#4CAF50');
    proceedWithClockIn();
  }, [proceedWithClockIn]);

  const handleFaceVerificationFailure = useCallback((error) => {
    setClockInMessage('❌ Face verification failed.');
    setStatusIndicator('#dc2626');
    setIsLoading(false);
    Alert.alert('Face Verification Failed', error || 'Unable to verify face.');
  }, []);

  useEffect(() => {
    const checkUserType = async () => {
      try {
        const isAdmin = await AsyncStorage.getItem('isAdmin');
        if (isAdmin === 'true') {
          navigation.replace('AdminDashboard');
        }
      } catch (error) {
        console.error('Error checking user type:', error);
      }
    };

    const loadUserData = async () => {
      try {
        const email = await AsyncStorage.getItem('userEmail');
        setUserEmail(email);
        if (email) {
          const { data, error } = await supabase
            .from('users')
            .select('name')
            .eq('email', email)
            .single();
          if (!error && data && data.name) {
            setUsername(data.name);
          } else {
            setUsername(email);
          }
        } else {
          setUsername('User');
        }
      } catch (error) {
        console.error('Error loading user data:', error);
        setUsername('User');
      }
    };

    const checkFaceRegistration = async () => {
      try {
        const hasRegistered = await faceRecognitionService.hasRegisteredFace();
        setHasFaceRegistered(hasRegistered);
      } catch (error) {
        console.error('Error checking face registration:', error);
        setHasFaceRegistered(false);
      }
    };

    checkUserType();
    loadUserData();
    loadCalendar();
    checkFaceRegistration();
  }, [loadCalendar, navigation]);

  useEffect(() => {
    const unsubscribe = navigation.addListener('focus', () => {
      const route = navigation.getState()?.routes?.find(r => r.name === 'Dashboard');
      const verificationResult = route?.params?.verificationResult;
      const faceRegistered = route?.params?.faceRegistered;

      // Refresh face registration status when returning from enrollment
      if (typeof faceRegistered === 'boolean') {
        setHasFaceRegistered(faceRegistered);
        navigation.setParams({ faceRegistered: null });
      }

      if (verificationResult) {
        if (verificationResult.success) {
          handleFaceVerificationSuccess(verificationResult.data);
        } else {
          handleFaceVerificationFailure(verificationResult.error?.message);
        }
        navigation.setParams({ verificationResult: null });
      }
    });

    return unsubscribe;
  }, [navigation, handleFaceVerificationSuccess, handleFaceVerificationFailure]);

  const handleClockIn = async () => {
    if (alreadyClockedIn) {
      Alert.alert('Already Clocked In', 'You have already clocked in today.');
      return;
    }

    setIsLoading(true);
    setClockInMessage('');
    setLocationStatus('');
    setStatusIndicator('#ffa500');

    try {
      if (hasFaceRegistered) {
        navigation.navigate('FaceVerification');
      } else {
        setIsLoading(false);
        navigation.navigate('FaceEnrollment');
      }
    } catch (error) {
      setClockInMessage('❌ Clock-in failed.');
      setStatusIndicator('#dc2626');
      Alert.alert('Clock-in Failed', error.message || 'Unable to clock in.');
      setIsLoading(false);
    }
  };

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

  const renderCalendar = () => {
    if (!attendanceStats) return null;

    const now = new Date();
    const year = now.getFullYear();
    const month = now.getMonth();
    const daysInMonth = new Date(year, month + 1, 0).getDate();
    const presentDays = new Set(
      attendanceStats.records
        .filter(r => r.date)
        .map(r => Number(r.date.split('-')[2]))
    );
    const weekDays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    const firstDay = new Date(year, month, 1).getDay();

    let calendarRows = [];
    
    let headerRow = [];
    weekDays.forEach(day => {
      headerRow.push(
        <View key={day} style={styles.calendarHeader}>
          <Text style={styles.calendarHeaderText}>{day}</Text>
        </View>
      );
    });
    calendarRows.push(
      <View key="header" style={styles.calendarRow}>
        {headerRow}
      </View>
    );

    let currentRow = [];
    
    for (let i = 0; i < firstDay; i++) {
      currentRow.push(<View key={`empty-${i}`} style={styles.calendarCell} />);
    }

    for (let day = 1; day <= daysInMonth; day++) {
      if ((firstDay + day - 1) % 7 === 0 && day !== 1) {
        calendarRows.push(
          <View key={`row-${Math.floor((firstDay + day - 1) / 7)}`} style={styles.calendarRow}>
            {currentRow}
          </View>
        );
        currentRow = [];
      }

      const date = new Date(year, month, day);
      const dayOfWeek = date.getDay();
      const isWorkingDay = dayOfWeek >= 1 && dayOfWeek <= 4;
      const isFriday = dayOfWeek === 5;
      const presentRecord = attendanceStats.records.find(r => Number(r.date.split('-')[2]) === day);
      const isPresent = !!presentRecord;
      
      let cellStyle = [styles.calendarCell];
      let textStyle = [styles.calendarCellText];
      
      if (isPresent) {
        cellStyle.push(styles.calendarCellPresent);
        textStyle.push(styles.calendarCellTextPresent);
      } else if (isWorkingDay) {
        cellStyle.push(styles.calendarCellAbsent);
        textStyle.push(styles.calendarCellTextAbsent);
      } else if (isFriday) {
        cellStyle.push(styles.calendarCellFriday);
        textStyle.push(styles.calendarCellTextFriday);
      } else {
        cellStyle.push(styles.calendarCellWeekend);
        textStyle.push(styles.calendarCellTextWeekend);
      }
      
      const handleDayPress = () => {
        if (isWorkingDay) {
          setSelectedDayInfo({
            date: `${year}-${(month + 1).toString().padStart(2, '0')}-${day.toString().padStart(2, '0')}`,
            time: presentRecord ? presentRecord.time : null,
            full: presentRecord ? presentRecord.full : null,
            isPresent
          });
        }
      };
      currentRow.push(
        <TouchableOpacity key={day} style={cellStyle} onPress={handleDayPress} disabled={!isWorkingDay}>
          <Text style={textStyle}>{day}</Text>
        </TouchableOpacity>
      );
    }

    if (currentRow.length > 0) {
      calendarRows.push(
        <View key="last-row" style={styles.calendarRow}>
          {currentRow}
        </View>
      );
    }

    const monthNames = ['January', 'February', 'March', 'April', 'May', 'June', 
                       'July', 'August', 'September', 'October', 'November', 'December'];
    
    return (
      <View style={styles.calendarContainer}>
        <Text style={styles.monthTitle}>{monthNames[month]} {year}</Text>
        {calendarRows}
        {selectedDayInfo && (
          <View style={{ marginTop: 12, alignItems: 'center' }}>
            <Text style={{ fontSize: 16, fontWeight: 'bold' }}>
              {selectedDayInfo.date}
            </Text>
            {selectedDayInfo.isPresent && selectedDayInfo.full ? (
              <Text style={{ fontSize: 15, color: '#4CAF50' }}>Clocked in at: {formatUtcTime(selectedDayInfo.full)}</Text>
            ) : (
              <Text style={{ fontSize: 15, color: '#dc2626' }}>Not clocked in</Text>
            )}
          </View>
        )}
        <Text style={styles.statsText}>
          <Text style={styles.bold}>Days Present:</Text> {attendanceStats.daysPresent} / {attendanceStats.daysThisMonth}
        </Text>
      </View>
    );
  };

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.header}>
        <View style={styles.headerLeft}>
          <Image
            source={require('../assets/itskylogo.png')}
            style={styles.headerLogo}
            resizeMode="contain"
          />
          <Text style={styles.welcomeText}>Welcome, {username}!</Text>
        </View>
        <View style={{ flexDirection: 'row', gap: 10 }}>
          <TouchableOpacity 
            style={styles.faceButton} 
            onPress={() => navigation.navigate('FaceEnrollment')}
          >
            <Text style={styles.faceButtonText}>
              {hasFaceRegistered ? '👤' : '➕👤'}
            </Text>
          </TouchableOpacity>
          <TouchableOpacity style={styles.logoutButton} onPress={handleLogout}>
            <Text style={styles.logoutButtonText}>Logout</Text>
          </TouchableOpacity>
        </View>
      </View>

      <ScrollView style={styles.scrollContent} showsVerticalScrollIndicator={false}>
        <View style={styles.statsSection}>
          <Text style={styles.sectionTitle}>Attendance Calendar (This Month)</Text>
          {renderCalendar()}
        </View>
      </ScrollView>

      <View style={styles.bottomSection}>
      <View style={styles.clockInSection}>
        <TouchableOpacity
          style={[
            styles.clockInButton, 
            isLoading && styles.buttonDisabled,
            alreadyClockedIn && styles.buttonClockedIn
          ]}
          onPress={handleClockIn}
          disabled={isLoading || alreadyClockedIn}
        >
          <Text style={styles.clockInButtonText}>
            {isLoading ? 'Processing...' : alreadyClockedIn ? 'Already Clocked In' : 'Clock In'}
          </Text>
        </TouchableOpacity>

          {/* Status messages */}
        {clockInMessage ? (
          <Text style={styles.clockInMessage}>{clockInMessage}</Text>
        ) : null}

        {locationStatus ? (
          <View style={styles.locationStatusContainer}>
            <View style={[styles.statusIndicator, { backgroundColor: statusIndicator }]} />
            <Text style={styles.locationStatusText}>{locationStatus}</Text>
          </View>
        ) : null}
      </View>
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#fff',
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    padding: 20,
    backgroundColor: '#fff',
    borderBottomWidth: 1,
    borderBottomColor: '#eee',
  },
  headerLeft: {
    flexDirection: 'row',
    alignItems: 'center',
    flex: 1,
    marginRight: 15,
  },
  headerLogo: {
    width: 60,
    height: 30,
    marginRight: 12,
  },
  welcomeText: {
    fontSize: 18,
    fontWeight: '600',
    color: '#111',
    flex: 1,
  },
  logoutButton: {
    backgroundColor: '#dc2626',
    paddingHorizontal: 15,
    paddingVertical: 8,
    borderRadius: 8,
  },
  logoutButtonText: {
    color: 'white',
    fontSize: 14,
    fontWeight: '600',
  },
  faceButton: {
    backgroundColor: '#4CAF50',
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderRadius: 8,
    minWidth: 40,
    alignItems: 'center',
  },
  faceButtonText: {
    fontSize: 16,
  },
  scrollContent: {
    flex: 1,
  },
  bottomSection: {
    backgroundColor: '#fff',
    borderTopWidth: 1,
    borderTopColor: '#eee',
    paddingBottom: 20,
  },
  clockInSection: {
    paddingHorizontal: 20,
    paddingTop: 20,
  },
  clockInButton: {
    backgroundColor: '#dc2626',
    padding: 16,
    borderRadius: 12,
    alignItems: 'center',
    marginBottom: 10,
  },
  buttonDisabled: {
    backgroundColor: '#aaa',
  },
  buttonClockedIn: {
    backgroundColor: '#4CAF50',
  },
  clockInButtonText: {
    color: 'white',
    fontSize: 18,
    fontWeight: '600',
  },
  clockInMessage: {
    marginTop: 8,
    color: '#198754',
    fontWeight: '600',
    fontSize: 14,
    textAlign: 'center',
  },
  locationStatusContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    marginTop: 10,
    padding: 12,
    backgroundColor: '#f8f9fa',
    borderRadius: 8,
  },
  statusIndicator: {
    width: 20,
    height: 20,
    borderRadius: 10,
    marginRight: 10,
  },
  locationStatusText: {
    fontSize: 14,
    color: '#666',
    flex: 1,
  },
  statsSection: {
    backgroundColor: '#f8f8f8',
    borderRadius: 8,
    padding: 16,
    margin: 20,
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: 'bold',
    marginBottom: 16,
    color: '#111',
  },
  calendarContainer: {
    marginTop: 8,
  },
  monthTitle: {
    fontSize: 16,
    fontWeight: '600',
    color: '#666',
    textAlign: 'center',
    marginBottom: 12,
  },
  calendarRow: {
    flexDirection: 'row',
    marginBottom: 1,
  },
  calendarHeader: {
    flex: 1,
    height: 36,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: '#f3f3f3',
    borderWidth: 1,
    borderColor: '#eee',
  },
  calendarHeaderText: {
    fontSize: 14,
    fontWeight: '600',
    color: '#111',
  },
  calendarCell: {
    flex: 1,
    height: 36,
    justifyContent: 'center',
    alignItems: 'center',
    borderWidth: 1,
    borderColor: '#eee',
    backgroundColor: '#fff',
  },
  calendarCellPresent: {
    backgroundColor: '#dc2626',
  },
  calendarCellAbsent: {
    backgroundColor: '#fef2f2',
    borderWidth: 2,
    borderColor: '#dc2626',
  },
  calendarCellWeekend: {
    backgroundColor: '#f0f0f0',
    opacity: 0.6,
  },
  calendarCellFriday: {
    backgroundColor: '#f5f5f5',
    opacity: 0.7,
  },
  calendarCellText: {
    fontSize: 14,
    color: '#111',
  },
  calendarCellTextPresent: {
    color: '#fff',
    fontWeight: '700',
  },
  calendarCellTextAbsent: {
    color: '#dc2626',
    fontWeight: '600',
  },
  calendarCellTextWeekend: {
    color: '#888',
    fontStyle: 'italic',
  },
  calendarCellTextFriday: {
    color: '#aaa',
  },
  statsText: {
    marginTop: 8,
    fontSize: 16,
    color: '#111',
  },
  bold: {
    fontWeight: 'bold',
  },
});