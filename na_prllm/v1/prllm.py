import requests
import json
import asyncio
import websockets

# For now - get session token every request
def session_token(SNOWFLAKE_HOST, SNOWFLAKE_ACCOUNT, SNOWFLAKE_USER, SNOWFLAKE_PASSWORD):
    data = {
        "data": {
            "ACCOUNT_NAME": SNOWFLAKE_ACCOUNT,
            "LOGIN_NAME": SNOWFLAKE_USER,
            "PASSWORD" : SNOWFLAKE_PASSWORD
        }
    }
    headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/snowflake'
    }
    url = f"{SNOWFLAKE_HOST}/session/v1/login-request"
    resp = requests.post(url, data=json.dumps(data), headers=headers)

    master_token = resp.json()['data']['masterToken']
    old_token = resp.json()['data']['token']

    data = {
        "requestType": "ISSUE",
        "oldSessionToken": old_token
    }
    headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': f'Snowflake Token="{master_token}"'
    }
    url = f"{SNOWFLAKE_HOST}/session/token-request"
    resp = requests.post(url, data=json.dumps(data), headers=headers)
    return resp.json()['data']['sessionToken']

async def ws_prllm(prompt, uri, headers):
    async with websockets.connect(uri, extra_headers=headers) as websocket:
        await websocket.send(prompt)
        response = await websocket.recv()
        return response

def prllm(prompt, host, account, user, password, api_url):
    token = session_token(host, account, user, password)
    url = f"{api_url}/" ## for now
    headers = {
        'Authorization': f'Snowflake Token="{token}"'
    }
    return asyncio.run(ws_prllm(prompt, url, headers))
