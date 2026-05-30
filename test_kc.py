import urllib.request
import json
import ssl

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

try:
    url = "http://localhost:8180/realms/master/protocol/openid-connect/token"
    data = "client_id=admin-cli&username=admin&password=admin&grant_type=password".encode('utf-8')
    req = urllib.request.Request(url, data=data)
    with urllib.request.urlopen(req, context=ctx) as response:
        token = json.loads(response.read().decode())['access_token']
        print("Successfully obtained admin token")
except Exception as e:
    print(f"Error: {e}")
