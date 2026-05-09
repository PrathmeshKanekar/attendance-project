import requests
import json

BASE_URL = "http://127.0.0.1:8000/api/v1"

def run_tests():
    # 0. Login
    login_data = {
        "login_id": "principal@smartcampus.edu",
        "password": "password123"
    }
    response = requests.post(f"{BASE_URL}/auth/login/", json=login_data)
    login_json = response.json()
    token = login_json['access']
    headers = {"Authorization": f"Bearer {token}"}
    
    print("--- LOGIN RESPONSE ---")
    print(json.dumps(login_json, indent=4))
    
    # 1. Dashboard Stats
    stats_response = requests.get(f"{BASE_URL}/reports/dashboard/", headers=headers)
    print("\n--- TEST 1: DASHBOARD STATS ---")
    print(json.dumps(stats_response.json(), indent=4))
    
    # 2. Pending Approvals
    # Create a fresh pending user first to ensure we have data
    # (Using shell would be better but let's see current state)
    approvals_response = requests.get(f"{BASE_URL}/approvals/approvals/", headers=headers)
    print("\n--- TEST 2: ALL APPROVALS ---")
    print(json.dumps(approvals_response.json(), indent=4))
    
    # 5. Defaulters
    defaulters_response = requests.get(f"{BASE_URL}/students/profiles/?has_low_attendance=true", headers=headers)
    print("\n--- TEST 5: DEFAULTERS LIST ---")
    print(json.dumps(defaulters_response.json(), indent=4))

if __name__ == "__main__":
    run_tests()
