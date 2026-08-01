import urllib.request
import json
import ssl

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE
BASE_URL = "http://localhost:8180"

url = f"{BASE_URL}/realms/master/protocol/openid-connect/token"
data = "client_id=admin-cli&username=admin&password=admin&grant_type=password".encode('utf-8')
req = urllib.request.Request(url, data=data)
with urllib.request.urlopen(req, context=ctx) as response:
    token = json.loads(response.read().decode())['access_token']

url_clients = f"{BASE_URL}/admin/realms/auren/clients"
req_clients = urllib.request.Request(url_clients)
req_clients.add_header("Authorization", f"Bearer {token}")
with urllib.request.urlopen(req_clients, context=ctx) as response:
    clients = json.loads(response.read().decode())
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
