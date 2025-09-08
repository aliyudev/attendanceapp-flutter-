// SignupScreen.js - User Registration Screen
// This screen allows new users to register for the attendance system using Supabase Auth.
//
// Features:
// - Email/password registration via Supabase Auth
// - Enforces @itskysolutions.com email domain
// - Password strength validation
// - Stores user profile in Supabase users table
//
// @author ITSky Solutions
// @version 1.3.0

// Import React and useState for state management
import React, { useState } from 'react';
// Import React Native components for UI
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  StyleSheet,
  Alert,
  KeyboardAvoidingView,
  Platform,
  ScrollView,
  Image,
} from 'react-native';
// Import Supabase client for API calls
import { supabase } from '../config/api';

// Main SignupScreen component
export default function SignupScreen({ navigation }) {
  // State variables for form fields and loading state
  const [fullname, setFullname] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [isLoading, setIsLoading] = useState(false);

  // Function to handle signup logic
  const handleSignup = async () => {
    // Validate all fields are filled
    if (!fullname || !email || !password || !confirmPassword) {
      Alert.alert('Error', 'Please fill in all fields');
      return;
    }

    // Check if passwords match
    if (password !== confirmPassword) {
      Alert.alert('Error', 'Passwords do not match');
      return;
    }

    // Ensure email is from the correct domain
    if (!email.endsWith('@itskysolutions.com')) {
      Alert.alert('Error', 'Email must be @itskysolutions.com');
      return;
    }

    // Password strength validation
    if (password.length < 8) {
      Alert.alert('Error', 'Password must be at least 8 characters');
      return;
    }
    if (!/[A-Z]/.test(password)) {
      Alert.alert('Error', 'Password must include at least one uppercase letter');
      return;
    }
    if (!/[!@#$%^&*(),.?":{}|<>]/.test(password)) {
      Alert.alert('Error', 'Password must include at least one special symbol');
      return;
    }

    // Set loading state
    setIsLoading(true);

    try {
      // Attempt to sign up user with Supabase Auth
      const { data, error } = await supabase.auth.signUp({
        email,
        password,
        options: { data: { name: fullname } }
      });
      if (error) throw error;
      // Optionally, insert into users table for profile
      const user = data.user;
      if (user) {
        const { error: profileError } = await supabase
          .from('users')
          .insert([{ id: user.id, name: fullname, email }]);
        if (profileError) throw profileError;
      }
      // Show success alert and navigate to login
      Alert.alert(
        'Success',
        'Account created successfully! Please sign in.',
        [
          {
            text: 'OK',
            onPress: () => navigation.navigate('Login'),
          },
        ]
      );
    } catch (error) {
      // Handle signup errors
      console.error('Signup error:', error);
      Alert.alert(
        'Signup Failed',
        error.message || 'Registration failed. Please try again.'
      );
    } finally {
      // Reset loading state
      setIsLoading(false);
    }
  };

  // Render the signup form UI
  return (
    <KeyboardAvoidingView
      style={styles.container}
      behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
    >
      <ScrollView contentContainerStyle={styles.scrollContainer}>
        <View style={styles.logoContainer}>
          <Image
            source={require('../assets/itskylogo.png')}
            style={styles.logoImage}
            resizeMode="contain"
          />
          <Text style={styles.subtitle}>Attendance System</Text>
        </View>

        <View style={styles.formContainer}>
          <Text style={styles.title}>Create Account</Text>
          
          <View style={styles.inputContainer}>
            <TextInput
              style={[styles.input, { color: '#222' }]}
              placeholder="Enter your full name"
              placeholderTextColor="#888"
              value={fullname}
              onChangeText={setFullname}
              autoCapitalize="words"
            />
          </View>

          <View style={styles.inputContainer}>
            <TextInput
              style={[styles.input, { color: '#222' }]}
              placeholder="Enter your email (@itskysolutions.com)"
              placeholderTextColor="#888"
              value={email}
              onChangeText={setEmail}
              keyboardType="email-address"
              autoCapitalize="none"
              autoCorrect={false}
            />
          </View>

          <View style={styles.inputContainer}>
            <TextInput
              style={[styles.input, { color: '#222' }]}
              placeholder="Enter your password"
              placeholderTextColor="#888"
              value={password}
              onChangeText={setPassword}
              secureTextEntry
              autoCapitalize="none"
            />
          </View>

          <View style={styles.inputContainer}>
            <TextInput
              style={[styles.input, { color: '#222' }]}
              placeholder="Confirm your password"
              placeholderTextColor="#888"
              value={confirmPassword}
              onChangeText={setConfirmPassword}
              secureTextEntry
              autoCapitalize="none"
            />
          </View>

          <TouchableOpacity
            style={[styles.button, isLoading && styles.buttonDisabled]}
            onPress={handleSignup}
            disabled={isLoading}
          >
            <Text style={styles.buttonText}>
              {isLoading ? 'Creating Account...' : 'Create Account'}
            </Text>
          </TouchableOpacity>

          <TouchableOpacity
            style={styles.linkButton}
            onPress={() => navigation.navigate('Login')}
          >
            <Text style={styles.linkText}>
              Already have an account? Sign In
            </Text>
          </TouchableOpacity>
        </View>
      </ScrollView>
    </KeyboardAvoidingView>
  );
}

// Styles for the signup screen
const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#fff',
  },
  scrollContainer: {
    flexGrow: 1,
    justifyContent: 'center',
    padding: 20,
  },
  logoContainer: {
    alignItems: 'center',
    marginBottom: 40,
  },
  logoImage: {
    width: 120,
    height: 60,
    marginBottom: 10,
  },
  subtitle: {
    fontSize: 16,
    color: '#666',
    marginTop: 5,
  },
  formContainer: {
    backgroundColor: '#fff',
    padding: 32,
    borderRadius: 16,
    shadowColor: '#000',
    shadowOffset: {
      width: 0,
      height: 2,
    },
    shadowOpacity: 0.07,
    shadowRadius: 16,
    elevation: 5,
  },
  title: {
    fontSize: 24,
    fontWeight: 'bold',
    textAlign: 'center',
    marginBottom: 30,
    color: '#dc2626',
  },
  inputContainer: {
    marginBottom: 12,
  },
  input: {
    borderWidth: 1,
    borderColor: '#dc2626',
    borderRadius: 8,
    padding: 12,
    fontSize: 16,
    backgroundColor: '#fff',
  },
  button: {
    backgroundColor: '#dc2626',
    padding: 12,
    borderRadius: 8,
    alignItems: 'center',
    marginTop: 8,
  },
  buttonDisabled: {
    backgroundColor: '#aaa',
  },
  buttonText: {
    color: 'white',
    fontSize: 16,
    fontWeight: '600',
  },
  linkButton: {
    marginTop: 20,
    alignItems: 'center',
  },
  linkText: {
    color: '#dc2626',
    fontSize: 16,
    textDecorationLine: 'underline',
  },
}); 