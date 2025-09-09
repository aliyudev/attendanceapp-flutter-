# Face Processing Service (MobileFaceNet)

Small Flask service that processes face images into 128‑d embeddings using the MobileFaceNet ONNX model. Used by the mobile app for enrollment and verification.

## Quick Start

Prereqs: Python 3.10+, pip, OpenCV runtime dependencies.

Install deps:
```bash
pip install -r requirements.txt
```

Run the service:
```bash
set MODEL_PATH=../mobilefacenet.onnx
set PORT=8001
python app.py
```

Verify it’s running:
- Health: GET http://localhost:8001/health
- Model info: GET http://localhost:8001/model-info

## API

- POST `/process-face`
  - Body (JSON): `{ "imageData": "<base64>", "returnFaceImage": false }`
  - Returns: `{ face_detected, embedding[128], quality_score, processing_time, face_image? }`

- POST `/process-face` (mock register)
  - Body (JSON): `{ "action": "register", "embedding": [..], "userId": "uuid" }`
  - Returns: `{ success, message, userId }`

- GET `/health`
  - Returns status, model metadata, and Python version

## Configuration

- `MODEL_PATH` — path to `mobilefacenet.onnx` (default: `../mobilefacenet.onnx`)
- `PORT` — HTTP port (default: `8001`)

## Docker (optional)

Build and run:
```bash
docker build -t face-service .
docker run -p 8001:8001 -e MODEL_PATH=/app/mobilefacenet.onnx face-service
```

## Notes

- Embeddings are normalized (L2); the client computes cosine similarity.
- The Haar cascade is used for face detection; ensure good lighting and frontal faces.
- This service does not store images; it returns embeddings to the caller.
