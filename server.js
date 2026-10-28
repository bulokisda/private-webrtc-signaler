const WebSocket = require('ws');
const wss = new WebSocket.Server({ port: 8080 });

// Track active connections
const clients = new Map(); // Store as id -> socket

wss.on('connection', (ws) => {
    let clientId = null;

    ws.on('message', (message) => {
        const data = JSON.parse(message);

        switch (data.type) {
            case 'register-tablet':
                clientId = 'tablet';
                clients.set(clientId, ws);
                console.log('Tablet registered');
                break;

            case 'register-browser':
                clientId = 'browser_user_' + Math.random().toString(36).substr(2, 5);
                clients.set(clientId, ws);
                console.log(`Browser registered: ${clientId}`);
                // Tell the browser its own ID
                ws.send(JSON.stringify({ type: 'registered', id: clientId }));
                break;

            case 'offer':
            case 'answer':
            case 'ice-candidate':
                // Attach who sent it
                data.senderId = clientId;
                
                // Route directly to the intended recipient
                const targetSocket = clients.get(data.targetId || 'tablet');
                if (targetSocket && targetSocket.readyState === WebSocket.OPEN) {
                    targetSocket.send(JSON.stringify(data));
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
                    // Broadcast hangup if no specific target
                    clients.forEach((socket, id) => {
                        if (id !== clientId) socket.send(JSON.stringify({ type: 'hangup', senderId: clientId }));
                    });
                }
                break;
        }
    });

    ws.on('close', () => {
        if (clientId) {
            clients.delete(clientId);
            console.log(`${clientId} disconnected`);
            // Notify other peers
            clients.forEach((socket) => {
                socket.send(JSON.stringify({ type: 'hangup', senderId: clientId }));
            });
        }
    });
});
