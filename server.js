const WebSocket = require('ws');
const server = new WebSocket.Server({ port: process.env.PORT || 8080 });

let browserClient = null;
let tabletClient = null;
let pendingOffer = null;

// New helper to broadcast live availability changes to both clients
function broadcastPresence() {
    const isBrowserOpen = browserClient && browserClient.readyState === WebSocket.OPEN;
    const isTabletOpen = tabletClient && tabletClient.readyState === WebSocket.OPEN;

    if (isBrowserOpen) {
        browserClient.send(JSON.stringify({ 
            type: 'partner-status', 
            online: isTabletOpen 
        }));
    }
    if (isTabletOpen) {
        tabletClient.send(JSON.stringify({ 
            type: 'partner-status', 
            online: isBrowserOpen 
        }));
    }
}

server.on('connection', (ws) => {
    ws.on('message', (message) => {
        const data = JSON.parse(message);
        
        if (data.type === 'register-browser') {
            browserClient = ws;
            console.log("Browser connected.");
            broadcastPresence(); // Trigger presence check
        } else if (data.type === 'register-tablet') {
            tabletClient = ws;
            console.log("Tablet connected and verified.");
            broadcastPresence(); // Trigger presence check
            
            if (pendingOffer && tabletClient.readyState === WebSocket.OPEN) {
                console.log("Flushing queued offer to tablet.");
                tabletClient.send(JSON.stringify(pendingOffer));
                pendingOffer = null;
            }
        }
        
        if (data.type === 'offer') {
            if (ws === tabletClient) {
                if (browserClient && browserClient.readyState === WebSocket.OPEN) {
                    console.log("Routing tablet offer to browser.");
                    browserClient.send(JSON.stringify(data));
                } else {
                    console.log("Tablet tried to call, but browser is offline.");
                }
            } else {
                if (tabletClient && tabletClient.readyState === WebSocket.OPEN) {
                    console.log("Routing browser offer to tablet.");
                    tabletClient.send(JSON.stringify(data));
                } else {
                    console.log("Tablet not ready. Queueing offer payload.");
                    pendingOffer = data;
                }
            }
        } else if (data.type === 'candidate') {
            if (ws === browserClient && tabletClient && tabletClient.readyState === WebSocket.OPEN) {
                tabletClient.send(JSON.stringify(data));
            } else if (ws === tabletClient && browserClient && browserClient.readyState === WebSocket.OPEN) {
                browserClient.send(JSON.stringify(data));
            }
        } else if (data.type === 'answer') {
            if (ws === tabletClient && browserClient && browserClient.readyState === WebSocket.OPEN) {
                browserClient.send(JSON.stringify(data));
            } else if (ws === browserClient && tabletClient && tabletClient.readyState === WebSocket.OPEN) {
                tabletClient.send(JSON.stringify(data));
            }
        } else if (data.type === 'hangup') {
            if (ws === tabletClient && browserClient && browserClient.readyState === WebSocket.OPEN) {
                browserClient.send(JSON.stringify({ type: 'hangup' }));
            } else if (ws === browserClient && tabletClient && tabletClient.readyState === WebSocket.OPEN) {
                tabletClient.send(JSON.stringify({ type: 'hangup' }));
            }
        }
    });

    ws.on('close', () => {
        if (ws === browserClient) browserClient = null;
        if (ws === tabletClient) {
            tabletClient = null;
            pendingOffer = null;
        }
        broadcastPresence(); // Trigger updates when a client drops off natively
    });
});

console.log("State-queued bidirectional switchboard active.");
