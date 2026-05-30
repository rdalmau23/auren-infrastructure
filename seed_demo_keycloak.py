import urllib.request
import json
import ssl
import sys

# Disable SSL verification for localhost dev
ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

BASE_URL = "http://localhost:8180"

def get_admin_token():
    url = f"{BASE_URL}/realms/master/protocol/openid-connect/token"
    data = "client_id=admin-cli&username=admin&password=admin&grant_type=password".encode('utf-8')
    req = urllib.request.Request(url, data=data)
    with urllib.request.urlopen(req, context=ctx) as response:
        return json.loads(response.read().decode())['access_token']

def get_users(token):
    url = f"{BASE_URL}/admin/realms/auren/users"
    req = urllib.request.Request(url)
    req.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(req, context=ctx) as response:
        return json.loads(response.read().decode())

def get_role_id(token, role_name):
    url = f"{BASE_URL}/admin/realms/auren/roles/{role_name}"
    req = urllib.request.Request(url)
    req.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req, context=ctx) as response:
            return json.loads(response.read().decode())
    except:
        return None

def create_user(token, user_data, custom_id=None):
    url = f"{BASE_URL}/admin/realms/auren/users"
    if custom_id:
        user_data["id"] = custom_id
    req = urllib.request.Request(url, data=json.dumps(user_data).encode('utf-8'), method="POST")
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, context=ctx) as response:
            location = response.headers.get("Location")
            return location.split("/")[-1] if location else custom_id
    except urllib.error.HTTPError as e:
        if e.code == 409:
            print(f"User {user_data.get('username')} already exists. Reusing ID.")
            return custom_id
        print(f"Failed to create user {user_data.get('username')}: {e.read().decode()}")
        return None

def assign_role(token, user_id, role_obj):
    url = f"{BASE_URL}/admin/realms/auren/users/{user_id}/role-mappings/realm"
    req = urllib.request.Request(url, data=json.dumps([role_obj]).encode('utf-8'), method="POST")
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, context=ctx) as response:
            pass
    except:
        pass

def create_demo_user(token, email, first_name, last_name, role_name, keycloak_id):
    user_data = {
        "id": keycloak_id,
        "username": email,
        "email": email,
        "firstName": first_name,
        "lastName": last_name,
        "enabled": True,
        "emailVerified": True,
        "credentials": [{"type": "password", "value": "auren123", "temporary": False}],
        "requiredActions": [] # NO 2FA for demo
    }
    created_id = create_user(token, user_data, keycloak_id)
    if created_id:
        role = get_role_id(token, role_name)
        if role:
            assign_role(token, created_id, role)
            print(f"✅ User {email} ready with role {role_name}")

try:
    print("Starting Keycloak demo data seed...")
    token = get_admin_token()

    demo_users = [
        ("superadmin@auren.dev", "Super", "Admin", "SUPER_ADMIN", "11111111-1111-1111-1111-111111111111"),
        ("admin_centro_1@auren.dev", "Admin", "Centro 1", "CENTER_ADMIN", "22222222-2222-2222-2222-222222222221"),
        ("admin_centro_2@auren.dev", "Admin", "Centro 2", "CENTER_ADMIN", "22222222-2222-2222-2222-222222222222"),
        ("psicologo_1@auren.dev", "Carlos", "Psicólogo 1", "PSYCHOLOGIST", "33333333-3333-3333-3333-333333333331"),
        ("psiquiatra_2@auren.dev", "Marta", "Psiquiatra 2", "PSYCHIATRIST", "33333333-3333-3333-3333-333333333332"),
        ("paciente_demo1@auren.dev", "Juan", "Paciente 1", "PATIENT", "44444444-4444-4444-4444-444444444441"),
        ("paciente_demo2@auren.dev", "María", "Paciente 2", "PATIENT", "44444444-4444-4444-4444-444444444442"),
        ("paciente_demo3@auren.dev", "Luis", "Paciente 3", "PATIENT", "44444444-4444-4444-4444-444444444443"),
        ("paciente_demo4@auren.dev", "Ana", "Paciente 4", "PATIENT", "44444444-4444-4444-4444-444444444444")
    ]

    for email, fn, ln, role, kc_id in demo_users:
        create_demo_user(token, email, fn, ln, role, kc_id)

    print("Keycloak demo seed completed.")

except Exception as e:
    print(f"Error: {e}")
    sys.exit(1)
