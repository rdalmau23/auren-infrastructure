import urllib.request
import json
import base64

try:
    url = "http://localhost:8180/realms/auren/protocol/openid-connect/token"
    data = "client_id=auren-cms&username=superadmin@auren.dev&password=auren123&grant_type=password".encode('utf-8')
    req = urllib.request.Request(url, data=data)
    with urllib.request.urlopen(req) as response:
        token = json.loads(response.read().decode())['access_token']
        parts = token.split('.')
        payload = json.loads(base64.urlsafe_b64decode(parts[1] + '==').decode('utf-8'))
        print("Roles:", payload.get("realm_access", {}).get("roles", []))
except Exception as e:
    print(f"Error: {e}")
