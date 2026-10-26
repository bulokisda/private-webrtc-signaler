const WebSocket = require('ws');
const server = new WebSocket.Server({ port: process.env.PORT || 8080 });

let browserClient = null;
let tabletClient = null;
let pendingOffer = null; // Stores the signal if the tablet is busy or booting

server.on('connection', (ws) => {
    ws.on('message', (message) => {
        const data = JSON.parse(message);
        
        if (data.type === 'register-browser') {
            browserClient = ws;
            console.log("Browser connected.");
            if (tabletClient && tabletClient.readyState === WebSocket.OPEN) {
                browserClient.send(JSON.stringify({ type: 'tablet-online' }));
            }
        } else if (data.type === 'register-tablet') {
            tabletClient = ws;
            console.log("Tablet connected and verified.");
            
            // If the browser sent an offer while the tablet was offline, forward it now
            if (pendingOffer && tabletClient.readyState === WebSocket.OPEN) {
                console.log("Flushing queued offer to tablet.");
                tabletClient.send(JSON.stringify(pendingOffer));
                pendingOffer = null;
            }
        }
        
        if (data.type === 'offer') {
            // FIXED: If the tablet sends the offer, forward it to the browser. Otherwise send it to the tablet.
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
                    pendingOffer = data; // Buffer the signal safely
                }
            }
        } else if (data.type === 'candidate') {
            // FIXED: Cleaned up bidirectional ICE routing logic using absolute client tracking structures
            if (ws === browserClient) {
                if (tabletClient && tabletClient.readyState === WebSocket.OPEN) {
                    tabletClient.send(JSON.stringify(data));
                }
            } else if (ws === tabletClient) {
                if (browserClient && browserClient.readyState === WebSocket.OPEN) {
                    browserClient.send(JSON.stringify(data));
                }
            }
        } else if (data.type === 'answer') {
            if (browserClient && browserClient.readyState === WebSocket.OPEN) {
                console.log("Routing answer payload back to browser.");
                browserClient.send(JSON.stringify(data));
            }
        }
    });

    ws.on('close', () => {
        if (ws === browserClient) {
            console.log("Browser disconnected.");
            browserClient = null;
        }
        if (ws === tabletClient) {
            console.log("Tablet disconnected.");
            tabletClient = null;
            pendingOffer = null;
        }
    });
});

console.log("State-queued bidirectional switchboard active.");
