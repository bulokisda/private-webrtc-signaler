const WebSocket = require('ws');
const wss = new WebSocket.Server({ port: 8080 });

// Track active connections map (Store as id -> socket instance)
const clients = new Map();

console.log("Mesh Signaling Server active on port 8080...");

wss.on('connection', (ws) => {
    let clientId = null;

    // Node.js 'ws' package uses 'message' event with raw data parameters, NOT browser 'onmessage'
    ws.on('message', (message) => {
        try {
            const data = JSON.parse(message);

            switch (data.type) {
                case 'register-tablet':
                    // Map unique key matching the registration payload
                    clientId = data.id || 'tablet';
                    clients.set(clientId, ws);
                    console.log(`Tablet registered successfully as node: ${clientId}`);
                    break;

                case 'register-browser':
                    // Generate a distinct hash string matching multiple incoming participants
                    clientId = 'browser_user_' + Math.random().toString(36).substr(2, 5);
                    clients.set(clientId, ws);
                    console.log(`Browser registered successfully as node: ${clientId}`);
                    
                    // Reply to the browser and inform it of its assigned unique string hash
                    ws.send(JSON.stringify({ type: 'registered', id: clientId }));
                    break;

                case 'offer':
                case 'answer':
                case 'ice-candidate':
                    // Attach who sent it to the envelope payload automatically
                    data.senderId = clientId;
                    
                    // TARGETED ROUTING SYSTEM: Route directly to the intended destination node map
                    const targetId = data.targetId || 'tablet';
                    const targetSocket = clients.get(targetId);
                    
                    if (targetSocket && targetSocket.readyState === WebSocket.OPEN) {
                        targetSocket.send(JSON.stringify(data));
                    } else {
                        console.log(`Warning: Target node (${targetId}) not found or offline.`);
                    }
                    break;

                case 'ping':
                    ws.send(JSON.stringify({ type: 'pong' }));
                    break;

                case 'hangup':
                    if (data.targetId) {
                        const tSocket = clients.get(data.targetId);
                        if (tSocket) tSocket.send(JSON.stringify({ type: 'hangup', senderId: clientId }));
                    } else {
                        // Broadcast hangup to all sibling targets if no explicit ID parameter is declared
                        clients.forEach((socket, id) => {
                            if (id !== clientId) socket.send(JSON.stringify({ type: 'hangup', senderId: clientId }));
                        });
                    }
                    break;
            }
        } catch (e) {
            console.error("Error decoding signaling frame:", e);
        }
    });

    ws.on('close', () => {
        if (clientId) {
            clients.delete(clientId);
            console.log(`Node disconnected: ${clientId}`);
            
            // Broadcast connection dropout alert down to all surviving mesh elements
            clients.forEach((socket) => {
                if (socket.readyState === WebSocket.OPEN) {
                    socket.send(JSON.stringify({ type: 'hangup', senderId: clientId }));
                }
            });
        }
    });
});
