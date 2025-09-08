// LoadingScreen.js - App Initialization and Auth Check
// This screen checks the user's authentication status and routes them to the appropriate dashboard or login screen.
//
// Features:
// - Checks AsyncStorage for user token, email, and admin status
// - Simulates loading for better UX
// - Redirects to AdminDashboard, Dashboard, or Login as appropriate
//
// @author ITSky Solutions
// @version 1.3.0

// Import React and useEffect for lifecycle management
import React, { useEffect } from 'react';
// Import React Native components for UI
import { View, Text, StyleSheet, ActivityIndicator, Image } from 'react-native';
// Import AsyncStorage for local storage
import AsyncStorage from '@react-native-async-storage/async-storage';
// Import Supabase client for session restoration
import { supabase } from '../config/api';

// Main LoadingScreen component
export default function LoadingScreen({ navigation }) {
  // useEffect to check authentication status on mount
  useEffect(() => {
    checkAuthStatus();
  }, []);

  // Function to check authentication and route user
  const checkAuthStatus = async () => {
    try {
      // First, try to restore Supabase session
      const { data: { session }, error: sessionError } = await supabase.auth.getSession();
      console.log('Session restoration result:', { session: !!session, error: sessionError });

      // Retrieve persisted session keys
      const email = await AsyncStorage.getItem('userEmail');
      const isAdmin = await AsyncStorage.getItem('isAdmin');

      // Simulate loading time for user experience
      await new Promise(resolve => setTimeout(resolve, 1500));

      // Check if we have a valid session or stored credentials
      if (session || email) {
        // Route to appropriate dashboard based on user type
        if (isAdmin === 'true') {
          navigation.replace('AdminDashboard');
        } else {
          navigation.replace('Dashboard');
        }
      } else {
        // If not authenticated, go to login
        navigation.replace('Login');
      }
    } catch (error) {
      // Handle errors and fallback to login
      console.error('Error checking auth status:', error);
      navigation.replace('Login');
    }
  };

  // Render the loading screen UI
  return (
    <View style={styles.container}>
      <View style={styles.content}>
        <Image
          source={require('../assets/itskylogo.png')}
          style={styles.logoImage}
          resizeMode="contain"
        />
        <Text style={styles.subtitle}>Attendance System</Text>
        <ActivityIndicator size="large" color="#dc2626" style={styles.spinner} />
        <Text style={styles.loadingText}>Loading...</Text>
      </View>
    </View>
  );
}

// Styles for the loading screen
const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#fff',
    justifyContent: 'center',
    alignItems: 'center',
  },
  content: {
    alignItems: 'center',
  },
  logoImage: {
    width: 150,
    height: 75,
    marginBottom: 20,
  },
  subtitle: {
    fontSize: 16,
    color: '#666',
    marginBottom: 40,
  },
  spinner: {
    marginBottom: 20,
  },
  loadingText: {
    fontSize: 16,
    color: '#666',
  },
}); 