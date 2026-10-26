const WebSocket = require('ws');
const server = new WebSocket.Server({ port: process.env.PORT || 8080 });

let browserClient = null;
let tabletClient = null;

server.on('connection', (ws) => {
    ws.on('message', (message) => {
        const data = JSON.parse(message);

        if (data.type === 'register-browser') {
            browserClient = ws;
            if (tabletClient) tabletClient.send(JSON.stringify({ type: 'browser-online' }));
        } else if (data.type === 'register-tablet') {
            tabletClient = ws;
            if (browserClient) browserClient.send(JSON.stringify({ type: 'tablet-online' }));
        }

        if (data.type === 'offer' || data.type === 'candidate') {
            if (tabletClient) tabletClient.send(JSON.stringify(data));
        } else if (data.type === 'answer') {
            if (browserClient) browserClient.send(JSON.stringify(data));
        }
    });

    ws.on('close', () => {
        if (ws === browserClient) browserClient = null;
        if (ws === tabletClient) tabletClient = null;
    });
});

console.log("Private Switchboard Signaler running...");
