import urllib.request
import json

base_url = "http://127.0.0.1:8000/api/v1"

def test_apis():
    # Login
    req = urllib.request.Request(
        f"{base_url}/auth/login/",
        data=json.dumps({
            "login_id": "student@globaltech.edu",
            "password": "password123",
            "college_code": "DUMMY-01"
        }).encode("utf-8"),
        headers={"Content-Type": "application/json"}
    )
    try:
        with urllib.request.urlopen(req) as resp:
            login_data = json.loads(resp.read().decode("utf-8"))
    except Exception as e:
        print(f"Login failed: {e}")
        return

    token = login_data["access"]
    user_id = login_data["user"]["id"]
    print(f"--- LOGIN SUCCESS (User ID: {user_id}) ---\n")

    # TEST 1: Profile
    print("--- TEST 1: Profile ---")
    try:
        req1 = urllib.request.Request(f"{base_url}/students/profiles/1/", headers={"Authorization": f"Bearer {token}"})
        with urllib.request.urlopen(req1) as resp:
            print(json.dumps(json.loads(resp.read().decode("utf-8")), indent=2))
    except Exception as e:
        print(f"Profile failed: {e}")

    # TEST 2: Dashboard
    print("\n--- TEST 2: Dashboard ---")
    try:
        # try /me/ first
        req2 = urllib.request.Request(f"{base_url}/students/profiles/me/dashboard/", headers={"Authorization": f"Bearer {token}"})
        with urllib.request.urlopen(req2) as resp:
            print(json.dumps(json.loads(resp.read().decode("utf-8")), indent=2))
    except Exception as e:
        print(f"Dashboard with /me/ failed: {e}, trying with user_id")
        try:
            req2 = urllib.request.Request(f"{base_url}/students/profiles/1/dashboard/", headers={"Authorization": f"Bearer {token}"})
            with urllib.request.urlopen(req2) as resp:
                print(json.dumps(json.loads(resp.read().decode("utf-8")), indent=2))
        except Exception as e2:
            print(f"Dashboard with profile ID 1 failed: {e2}")

    # TEST 3: Attendance Summary
    print("\n--- TEST 3: Attendance Summary ---")
    try:
        req3 = urllib.request.Request(f"{base_url}/students/profiles/1/attendance_summary/", headers={"Authorization": f"Bearer {token}"})
        with urllib.request.urlopen(req3) as resp:
            print(json.dumps(json.loads(resp.read().decode("utf-8")), indent=2))
    except Exception as e:
        print(f"Attendance summary failed: {e}")

if __name__ == "__main__":
    test_apis()
