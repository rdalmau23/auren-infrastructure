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

def update_user(token, user_id, user_data):
    url = f"{BASE_URL}/admin/realms/auren/users/{user_id}"
    req = urllib.request.Request(url, data=json.dumps(user_data).encode('utf-8'), method="PUT")
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req, context=ctx) as response:
        pass

def create_user(token, user_data):
    url = f"{BASE_URL}/admin/realms/auren/users"
    req = urllib.request.Request(url, data=json.dumps(user_data).encode('utf-8'), method="POST")
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, context=ctx) as response:
            # Location header gives the new user ID
            location = response.headers.get("Location")
            return location.split("/")[-1]
    except urllib.error.HTTPError as e:
        print(f"Failed to create user {user_data.get('username')}: {e.read().decode()}")
        return None

def assign_role(token, user_id, role_obj):
    url = f"{BASE_URL}/admin/realms/auren/users/{user_id}/role-mappings/realm"
    req = urllib.request.Request(url, data=json.dumps([role_obj]).encode('utf-8'), method="POST")
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req, context=ctx) as response:
        pass

try:
    token = get_admin_token()
    users = get_users(token)
    
    # 1. Update existing users (psych and patient) to require TOTP
    for user in users:
        if user['username'] in ['psych@auren.dev', 'patient@auren.dev']:
            actions = user.get('requiredActions', [])
            if 'CONFIGURE_TOTP' not in actions:
                actions.append('CONFIGURE_TOTP')
                user['requiredActions'] = actions
                update_user(token, user['id'], user)
                print(f"Added CONFIGURE_TOTP to {user['username']}")

    # 2. Check and Create Admin Profesional
    admin_prof_username = "admin_profesional@auren.dev"
    if not any(u['username'] == admin_prof_username for u in users):
        user_data = {
            "username": admin_prof_username,
            "email": admin_prof_username,
            "firstName": "Admin",
            "lastName": "Profesional",
            "enabled": True,
            "emailVerified": True,
            "credentials": [{"type": "password", "value": "admin123", "temporary": False}],
            "requiredActions": [] # NO 2FA
        }
        user_id = create_user(token, user_data)
        if user_id:
            role = get_role_id(token, "CENTER_ADMIN")
            if role:
                assign_role(token, user_id, role)
                print(f"Created {admin_prof_username} with CENTER_ADMIN role (No 2FA)")

    # 3. Check and Create Admin Paciente
    admin_pac_username = "admin_paciente@auren.dev"
    if not any(u['username'] == admin_pac_username for u in users):
        user_data = {
            "username": admin_pac_username,
            "email": admin_pac_username,
            "firstName": "Admin",
            "lastName": "Paciente",
            "enabled": True,
            "emailVerified": True,
            "credentials": [{"type": "password", "value": "admin123", "temporary": False}],
            "requiredActions": [] # NO 2FA
        }
        user_id = create_user(token, user_data)
        if user_id:
            role = get_role_id(token, "PATIENT")
            if role:
                assign_role(token, user_id, role)
                print(f"Created {admin_pac_username} with PATIENT role (No 2FA)")

    # 4. Enable directAccessGrantsEnabled for auren-mobile
    url_clients = f"{BASE_URL}/admin/realms/auren/clients"
    req_clients = urllib.request.Request(url_clients)
    req_clients.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(req_clients, context=ctx) as response:
        clients = json.loads(response.read().decode())
        
        for client in clients:
            if client.get("clientId") == "auren-mobile":
                if not client.get("directAccessGrantsEnabled"):
                    client["directAccessGrantsEnabled"] = True
                    client_id = client["id"]
                    url_update_client = f"{url_clients}/{client_id}"
                    req_update_client = urllib.request.Request(url_update_client, data=json.dumps(client).encode('utf-8'), method="PUT")
                    req_update_client.add_header("Authorization", f"Bearer {token}")
                    req_update_client.add_header("Content-Type", "application/json")
                    with urllib.request.urlopen(req_update_client, context=ctx) as r:
                        pass
                    print("Enabled Direct Access Grants for auren-mobile")
                break

    print("Keycloak configuration complete.")

except Exception as e:
    print(f"Error: {e}")
    sys.exit(1)

    # 5. Add postLogoutRedirectUris to auren-cms
    for client in clients:
        if client.get("clientId") == "auren-cms":
            attributes = client.get("attributes", {})
            attributes["post.logout.redirect.uris"] = "http://localhost:3000/*##http://localhost:3000"
            client["attributes"] = attributes
            
            client_id = client["id"]
            url_update_client = f"{url_clients}/{client_id}"
            req_update_client = urllib.request.Request(url_update_client, data=json.dumps(client).encode('utf-8'), method="PUT")
            req_update_client.add_header("Authorization", f"Bearer {token}")
            req_update_client.add_header("Content-Type", "application/json")
            with urllib.request.urlopen(req_update_client, context=ctx) as r:
                pass
            print("Updated postLogoutRedirectUris for auren-cms")
            break

