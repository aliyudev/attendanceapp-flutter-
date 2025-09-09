#!/usr/bin/env python3
"""
Face Processing Service for ITSky Attendance System
Handles face detection, alignment, preprocessing, and ONNX inference using MobileFaceNet
"""

import os
import time
import base64
import numpy as np
import cv2
import onnxruntime as ort
from flask import Flask, request, jsonify, Response
from flask_cors import CORS
import logging
from typing import Tuple, Optional, Dict, Any, List
import json
import sys

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)
CORS(app)

# Global face processor instance
face_processor = None

class FaceProcessor:
    def __init__(self, model_path: str = "mobilefacenet.onnx"):
        """Initialize the face processor.

        Parameters:
            model_path: Filesystem path to the MobileFaceNet ONNX model.

        Notes:
            This initializes internal state but defers heavy operations to
            `load_models()`, which loads the ONNX runtime session and the
            OpenCV Haar cascade for face detection.
        """
        # Normalize model path; if not found, try path relative to this file's directory
        candidate = model_path
        if not os.path.isabs(candidate):
            candidate = os.path.abspath(candidate)
        if not os.path.exists(candidate):
            here = os.path.dirname(os.path.abspath(__file__))
            alt = os.path.join(here, os.path.basename(model_path))
            if os.path.exists(alt):
                candidate = alt
        self.model_path = candidate
        self.session = None
        self.face_cascade = None
        self.load_models()
    
    def load_models(self):
        """Load the ONNX model and face detection cascade.

        Loads the MobileFaceNet ONNX model with CPU execution provider and
        configures the OpenCV Haar cascade for frontal face detection.

        Raises:
            FileNotFoundError: If the model or cascade files are missing.
            RuntimeError: If the cascade fails to load into OpenCV.
        """
        try:
            # Load ONNX model
            if not os.path.exists(self.model_path):
                raise FileNotFoundError(f"ONNX model not found at {self.model_path}")
                
            # Set ONNX runtime session options
            so = ort.SessionOptions()
            so.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
            
            # Load the model with optimizations for your CPU
            self.session = ort.InferenceSession(
                self.model_path,
                sess_options=so,
                providers=['CPUExecutionProvider']
            )
            
            logger.info(f"Loaded ONNX model from {self.model_path}")
            
            # Print model info
            input_info = self.session.get_inputs()[0]
            output_info = self.session.get_outputs()[0]
            logger.info(f"Model input: {input_info.name}, shape: {input_info.shape}")
            logger.info(f"Model output: {output_info.name}, shape: {output_info.shape}")
            
            # Load OpenCV face detection cascade
            cascade_path = os.path.join(
                os.path.dirname(cv2.__file__),
                'data',
                'haarcascade_frontalface_default.xml'
            )
            
            if not os.path.exists(cascade_path):
                raise FileNotFoundError(f"Haar cascade file not found at {cascade_path}")
                
            self.face_cascade = cv2.CascadeClassifier(cascade_path)
            
            if self.face_cascade.empty():
                raise RuntimeError("Failed to load face detection cascade")
            
            logger.info("Face detection cascade loaded successfully")
            
        except Exception as e:
            logger.error(f"Error loading models: {e}")
            raise
    
    def detect_faces(self, image: np.ndarray) -> List[Tuple[int, int, int, int]]:
        """Detect faces using the OpenCV Haar cascade.

        Parameters:
            image: BGR image as a NumPy array (H x W x 3) from cv2.imdecode.

        Returns:
            A list of rectangles (x, y, w, h) for each detected face. Returns
            an empty list if no faces are detected or an error occurs.
        """
        try:
            gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
            faces = self.face_cascade.detectMultiScale(
                gray,
                scaleFactor=1.1,
                minNeighbors=5,
                minSize=(80, 80),
                flags=cv2.CASCADE_SCALE_IMAGE
            )
            return faces if faces is not None else []
        except Exception as e:
            logging.error(f"Error in detect_faces: {e}")
            return []
    
    def align_face(self, image: np.ndarray, face_rect: Tuple[int, int, int, int]) -> np.ndarray:
        """Extract and align the face region.

        Parameters:
            image: Original BGR image array.
            face_rect: Tuple (x, y, w, h) for the face bounding box.

        Returns:
            A cropped and resized BGR face image of size 112x112 suitable for
            MobileFaceNet input.
        """
        x, y, w, h = face_rect
        
        # Add padding around face
        padding = int(0.2 * min(w, h))
        x1 = max(0, x - padding)
        y1 = max(0, y - padding)
        x2 = min(image.shape[1], x + w + padding)
        y2 = min(image.shape[0], y + h + padding)
        
        # Extract face region
        face = image[y1:y2, x1:x2]
        
        # Resize to 112x112 for MobileFaceNet
        face_resized = cv2.resize(face, (112, 112))
        
        return face_resized
    
    def preprocess_face(self, face: np.ndarray) -> np.ndarray:
        """Preprocess a face image for ONNX inference.

        Steps:
            - Convert BGR to RGB
            - Normalize to [0,1] then scale to [-1,1]
            - Transpose to CHW
            - Add batch dimension -> (1, 3, 112, 112)

        Returns:
            Float32 NumPy array ready for model input.
        """
        # Convert BGR to RGB
        face_rgb = cv2.cvtColor(face, cv2.COLOR_BGR2RGB)
        
        # Normalize to [0, 1]
        face_normalized = face_rgb.astype(np.float32) / 255.0
        
        # Normalize to [-1, 1] (common for face recognition models)
        face_normalized = (face_normalized - 0.5) / 0.5
        
        # Transpose to CHW format (channels first)
        face_transposed = np.transpose(face_normalized, (2, 0, 1))
        
        # Add batch dimension
        face_batch = np.expand_dims(face_transposed, axis=0)
        
        return face_batch
    
    def get_embedding(self, face_input: np.ndarray) -> np.ndarray:
        """Run ONNX inference to produce a normalized embedding.

        Parameters:
            face_input: Preprocessed batch tensor (1, 3, 112, 112).

        Returns:
            1D NumPy array (length 128) normalized by L2 norm.
        """
        input_name = self.session.get_inputs()[0].name
        output_name = self.session.get_outputs()[0].name
        
        # Run inference
        embedding = self.session.run([output_name], {input_name: face_input})[0]
        
        # Normalize embedding (L2 normalization)
        embedding_normalized = embedding / np.linalg.norm(embedding, axis=1, keepdims=True)
        
        return embedding_normalized[0]  # Remove batch dimension
    
    def assess_face_quality(self, face: np.ndarray) -> float:
        """Compute a simple face quality score.

        Heuristics combine sharpness (Laplacian variance), brightness, and
        contrast into a [0,1] score. Higher is better.

        Returns:
            Quality score as a float between 0 and 1.
        """
        # Convert to grayscale for analysis
        gray = cv2.cvtColor(face, cv2.COLOR_BGR2GRAY)
        
        # Calculate sharpness using Laplacian variance
        laplacian_var = cv2.Laplacian(gray, cv2.CV_64F).var()
        
        # Calculate brightness
        brightness = np.mean(gray)
        
        # Calculate contrast
        contrast = gray.std()
        
        # Simple quality score (0-1)
        # Higher values indicate better quality
        sharpness_score = min(laplacian_var / 1000.0, 1.0)  # Normalize sharpness
        brightness_score = 1.0 - abs(brightness - 128) / 128.0  # Prefer mid-range brightness
        contrast_score = min(contrast / 64.0, 1.0)  # Normalize contrast
        
        quality_score = (sharpness_score * 0.5 + brightness_score * 0.3 + contrast_score * 0.2)
        
        return float(quality_score)
    
    def process_image(self, image_data: str, return_face_image: bool = False) -> Dict[str, Any]:
        """Process a base64 image to produce an embedding and quality metrics.

        Parameters:
            image_data: Base64-encoded JPEG/PNG data URI or raw base64 payload.
            return_face_image: If True, include the aligned face image as base64.

        Returns:
            Dict with keys:
                - face_detected (bool)
                - embedding (list[float]) when detected
                - quality_score (float)
                - processing_time (float seconds)
                - face_image (str, optional data URL)
                - error (str, optional when failure)
        """
        start_time = time.time()
        
        try:
            # Decode base64 image
            image_bytes = base64.b64decode(image_data)
            nparr = np.frombuffer(image_bytes, np.uint8)
            image = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
            
            if image is None:
                raise ValueError("Failed to decode image")
            
            # Detect faces
            faces = self.detect_faces(image)
            
            if len(faces) == 0:
                return {
                    "face_detected": False,
                    "error": "No face detected in image",
                    "processing_time": time.time() - start_time
                }
            
            # Use the largest face
            largest_face = max(faces, key=lambda f: f[2] * f[3])
            
            # Align face
            aligned_face = self.align_face(image, largest_face)
            
            # Assess quality
            quality_score = self.assess_face_quality(aligned_face)
            
            # Preprocess for model
            face_input = self.preprocess_face(aligned_face)
            
            # Get embedding
            embedding = self.get_embedding(face_input)
            
            # Compute bbox-related metrics
            x, y, w, h = map(int, largest_face)
            img_h, img_w = image.shape[:2]
            cx, cy = x + w / 2.0, y + h / 2.0
            icx, icy = img_w / 2.0, img_h / 2.0
            dx, dy = (cx - icx) / img_w, (cy - icy) / img_h  # normalized offset
            box_ratio = float((w * h) / float(img_w * img_h))

            result = {
                "face_detected": True,
                "embedding": embedding.tolist(),
                "quality_score": quality_score,
                "processing_time": time.time() - start_time,
                # bbox and layout info for client-side checks
                "bbox": [x, y, w, h],
                "image_size": [img_w, img_h],
                "face_center": [cx, cy],
                "center_offset": [dx, dy],  # normalized -1..1 approx
                "box_ratio": box_ratio,
            }
            
            # Optionally return face image
            if return_face_image:
                _, buffer = cv2.imencode('.jpg', aligned_face)
                face_image_b64 = base64.b64encode(buffer).decode('utf-8')
                result["face_image"] = f"data:image/jpeg;base64,{face_image_b64}"
            
            return result
            
        except Exception as e:
            logger.error(f"Error processing image: {e}")
            return {
                "face_detected": False,
                "error": str(e),
                "processing_time": time.time() - start_time
            }

