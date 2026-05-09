import requests
import json

base_url = "http://127.0.0.1:8000/api/v1"
login_url = f"{base_url}/auth/login/"

def test_login(login_id, password):
    payload = {
        "login_id": login_id,
        "password": password
    }
    headers = {"Content-Type": "application/json"}
    
    print(f"Testing login for: {login_id}")
    try:
        response = requests.post(login_url, data=json.dumps(payload), headers=headers)
        print(f"Status Code: {response.status_code}")
        print(f"Response Body: {response.text}")
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    # Test with dummy credentials
    test_login("teacher@pccoe.edu", "wrongpassword")
    test_login("teacher@pccoe.edu", "admin123")
