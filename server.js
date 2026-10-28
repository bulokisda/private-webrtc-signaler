const WebSocket = require('ws');
const wss = new WebSocket.Server({ port: 8080 });

// Track active connections
const clients = new Map(); // Store as id -> socket

wss.on('connection', (ws) => {
    let clientId = null;

    ws.onmessage = async (event) => {
        const data = JSON.parse(event.data);
        
        switch (data.type) {
            case 'registered':
                myId = data.id;
                document.getElementById('callBtn').disabled = false;
                console.log("Registered on server as: " + myId);
                break;
    
            case 'answer':
                // FIXED: Explicitly map the incoming object keys rather than passing the container object!
                await peerConnection.setRemoteDescription(new RTCSessionDescription({
                    type: 'answer',
                    sdp: data.sdp
                }));
                console.log("Remote SDP answer applied successfully.");
                break;
    
            case 'ice-candidate':
                // FIXED: Safeguard candidate ingestion by ensuring our remote description has landed first
                if (peerConnection && peerConnection.remoteDescription && data.candidate) {
                    // If your signaling data object contains a sub-candidate dictionary layer:
                    const candidateData = data.candidate.candidate ? data.candidate : {
                        candidate: data.candidate.candidate || data.candidate,
                        sdpMid: data.candidate.sdpMid,
                        sdpMLineIndex: data.candidate.sdpMLineIndex
                    };
                    await peerConnection.addIceCandidate(new RTCIceCandidate(candidateData));
                }
                break;
    
            case 'hangup':
                handleRemoteHangup();
                break;
        }
    };


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