@app.route('/health', methods=['GET'])
def health_check() -> Response:
    """Health check endpoint.

    Returns service status, model load state, absolute model path, and
    Python runtime version details. Useful for readiness/liveness probes.
    """
    try:
        return jsonify({
            'status': 'ok',
            'timestamp': time.time(),
            'model_loaded': face_processor.session is not None,
            'model_path': os.path.abspath(face_processor.model_path) if hasattr(face_processor, 'model_path') else None,
            'python_version': f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}"
        })
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        return jsonify({
            'status': 'error',
            'error': str(e)
        }), 500

@app.route('/process-face', methods=['POST'])
def process_face() -> Response:
    """Handle face processing and mock registration.

    Request body options:
        - { imageData, returnFaceImage? } -> returns embedding and quality
        - { action: 'register', embedding, userId } -> mock success response
    """
    try:
        data = request.get_json()
        if not data:
            return jsonify({'error': 'No data provided'}), 400

        # Handle face processing (image to embedding)
        if 'imageData' in data:
            result = face_processor.process_image(
                data['imageData'],
                data.get('returnFaceImage', False)
            )
            
            if not result.get('face_detected', False):
                return jsonify({
                    'error': 'No face detected or face quality too low',
                    'details': result.get('error', 'Unknown error')
                }), 400
                
            return jsonify(result)
            
        # Handle face registration (store embedding)
        elif data.get('action') == 'register' and 'embedding' in data and 'userId' in data:
            # Here you would typically store the embedding in your database
            # For now, we'll just return a success response
            logger.info(f"Storing face embedding for user {data['userId']}")
            return jsonify({
                'success': True,
                'message': 'Face registered successfully',
                'userId': data['userId']
            })
            
        else:
            return jsonify({
                'error': 'Invalid request',
                'details': 'Either provide imageData for processing or action=register with embedding and userId'
            }), 400
            
    except Exception as e:
        logger.exception('Error in face processing endpoint')
        return jsonify({
            'error': 'Face processing failed',
            'details': str(e)
        }), 500

