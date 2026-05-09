import urllib.request
import urllib.parse
import json

def run_tests():
    base_url = "http://localhost:8000/api/v1"
    
    # Login to get token
    login_data = json.dumps({
        "login_id": "student@globaltech.edu",
        "password": "password123",
        "college_code": "DUMMY-01"
    }).encode("utf-8")
    
    req = urllib.request.Request(f"{base_url}/auth/login/", data=login_data, headers={"Content-Type": "application/json"})
    
    try:
        with urllib.request.urlopen(req) as response:
            resp_data = json.loads(response.read().decode("utf-8"))
            token = resp_data.get("access")
            print("--- LOGIN SUCCESS ---")
    except Exception as e:
        print(f"Login failed: {e}")
        return

    # TEST 1: Active sessions
    print("\n--- TEST 1: Active sessions ---")
    session_id = None
    try:
        req1 = urllib.request.Request(f"{base_url}/attendance/sessions/?status=active", headers={"Authorization": f"Bearer {token}"})
        with urllib.request.urlopen(req1) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            print(json.dumps(data, indent=2))
            if isinstance(data, list) and len(data) > 0:
                session_id = data[0].get("id")
            elif isinstance(data, dict) and "results" in data and len(data["results"]) > 0:
                session_id = data["results"][0].get("id")
    except Exception as e:
        print(f"Test 1 failed: {e}")

    if not session_id:
        # Fallback dummy ID just to see response shape of error
        session_id = "dummy-session-id"

    # TEST 2: Location check
    print("\n--- TEST 2: Location check ---")
    try:
        loc_data = json.dumps({
            "session_id": session_id,
            "lat": 18.5204,
            "lng": 73.8567,
            "altitude": 560.0
        }).encode("utf-8")
        req2 = urllib.request.Request(f"{base_url}/attendance/check-location/", data=loc_data, headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"})
        with urllib.request.urlopen(req2) as resp:
            print(json.dumps(json.loads(resp.read().decode("utf-8")), indent=2))
    except urllib.error.HTTPError as e:
        print(f"Test 2 HTTPError: {e.code}")
        print(e.read().decode("utf-8"))
    except Exception as e:
        print(f"Test 2 failed: {e}")

    # TEST 3: Mark attendance
    print("\n--- TEST 3: Mark attendance ---")
    try:
        mark_data = json.dumps({
            "session_id": session_id,
            "lat": 18.5204,
            "lng": 73.8567,
            "altitude": 560.0,
            "device_id": "test-device-001"
        }).encode("utf-8")
        req3 = urllib.request.Request(f"{base_url}/attendance/mark/", data=mark_data, headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"})
        with urllib.request.urlopen(req3) as resp:
            print(json.dumps(json.loads(resp.read().decode("utf-8")), indent=2))
    except urllib.error.HTTPError as e:
        print(f"Test 3 HTTPError: {e.code}")
        print(e.read().decode("utf-8"))
    except Exception as e:
        print(f"Test 3 failed: {e}")

    # TEST 4: Attendance logs
    print("\n--- TEST 4: Attendance logs ---")
    try:
        req4 = urllib.request.Request(f"{base_url}/attendance/logs/", headers={"Authorization": f"Bearer {token}"})
        with urllib.request.urlopen(req4) as resp:
            print(json.dumps(json.loads(resp.read().decode("utf-8")), indent=2))
    except urllib.error.HTTPError as e:
        print(f"Test 4 HTTPError: {e.code}")
        print(e.read().decode("utf-8"))
    except Exception as e:
        print(f"Test 4 failed: {e}")

if __name__ == "__main__":
    run_tests()
