const WebSocket = require('ws');
const wss = new WebSocket.Server({ port: 8080 });

// Track active connections map (Store as id -> { socket: ws, type: string })
const clients = new Map();

console.log("Mesh Signaling Server active on port 8080...");

// Helper helper to broadcast room state to all clients
function broadcastPeerList() {
    const peerList = Array.from(clients.entries()).map(([id, info]) => ({
        id: id,
        type: info.type
    }));
    
    clients.forEach((info) => {
        if (info.socket.readyState === WebSocket.OPEN) {
            info.socket.send(JSON.stringify({
                type: 'mesh-peer-list',
                peers: peerList
            }));
        }
    });
}

wss.on('connection', (ws) => {
    let clientId = null;

    ws.on('message', (message) => {
        try {
            const data = JSON.parse(message);

            switch (data.type) {
                case 'register-tablet':
                    // Prevent collisions by ensuring unique tablet IDs if scaling
                    clientId = data.id || 'tablet_node_' + Math.random().toString(36).substr(2, 5);
                    clients.set(clientId, { socket: ws, type: 'tablet' });
                    console.log(`Tablet registered successfully as node: ${clientId}`);
                    
                    // Acknowledge registration down to the tablet isolate
                    ws.send(JSON.stringify({ type: 'registered', id: clientId }));
                    
                    // Trigger dynamic mesh discovery update
                    broadcastPeerList();
                    break;

                case 'register-browser':
                    clientId = 'browser_node_' + Math.random().toString(36).substr(2, 5);
                    clients.set(clientId, { socket: ws, type: 'browser' });
                    console.log(`Browser registered successfully as node: ${clientId}`);
                    
                    // Reply to the browser with its assigned identity
                    ws.send(JSON.stringify({ type: 'registered', id: clientId }));
                    
                    // Trigger dynamic mesh discovery update
                    broadcastPeerList();
                    break;

                case 'offer':
                case 'answer':
                case 'ice-candidate':
                    data.senderId = clientId;
                    
                    // STRICT ROUTING: Require explicit targets. No more blind tablet fallbacks.
                    const targetId = data.targetId;
                    if (!targetId) {
                        console.log(`Warning: Dropped ${data.type} frame due to missing targetId from ${clientId}`);
                        break;
                    }

                    const targetClient = clients.get(targetId);
                    if (targetClient && targetClient.socket.readyState === WebSocket.OPEN) {
                        targetClient.socket.send(JSON.stringify(data));
                    } else {
                        console.log(`Warning: Target node (${targetId}) is unreachable or offline.`);
                    }
                    break;

                case 'ping':
                    ws.send(JSON.stringify({ type: 'pong' }));
                    break;

                case 'hangup':
                    if (data.targetId) {
                        const target = clients.get(data.targetId);
                        if (target && target.socket.readyState === WebSocket.OPEN) {
                            target.socket.send(JSON.stringify({ type: 'hangup', senderId: clientId }));
                        }
                    } else {
                        clients.forEach((info, id) => {
                            if (id !== clientId && info.socket.readyState === WebSocket.OPEN) {
                                info.socket.send(JSON.stringify({ type: 'hangup', senderId: clientId }));
                            }
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
            
            // Immediately inform remaining mesh nodes to tear down specific WebRTC pipelines
            clients.forEach((info) => {
                if (info.socket.readyState === WebSocket.OPEN) {
                    info.socket.send(JSON.stringify({ type: 'hangup', senderId: clientId }));
                }
            });

            // Refresh room state across remaining clients
            broadcastPeerList();
        }
    });
});
