// FaceVerificationScreen.js - Face Verification for Clock-in
// Handles face capture and verification during attendance clock-in

import React, { useEffect, useMemo, useRef, useState } from 'react';
import {
  View,
  Text,
  TouchableOpacity,
  StyleSheet,
  Alert,
  SafeAreaView,
  ActivityIndicator,
} from 'react-native';
import { Camera, useCameraDevice, useFrameProcessor } from 'react-native-vision-camera';
import { runOnJS } from 'react-native-reanimated';
import { scanFaces } from 'vision-camera-face-detector';
import * as FileSystem from 'expo-file-system';
import faceRecognitionService from '../services/faceRecognitionService';

export default function FaceVerificationScreen({ navigation, route }) {
  const [cameraPermission, setCameraPermission] = useState(null);
  const [isLoading, setIsLoading] = useState(false);
  const [message, setMessage] = useState('Position your face in the guide');
  const [verificationAttempts, setVerificationAttempts] = useState(0);
  const cameraRef = useRef(null);
  const device = useCameraDevice('front');
  const [guidanceOk, setGuidanceOk] = useState(false);
  const [captured, setCaptured] = useState(false);
  
  // Request camera permissions and handle focus
  useEffect(() => {
    (async () => {
      const status = await Camera.requestCameraPermission();
      setCameraPermission(status === 'granted');
    })();
    const unsubscribe = navigation.addListener('focus', () => {
      setMessage('Position your face in the guide');
      setVerificationAttempts(0);
      setIsLoading(false);
      setCaptured(false);
    });
    return unsubscribe;
  }, [navigation]);

  // Handle verification success
  const handleSuccess = (data) => {
    navigation.navigate('Dashboard', {
      verificationResult: { success: true, data }
    });
  };

  // Handle verification failure
  const handleFailure = (error) => {
    navigation.navigate('Dashboard', {
      verificationResult: { 
        success: false, 
        error: { message: error?.message || 'Face verification failed' } 
      }
    });
  };
  
  const MAX_ATTEMPTS = 3;

  // Frame-based auto verification
  const faceStableRef = useRef(null);

  const isFrontStable = (face) => {
    const yaw = face?.yawAngle ?? 0;
    return Math.abs(yaw) <= 10;
  };

  const onFacesFromFrame = (faces) => {
    if (!faces || faces.length !== 1 || isLoading || captured) {
      setGuidanceOk(false);
      return;
    }
    const face = faces[0];
    const ok = isFrontStable(face);
    setGuidanceOk(ok);
    if (ok) {
      // Stability debounce ~400ms
      if (faceStableRef.current) clearTimeout(faceStableRef.current);
      faceStableRef.current = setTimeout(() => {
        void captureAndVerifyAuto();
      }, 400);
    } else if (faceStableRef.current) {
      clearTimeout(faceStableRef.current);
      faceStableRef.current = null;
    }
  };

  const frameProcessor = useFrameProcessor((frame) => {
    'worklet';
    try {
      const faces = scanFaces(frame);
      runOnJS(onFacesFromFrame)(faces);
    } catch (e) {
      // ignore in worklet
    }
  }, [isLoading, captured]);

  const captureAndVerifyAuto = async () => {
    if (!cameraRef.current || isLoading || captured) return;
    try {
      setIsLoading(true);
      setCaptured(true);
      setMessage('Capturing...');

      const snapshot = await cameraRef.current.takeSnapshot({ quality: 90, skipMetadata: true });
      if (!snapshot?.path) throw new Error('Failed to capture');
      const base64 = await FileSystem.readAsStringAsync(snapshot.path, { encoding: FileSystem.EncodingType.Base64 });

      setMessage('Processing face...');
      const processResult = await faceRecognitionService.processFace(base64, false);
      if (!processResult.face_detected) throw new Error('No face detected. Ensure your face is clearly visible.');
      if (processResult.quality_score < 0.3) throw new Error('Face quality too low. Improve lighting and try again.');

      setMessage('Verifying identity...');
      const verifyResult = await faceRecognitionService.verifyFace(processResult.embedding);
      if (verifyResult && verifyResult.success && verifyResult.matched) {
        setMessage('Face verified successfully!');
        handleSuccess({
          confidence: verifyResult.confidence,
          templateId: verifyResult.template_id,
          userId: verifyResult.user_id
        });
      } else {
        const errorMessage = verifyResult?.message || `Verification failed${verifyResult?.confidence ? ` (${(verifyResult.confidence * 100).toFixed(1)}% confidence)` : ''}`;
        throw new Error(errorMessage);
      }
    } catch (error) {
      const newAttempts = verificationAttempts + 1;
      setVerificationAttempts(newAttempts);
      if (newAttempts >= MAX_ATTEMPTS) {
        Alert.alert(
          'Verification Failed',
          `Face verification failed after ${MAX_ATTEMPTS} attempts. Please try again later or contact an administrator.`,
          [{ text: 'OK', onPress: () => handleFailure({ message: 'Maximum verification attempts reached.' }) }]
        );
      } else {
        Alert.alert('Verification Failed', error.message, [
          { text: 'Try Again', onPress: () => { setCaptured(false); setMessage('Position your face in the guide'); } }
        ]);
      }
    } finally {
      setIsLoading(false);
    }
  };

  if (cameraPermission === null) {
    return (
      <View style={styles.loadingContainer}>
        <ActivityIndicator size="large" />
      </View>
    );
  }
  if (!cameraPermission) {
    return (
      <View style={styles.permissionContainer}>
        <Text style={styles.permissionText}>
          We need camera permission to verify your identity. Please grant camera access in your device settings.
        </Text>
        <TouchableOpacity 
          style={styles.permissionButton}
          onPress={async () => {
            const status = await Camera.requestCameraPermission();
            setCameraPermission(status === 'granted');
          }}
        >
          <Text style={styles.permissionButtonText}>Grant Permission</Text>
        </TouchableOpacity>
      </View>
    );
  }

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.header}>
        <Text style={styles.title}>Face Verification</Text>
        <Text style={styles.subtitle}>{verificationAttempts > 0 ? `Attempt ${verificationAttempts + 1} of ${MAX_ATTEMPTS}` : 'Align your face within the guide'}</Text>
      </View>

      <View style={styles.cameraContainer}>
        {device ? (
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
          <View style={styles.loadingContainer}><ActivityIndicator size="large" /></View>
        )}
        <View style={styles.overlayContainer} pointerEvents="none">
          <View style={styles.cameraOverlay}>
            <View style={[
              styles.faceGuide,
              (isLoading ? styles.faceGuideProcessing : null),
              (guidanceOk ? styles.faceGuideReady : null)
            ]}>
              {isLoading && (
                <View style={styles.processingOverlay}>
                  <ActivityIndicator size="large" color="white" />
                </View>
              )}
            </View>
          </View>
        </View>
      </View>
      <View style={styles.buttonContainer}>
        <TouchableOpacity 
          style={[styles.button, styles.secondaryButton]} 
          onPress={() => navigation.goBack()}
          disabled={isLoading}
        >
          <Text style={styles.secondaryButtonText}>Cancel</Text>
        </TouchableOpacity>
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#fff',
  },
  loadingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
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
    marginBottom: 8,
  },
  cameraContainer: {
    flex: 1,
    margin: 20,
    borderRadius: 20,
    overflow: 'hidden',
  },
  camera: {
    flex: 1,
    aspectRatio: 3/4,
  },
  overlayContainer: {
    ...StyleSheet.absoluteFillObject,
    justifyContent: 'center',
    alignItems: 'center',
  },
  cameraOverlay: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  faceGuide: {
    width: 250,
    height: 250,
    borderRadius: 125,
    borderWidth: 3,
    borderColor: '#4CAF50',
    borderStyle: 'solid',
  },
  faceGuideProcessing: {
    borderColor: '#ffa500',
  },
  faceGuideReady: {
    borderColor: '#00C853',
  },
  processingOverlay: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    backgroundColor: 'rgba(0, 0, 0, 0.5)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  buttonContainer: {
    flexDirection: 'row',
    padding: 20,
    gap: 15,
  },
  button: {
    flex: 1,
    padding: 16,
    borderRadius: 12,
    alignItems: 'center',
  },
  secondaryButton: {
    backgroundColor: 'transparent',
    borderWidth: 2,
    borderColor: '#dc2626',
  },
  buttonText: {
    color: 'white',
    fontSize: 16,
    fontWeight: '600',
  },
  secondaryButtonText: {
    color: '#dc2626',
    fontSize: 16,
    fontWeight: '600',
  },
  permissionContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: 20,
    backgroundColor: '#fff',
  },
  permissionText: {
    fontSize: 16,
    marginBottom: 20,
    textAlign: 'center',
    color: '#333',
  },
  permissionButton: {
    backgroundColor: '#007AFF',
    paddingHorizontal: 20,
    paddingVertical: 12,
    borderRadius: 8,
  },
  permissionButtonText: {
    color: 'white',
    fontSize: 16,
    fontWeight: '600',
  }
});
