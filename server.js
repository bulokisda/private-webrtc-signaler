const WebSocket = require('ws');
const server = new WebSocket.Server({ port: process.env.PORT || 8080 });

let browserClient = null;
let tabletClient = null;

server.on('connection', (ws) => {
    ws.on('message', (message) => {
        const data = JSON.parse(message);
        
        if (data.type === 'register-browser') {
            browserClient = ws;
            console.log("Browser registered.");
            // SYNC: If the tablet is already waiting, tell the browser to initiate the offer immediately
            if (tabletClient && tabletClient.readyState === WebSocket.OPEN) {
                browserClient.send(JSON.stringify({ type: 'tablet-online' }));
            }
        } else if (data.type === 'register-tablet') {
            tabletClient = ws;
            console.log("Tablet registered.");
            // SYNC: If the browser is waiting, tell it the tablet is ready
            if (browserClient && browserClient.readyState === WebSocket.OPEN) {
                browserClient.send(JSON.stringify({ type: 'tablet-online' }));
            }
        }
        
        // Forward WebRTC signals directly between peers
        if (data.type === 'offer' || data.type === 'candidate') {
            if (tabletClient && tabletClient.readyState === WebSocket.OPEN) {
                tabletClient.send(JSON.stringify(data));
            }
        } else if (data.type === 'answer') {
            if (browserClient && browserClient.readyState === WebSocket.OPEN) {
                browserClient.send(JSON.stringify(data));
            }
        }
    });

    ws.on('close', () => {
        if (ws === browserClient) browserClient = null;
        if (ws === tabletClient) tabletClient = null;
    });
});

console.log("Private Switchboard Signaler running with sync blocks...");