@app.route('/model-info', methods=['GET'])
def model_info():
    """Return ONNX model input/output details and model path."""
    try:
        if face_processor.session is None:
            return jsonify({"error": "Model not loaded"}), 500
        
        input_info = face_processor.session.get_inputs()[0]
        output_info = face_processor.session.get_outputs()[0]
        
        return jsonify({
            "input_name": input_info.name,
            "input_shape": input_info.shape,
            "output_name": output_info.name,
            "output_shape": output_info.shape,
            "model_path": face_processor.model_path
        })
        
    except Exception as e:
        return jsonify({"error": str(e)}), 500

def main():
    """Entrypoint: initialize models and start the Flask app server.

    Respects environment variables:
        - PORT: HTTP port to listen on (default 8001)
        - MODEL_PATH: path to MobileFaceNet ONNX model
    """
    global face_processor
    
    # Configure logging
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
        handlers=[
            logging.StreamHandler(sys.stdout)
        ]
    )
    
    port = int(os.environ.get('PORT', 8001))
    
    try:
        # Get model path from environment or use default within this folder
        model_path = os.environ.get('MODEL_PATH', 'mobilefacenet.onnx')
        
        # Initialize face processor
        logger.info(f"Loading face recognition model from: {os.path.abspath(model_path)}")
        face_processor = FaceProcessor(model_path=model_path)
        
        # Test model loading
        if not face_processor.session:
            raise RuntimeError("Failed to load face recognition model")
            
        logger.info(f"Starting face processing service on port {port}")
        app.run(host='0.0.0.0', port=port, debug=False, use_reloader=False)
        
    except Exception as e:
        logger.exception("Failed to start face processing service")
        sys.exit(1)

if __name__ == '__main__':
    main()
