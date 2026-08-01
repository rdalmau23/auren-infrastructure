import urllib.request
import json
import psycopg2
import hmac
import hashlib

KC_URL = "http://localhost:8180"
REALM = "auren"
ENCRYPTION_KEY_RAW = "dev-encryption-key-change-in-prod"

hmac_base = "hmac:" + ENCRYPTION_KEY_RAW
hmac_key = hashlib.sha256(hmac_base.encode('utf-8')).digest()

def get_email_hash(email):
    input_str = email.lower().strip()
    h = hmac.new(hmac_key, input_str.encode('utf-8'), hashlib.sha256)
    return h.hexdigest()

# 1. Get Master Admin token
import ssl
ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

url = f"{KC_URL}/realms/master/protocol/openid-connect/token"
data = "client_id=admin-cli&username=admin&password=admin&grant_type=password".encode('utf-8')
req = urllib.request.Request(url, data=data)
with urllib.request.urlopen(req, context=ctx) as response:
    token = json.loads(response.read().decode())['access_token']

# 2. Fetch Users
req = urllib.request.Request(f"{KC_URL}/admin/realms/{REALM}/users")
req.add_header("Authorization", f"Bearer {token}")
with urllib.request.urlopen(req) as resp:
    users = json.loads(resp.read().decode())

# 3. Connect to DB
conn = psycopg2.connect("dbname=auren user=auren_user password=auren_dev_password host=localhost")
conn.autocommit = True
cur = conn.cursor()

# 4. Sync IDs
for user in users:
    kc_id = user["id"]
    email = user.get("email")
    if email:
        ehash = get_email_hash(email)
        print(f"Updating {email} -> {kc_id}")
        cur.execute("UPDATE auren.users SET keycloak_id = %s WHERE email_hash = %s", (kc_id, ehash))

print("Done")
