import asyncio
import websockets
from fastapi import FastAPI, WebSocket
from fastapi.responses import HTMLResponse
import logging
from openai import OpenAI
import os

client = OpenAI(
    base_url=os.getenv("OPENAI_API_BASE"),
    api_key="EMPTY",
)
import re
from dotenv import load_dotenv

load_dotenv()

model = os.getenv("MODEL")

app = FastAPI()

def extract_json_from_string(s):
    logging.info(f"Extracting JSON from string: {s}")
    # Use a regular expression to find a JSON-like string
    matches = re.findall(r"\{[^{}]*\}", s)

    if matches:
        # Return the first match (assuming there's only one JSON object embedded)
        return matches[0]

    # Return the original string if no JSON object is found
    return s

html = """
<html>
    <head>
        <title>Chat</title>
    </head>
    <body>
        <h1>WebSocket Chat</h1>
        <form action="" onsubmit="sendMessage(event)">
            <input type="text" id="messageText" autocomplete="off"/>
            <button>Send</button>
        </form>
        <ul id='messages'>
        </ul>
        <script>
            var loc = window.location, new_uri;
            if (loc.protocol == "https:") {
                new_uri = "wss:";
            } else {
                new_uri = "ws:";
            }
            new_uri += "//" + loc.host + "/ws"
            //var ws = new WebSocket("ws://localhost:8000/ws");
            var ws = new WebSocket(new_uri);
            ws.onmessage = function(event) {
                var messages = document.getElementById('messages')
                var message = document.createElement('li')
                var content = document.createTextNode(event.data)
                message.appendChild(content)
                messages.appendChild(message)
            };
            function sendMessage(event) {
                var input = document.getElementById("messageText")
                ws.send(input.value)
                input.value = ''
                event.preventDefault()
            }
        </script>
    </body>
</html>
"""

@app.get("/")
async def get():
    return HTMLResponse(html)

@app.websocket("/ws/")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()
    while True:
        input = await websocket.receive_text()
        completion = client.chat.completions.create(
                    model=model,
                    messages=[
                        {
                            "role": "system",
                            "content": "You are a bot to help extract data and should give professional responses",
                        },
                        {"role": "user", "content": input},
                    ],
                )
        response = extract_json_from_string(completion.choices[0].message.content)
        await websocket.send_text(response)
