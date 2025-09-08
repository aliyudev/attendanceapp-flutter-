// ManageUsersScreen.js - Admin User Management Screen
// This screen allows admins to view and delete users from the system.
// Uses Supabase for all user management operations.
//
// Features:
// - List all users
// - Delete user with confirmation
// - Uses Supabase client for all data operations
//
// @author ITSky Solutions
// @version 1.3.0

import React, { useEffect, useState } from 'react';
import { View, Text, FlatList, TouchableOpacity, Alert, ActivityIndicator, StyleSheet } from 'react-native';
import { supabase } from '../config/api';

export default function ManageUsersScreen({ navigation }) {
  const [users, setUsers] = useState([]);
  const [isLoading, setIsLoading] = useState(true);

  // Fetch all users from Supabase
  const fetchUsers = async () => {
    setIsLoading(true);
    const { data, error } = await supabase.from('users').select('id, name, email');
    if (!error) setUsers(data);
    setIsLoading(false);
  };

  useEffect(() => {
    fetchUsers();
  }, []);

  // Handle user deletion with confirmation dialog
  const handleDelete = (userId, userEmail) => {
    Alert.alert(
      'Delete User',
      `Are you sure you want to delete ${userEmail}? This cannot be undone!`,
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Delete', style: 'destructive',
          onPress: async () => {
            const { error } = await supabase.from('users').delete().eq('id', userId);
            if (error) {
              Alert.alert('Error', error.message);
            } else {
              Alert.alert('Deleted', 'User deleted successfully.');
              fetchUsers();
            }
          }
        }
      ]
    );
  };

  return (
    <View style={styles.container}>
      {/* Back button to return to previous screen */}
      <TouchableOpacity onPress={() => navigation.goBack()} style={styles.backButton}>
        <Text style={styles.backButtonText}>{'< Back'}</Text>
      </TouchableOpacity>
      <Text style={styles.title}>Manage Users</Text>
      {isLoading ? (
        <ActivityIndicator size="large" color="#4CAF50" />
      ) : (
        <FlatList
          data={users}
          keyExtractor={item => item.id}
          renderItem={({ item }) => (
            <View style={styles.userRow}>
              <View>
                <Text style={styles.userName}>{item.name}</Text>
                <Text style={styles.userEmail}>{item.email}</Text>
              </View>
              <TouchableOpacity
                style={styles.deleteButton}
                onPress={() => handleDelete(item.id, item.email)}
              >
                <Text style={styles.deleteButtonText}>Delete</Text>
              </TouchableOpacity>
            </View>
          )}
        />
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#fff', padding: 16 },
  title: { fontSize: 22, fontWeight: 'bold', marginBottom: 16, textAlign: 'center' },
  userRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', paddingVertical: 12, borderBottomWidth: 1, borderColor: '#eee' },
  userName: { fontSize: 16, fontWeight: 'bold' },
  userEmail: { fontSize: 14, color: '#888' },
  deleteButton: { backgroundColor: '#f44336', padding: 8, borderRadius: 6 },
  deleteButtonText: { color: '#fff', fontWeight: 'bold' },
  backButton: { marginBottom: 12 },
  backButtonText: { color: '#4CAF50', fontSize: 16 },
}); 