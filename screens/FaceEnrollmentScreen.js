// FaceEnrollmentScreen.js - Face Registration Interface
// Allows users to register their face for attendance verification

import React, { useState, useRef, useEffect, useMemo } from 'react';
import {
  View,
  Text,
  TouchableOpacity,
  StyleSheet,
  Alert,
  SafeAreaView,
  ActivityIndicator,
  Image,
  Linking,
} from 'react-native';
import { Camera, useCameraDevice, useFrameProcessor } from 'react-native-vision-camera';
import { runOnJS } from 'react-native-reanimated';
import { scanFaces } from 'vision-camera-face-detector';
import * as FileSystem from 'expo-file-system';
import faceRecognitionService from '../services/faceRecognitionService';
import { supabase } from '../config/supabase';

export default function FaceEnrollmentScreen({ navigation }) {
  const [cameraPermission, setCameraPermission] = useState(null);
  const [isLoading, setIsLoading] = useState(false);
  const [message, setMessage] = useState('Position your face as instructed');
  const cameraRef = useRef(null);
  const device = useCameraDevice('front');

  // Enrollment state machine: front -> left -> right -> smile
  const steps = useMemo(() => ['front', 'left', 'right', 'smile'], []);
  const [currentStepIndex, setCurrentStepIndex] = useState(0);
  const currentStep = steps[currentStepIndex];
  const [captures, setCaptures] = useState({ front: null, left: null, right: null, smile: null });
  const [guidanceOk, setGuidanceOk] = useState(false);
  const [lockCapture, setLockCapture] = useState(false); // debounce to avoid multi-captures

  useEffect(() => {
    (async () => {
      const status = await Camera.requestCameraPermission();
      setCameraPermission(status === 'granted');
      checkExistingEnrollment();
    })();
  }, []);

  const checkExistingEnrollment = async () => {
    try {
      const hasRegistered = await faceRecognitionService.hasRegisteredFace();
      if (hasRegistered) {
        Alert.alert(
          'Face Already Registered',
          'You already have a face registered. Would you like to update it?',
          [
            { text: 'Cancel', onPress: () => navigation.goBack() },
            { text: 'Update', onPress: () => {} }
          ]
        );
      }
    } catch (error) {
      console.error('Error checking enrollment:', error);
    }
  };

  // Determine if current face metrics satisfy the instruction
  const isConditionSatisfied = (face) => {
    const yaw = face?.yawAngle ?? 0;
    const smile = face?.smilingProbability ?? 0;
    switch (currentStep) {
      case 'front':
        return Math.abs(yaw) <= 10;
      case 'left':
        return yaw >= 30 && yaw <= 50;
      case 'right':
        return yaw <= -30 && yaw >= -50;
      case 'smile':
        return smile >= 0.7;
      default:
        return false;
    }
  };

  const proceedToNextStep = () => {
    setCurrentStepIndex((idx) => Math.min(idx + 1, steps.length - 1));
  };

  const frameSatisfiedDebounceRef = useRef(null);

  const onFacesFromFrame = (faces) => {
    if (!faces || faces.length !== 1 || isLoading || lockCapture) {
      setGuidanceOk(false);
      return;
    }
    const face = faces[0];
    const ok = isConditionSatisfied(face);
    setGuidanceOk(ok);
    if (ok && !lockCapture) {
      // Debounce stability ~400ms
      if (frameSatisfiedDebounceRef.current) clearTimeout(frameSatisfiedDebounceRef.current);
      frameSatisfiedDebounceRef.current = setTimeout(() => {
        void captureSnapshot();
      }, 400);
    } else if (!ok && frameSatisfiedDebounceRef.current) {
      clearTimeout(frameSatisfiedDebounceRef.current);
      frameSatisfiedDebounceRef.current = null;
    }
  };

  const frameProcessor = useFrameProcessor((frame) => {
    'worklet';
    try {
      const faces = scanFaces(frame);
      // Pass detected faces to JS thread
      // eslint-disable-next-line react-hooks/rules-of-hooks
      runOnJS(onFacesFromFrame)(faces);
    } catch (e) {
      // no-op in worklet
    }
  }, [currentStep, isLoading, lockCapture]);

  const captureSnapshot = async () => {
    if (!cameraRef.current || lockCapture) return;
    try {
      setLockCapture(true);
      const snapshot = await cameraRef.current.takeSnapshot({ quality: 90, skipMetadata: true });
      if (!snapshot?.path) throw new Error('Failed to capture snapshot');

      const base64 = await FileSystem.readAsStringAsync(snapshot.path, { encoding: FileSystem.EncodingType.Base64 });
      const stepKey = currentStep;
      setCaptures((prev) => ({ ...prev, [stepKey]: { uri: snapshot.path, base64 } }));

      // Move to next step or start processing if all done
      if (currentStepIndex < steps.length - 1) {
        setMessage('Great! Proceed to the next instruction');
        proceedToNextStep();
      } else {
        setMessage('Processing captures...');
        await processFaceEnrollment();
      }
    } catch (error) {
      console.error('Snapshot error:', error);
      Alert.alert('Capture Error', error.message || 'Failed to capture frame.');
    } finally {
      setTimeout(() => setLockCapture(false), 600);
    }
  };

  const processFaceEnrollment = async () => {
    try {
      setIsLoading(true);
      setMessage('Processing faces...');

      // Ensure all four captured
      const allHave = steps.every((k) => captures[k] && captures[k].base64);
      if (!allHave) throw new Error('Not all captures were collected.');

      // Process each capture to get embeddings
      const results = [];
      for (const key of steps) {
        const base64 = captures[key].base64;
        const res = await faceRecognitionService.processFace(base64, false);
        if (!res?.face_detected) throw new Error(`No face detected in ${key} capture.`);
        if (res.quality_score < 0.3) throw new Error(`${key} capture quality too low. Try again.`);
        results.push(res.embedding);
      }

      // Average embeddings
      const avgEmbedding = (() => {
        const length = results[0].length;
        const sum = new Array(length).fill(0);
        for (const emb of results) {
          for (let i = 0; i < length; i++) sum[i] += emb[i];
        }
        return sum.map((v) => v / results.length);
      })();

      setMessage('Registering face...');
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) throw new Error('User not authenticated');

      await faceRecognitionService.registerFace(avgEmbedding, user.id);

      Alert.alert(
        'Success!',
        'Face registered successfully.',
        [{ text: 'OK', onPress: () => navigation.navigate('Dashboard', { faceRegistered: true }) }]
      );

    } catch (error) {
      console.error('Face enrollment error:', error);
      Alert.alert('Registration Failed', error.message || 'Failed to process face.', [
        { text: 'OK', onPress: resetFlow }
      ]);
    } finally {
      setIsLoading(false);
      setMessage('');
    }
  };

  const resetFlow = () => {
    setCaptures({ front: null, left: null, right: null, smile: null });
    setCurrentStepIndex(0);
    setIsLoading(false);
    setMessage('Position your face as instructed');
  };

  // Main render logic
  const renderContent = () => {
    // Default camera view
    return (
      <>
        <View style={styles.header}>
          <Text style={styles.title}>Face Registration</Text>
          <Text style={styles.subtitle}>{getInstructionText()}</Text>
          <Text style={styles.progressText}>Step {currentStepIndex + 1} of {steps.length}</Text>
        </View>
        <View style={styles.cameraContainer}>
          {device && cameraPermission ? (
            <Camera
              ref={cameraRef}
              style={styles.camera}
              device={device}
              isActive={!isLoading}
              pixelFormat="yuv"
              frameProcessor={frameProcessor}
              frameProcessorFps={8}
            />
          ) : (
            <View style={[styles.processingContainer]}>
              <ActivityIndicator size="large" color="#dc2626" />
              <Text style={styles.processingText}>Requesting camera permission...</Text>
            </View>
          )}
          <View style={[styles.cameraOverlay, StyleSheet.absoluteFillObject]} pointerEvents="none">
            <View style={[styles.faceGuide, guidanceOk && styles.faceGuideDetected]} />
          </View>
        </View>
        <View style={styles.buttonContainer}>
          <TouchableOpacity style={[styles.button, styles.secondaryButton]} onPress={() => navigation.goBack()}>
            <Text style={styles.secondaryButtonText}>Cancel</Text>
          </TouchableOpacity>
        </View>
      </>
    );
  };

  const getInstructionText = () => {
    switch (currentStep) {
      case 'front':
        return 'Look straight at the camera';
      case 'left':
        return 'Turn your head to the left';
      case 'right':
        return 'Turn your head to the right';
      case 'smile':
        return 'Smile naturally';
      default:
        return message;
    }
  };

  return <SafeAreaView style={styles.container}>{renderContent()}</SafeAreaView>;
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#fff',
  },
  header: {
    padding: 20,
    alignItems: 'center',
  },
  title: {
    fontSize: 24,
    fontWeight: 'bold',
    color: '#111',
    marginBottom: 8,
  },
  subtitle: {
    fontSize: 16,
    color: '#666',
    textAlign: 'center',
    paddingHorizontal: 20,
  },
  progressText: {
    fontSize: 14,
    color: '#dc2626',
    fontWeight: '600',
    marginTop: 4,
  },
  cameraContainer: {
    flex: 1,
    marginHorizontal: 20,
    borderRadius: 20,
    overflow: 'hidden',
    position: 'relative',
    marginBottom: 20,
  },
  camera: {
    flex: 1,
  },
  cameraOverlay: {
    justifyContent: 'center',
    alignItems: 'center',
  },
  faceGuide: {
    width: 280,
    height: 280,
    borderRadius: 140,
    borderWidth: 3,
    borderColor: 'rgba(255, 255, 255, 0.5)',
    borderStyle: 'dashed',
  },
  faceGuideDetected: {
    borderColor: '#4CAF50',
    borderStyle: 'solid',
  },
  buttonContainer: {
    flexDirection: 'row',
    justifyContent: 'space-around',
    padding: 20,
    gap: 15,
  },
  button: {
    flex: 1,
    padding: 16,
    borderRadius: 12,
    alignItems: 'center',
  },
  primaryButton: {
    backgroundColor: '#dc2626',
  },
  secondaryButton: {
    backgroundColor: '#f3f4f6',
  },
  buttonText: {
    color: 'white',
    fontWeight: '600',
    fontSize: 16,
  },
  secondaryButtonText: {
    color: '#4b5563',
    fontWeight: '600',
    fontSize: 16,
  },
  processingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  processingText: {
    marginTop: 16,
    fontSize: 16,
    color: '#666',
  },
  centerContent: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: 20,
  },
  errorText: {
    fontSize: 18,
    fontWeight: '600',
    color: '#dc2626',
    marginBottom: 8,
  },
  permissionButtonContainer: {
    flexDirection: 'row',
    marginTop: 20,
    gap: 15,
  },
});