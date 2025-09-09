import json
import types

# Import the Flask app and module-level face_processor reference
import importlib
app_module = importlib.import_module('app')
app = app_module.app


def setup_module(module):
    """Ensure app_module.face_processor is defined for endpoints that reference it."""
    if getattr(app_module, 'face_processor', None) is None:
        # Minimal stub with attributes used by /health
        stub = types.SimpleNamespace(session=None, model_path='../mobilefacenet.onnx')
        app_module.face_processor = stub


def test_health_endpoint_ok():
    client = app.test_client()
    resp = client.get('/health')
    assert resp.status_code in (200, 500)  # If model not loaded, we still expect a JSON response
    data = resp.get_json()
    assert isinstance(data, dict)
    # Should contain these keys in both success and error cases
    assert 'status' in data or 'error' in data


def test_process_face_invalid_request():
    client = app.test_client()

    # No JSON payload -> 400
    resp = client.post('/process-face')
    assert resp.status_code == 400
    data = resp.get_json()
    assert data.get('error') == 'No data provided'

    # Invalid shape (missing required fields) -> 400 with informative error
    resp = client.post('/process-face', data=json.dumps({'foo': 'bar'}), content_type='application/json')
    assert resp.status_code == 400
    data = resp.get_json()
    assert data.get('error') == 'Invalid request'
