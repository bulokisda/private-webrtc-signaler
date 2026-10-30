import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class VideoCallScreen extends StatefulWidget {
  const VideoCallScreen({super.key});

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();

  final Map<String, RTCVideoRenderer> _remoteRenderers = {};
  final Map<String, RTCPeerConnection> _peerConnections = {};

  MediaStream? _localStream;
  StreamSubscription? _serviceSubscription;
  bool _isInitialized = false;
  String? _myNodeId;

  final Map<String, dynamic> _rtcConfig = {
    'iceServers': [
      {
        'urls': [
          'stun:stun.l.google.com:19302',
          'stun:stun1.l.google.com:19302',
          'stun:stun2.l.google.com:19302',
        ]
      },
    ],
    'sdpSemantics': 'unified-plan',
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInitialized) {
      final remoteSdp = ModalRoute.of(context)!.settings.arguments;
      _bootstrapWebRTC(remoteSdp);
      _isInitialized = true;
    }
  }

  void _bootstrapWebRTC(dynamic args) async {
    await _localRenderer.initialize();
    _bindMeshCallSignaling();
    await _initializeLocalHardware();

    if (args != null && args is Map) {
      String actualSenderId = args['senderId'] ?? "browser_node";
      dynamic remoteSdp = args['sdp'];

      await _handleIncomingMeshOffer(actualSenderId, remoteSdp);
    }
  }

  Future<void> _initializeLocalHardware() async {
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': {
        'mandatory': {'minWidth': '640', 'minHeight': '480'},
        'facingMode': 'user',
      },
    });
    if (mounted) {
      setState(() => _localRenderer.srcObject = _localStream);
    }
  }

  void _debugActiveConnections() async {
    debugPrint("==== WEBRTC DIAGNOSTIC MATRIX PROFILE ====");
    _peerConnections.forEach((peerId, pc) async {
      var stats = await pc.getStats();
      var state = await pc.getConnectionState();
      var sigState = await pc.getSignalingState();
      debugPrint("Peer [ $peerId ] Connection State: $state");
      debugPrint("Peer [ $peerId ] Signalling State: $sigState");

      for (var stat in stats) {
        if (stat.type == 'inbound-rtp' && stat.id.contains('video')) {
          debugPrint("--> Inbound Video Bytes Received: ${stat.values['bytesReceived']}");
          debugPrint("--> Inbound Video Frames Decoded: ${stat.values['framesDecoded']}");
        }
      }
    });
  }

  void _bindMeshCallSignaling() {
    _serviceSubscription = FlutterBackgroundService()
        .on('onSignalReceived')
        .listen((event) async {
          if (event == null || event['data'] == null) return;
          var data = json.decode(event['data']);

          String? peerId = data['senderId'];
          
          switch (data['type']) {
            case 'registered':
              _myNodeId = data['id'];
              debugPrint("Tablet registered connection pool mesh ID: $_myNodeId");
              break;

            case 'mesh-peer-list':
              if (data['peers'] != null) {
                var peersList = data['peers'] as List;
                for (var peer in peersList) {
                  String remoteId = peer['id'];
                  if (remoteId != _myNodeId && !_peerConnections.containsKey(remoteId)) {
                    debugPrint("Auto-initiating dynamic mesh connection to node: $remoteId");
                    await _createOutboundMeshOffer(remoteId);
                  }
                }
              }
              break;

            case 'offer':
              if (peerId == null) return;
              await _handleIncomingMeshOffer(peerId, data['sdp']);
              break;

            case 'answer':
              if (peerId == null) return;
              await _handleIncomingMeshAnswer(peerId, data['sdp']);
              break;

            case 'ice-candidate':
              if (peerId == null) return;
              if (data['candidate'] != null && _peerConnections.containsKey(peerId)) {
                var candidateMap = data['candidate'];
                await _peerConnections[peerId]!.addCandidate(
                  RTCIceCandidate(
                    candidateMap['candidate'],
                    candidateMap['sdpMid'],
                    candidateMap['sdpMLineIndex'],
                  ),
                );
              }
              break;

            case 'hangup':
              if (peerId == null) return;
              _removePeer(peerId);
              break;
          }
        });
  }

  Future<RTCPeerConnection> _createNewPeerConnectionNode(String peerId) async {
    final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();
    await remoteRenderer.initialize();

    if (mounted) {
      setState(() {
        _remoteRenderers[peerId] = remoteRenderer;
      });
    }

    RTCPeerConnection pc = await createPeerConnection(_rtcConfig, const {});
    
    if (_localStream != null) {
      for (var track in _localStream!.getTracks()) {
        await pc.addTrack(track, _localStream!);
        debugPrint("Attached track to peer pipeline: $peerId");
      }
    }

    pc.onTrack = (RTCTrackEvent event) {
      debugPrint("Remote track received from peer: $peerId");
      if (event.track.kind == 'video' && event.streams.isNotEmpty) {
        if (mounted) {
          setState(() {
            _remoteRenderers[peerId]?.srcObject = event.streams.first;
          });
        }
      }
      _debugActiveConnections();
    };

    pc.onIceCandidate = (RTCIceCandidate candidate) {
      FlutterBackgroundService().invoke('sendSignal', {
        'payload': json.encode({
          'type': 'ice-candidate',
          'targetId': peerId,
          'candidate': {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          },
        }),
      });
    };

    _peerConnections[peerId] = pc;
    return pc;
  }

  Future<void> _createOutboundMeshOffer(String peerId) async {
    if (_peerConnections.containsKey(peerId)) return;
    
    RTCPeerConnection pc = await _createNewPeerConnectionNode(peerId);
    
    RTCSessionDescription offer = await pc.createOffer({
      'mandatory': {'OfferToReceiveAudio': true, 'OfferToReceiveVideo': true},
    });
    await pc.setLocalDescription(offer);

    FlutterBackgroundService().invoke('sendSignal', {
      'payload': json.encode({
        'type': 'offer',
        'targetId': peerId,
        'sdp': offer.sdp,
      }),
    });
  }

  Future<void> _handleIncomingMeshOffer(String peerId, dynamic remoteSdp) async {
    if (_peerConnections.containsKey(peerId)) return;

    RTCPeerConnection pc = await _createNewPeerConnectionNode(peerId);
    
    String sdpString = (remoteSdp is Map && remoteSdp.containsKey('sdp')) ? remoteSdp['sdp'] : remoteSdp;
    await pc.setRemoteDescription(RTCSessionDescription(sdpString, 'offer'));

    RTCSessionDescription answer = await pc.createAnswer({
      'mandatory': {'OfferToReceiveAudio': true, 'OfferToReceiveVideo': true},
    });
    await pc.setLocalDescription(answer);

    FlutterBackgroundService().invoke('sendSignal', {
      'payload': json.encode({
        'type': 'answer',
        'targetId': peerId,
        'sdp': answer.sdp,
      }),
    });
  }

  Future<void> _handleIncomingMeshAnswer(String peerId, dynamic remoteSdp) async {
    if (_peerConnections.containsKey(peerId)) {
      try {
        String sdpString = "";
        if (remoteSdp is Map && remoteSdp.containsKey('sdp')) {
          sdpString = remoteSdp['sdp'];
        } else if (remoteSdp is String) {
          sdpString = remoteSdp;
        } else {
          sdpString = remoteSdp.toString();
        }

        await _peerConnections[peerId]!.setRemoteDescription(
          RTCSessionDescription(sdpString, 'answer'),
        );
        debugPrint("Remote description applied to peer connection: $peerId");
      } catch (e) {
        debugPrint("Failed applying remote answer payload on node $peerId: $e");
      }
    }
  }

  void _removePeer(String peerId) async {
    if (_peerConnections.containsKey(peerId)) {
      final pc = _peerConnections.remove(peerId);
      try {
        await pc?.close();
        await pc?.dispose();
      } catch (e) {
        debugPrint("Exception during connection closure: $e");
      }
    }
    
    if (_remoteRenderers.containsKey(peerId)) {
      final renderer = _remoteRenderers.remove(peerId);
      if (mounted) {
        setState(() {});
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          renderer?.dispose();
        } catch (e) {
          debugPrint("Renderer container resource extraction skip: $e");
        }
      });
    }

    if (_peerConnections.isEmpty) {
      _closeAllCallsAndExit();
    }
  }

  void _closeAllCallsAndExit() async {
    _localStream?.getTracks().forEach((track) => track.stop());
    await _localStream?.dispose();
    _localStream = null;

    for (var pc in _peerConnections.values) {
      try {
        await pc.close();
        await pc.dispose();
      } catch (e) {
        debugPrint("Connection shutdown cleanup skip: $e");
      }
    }
    _peerConnections.clear();

    for (var renderer in _remoteRenderers.values) {
      try {
        renderer.dispose();
      } catch (e) {
        debugPrint("Renderer container resource cleanup skip: $e");
      }
    }
    _remoteRenderers.clear();

    if (mounted) {
      Navigator.pushReplacementNamed(context, '/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> gridItems = [];

    gridItems.add(
      _buildVideoFrame(
        label: "You (Local)",
        renderer: _localRenderer,
        isLocal: true,
      ),
    );

    _remoteRenderers.forEach((peerId, renderer) {
      gridItems.add(
        _buildVideoFrame(
          label: "User: $peerId",
          renderer: renderer,
          isLocal: false,
        ),
      );
    });

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(6.0),
              child: GridView.builder(
                itemCount: gridItems.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: gridItems.length <= 2 ? 1 : 2,
                  mainAxisSpacing: 6.0,
                  crossAxisSpacing: 6.0,
                  childAspectRatio: gridItems.length == 1 ? 0.75 : 1.0,
                ),
                itemBuilder: (context, index) => gridItems[index],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 24,
              child: Center(
                child: FloatingActionButton(
                  backgroundColor: Colors.red,
                  onPressed: () {
                    FlutterBackgroundService().invoke('sendSignal', {
                      'payload': json.encode({'type': 'hangup'}),
                    });
                    _closeAllCallsAndExit();
                  },
                  child: const Icon(Icons.call_end, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoFrame({
    required String label,
    required RTCVideoRenderer renderer,
    required bool isLocal,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(child: RTCVideoView(renderer, mirror: isLocal)),
          Positioned(
            left: 12,
            top: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                label,
                style: const TextStyle(fontSize: 12, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _serviceSubscription?.cancel();
    _localRenderer.dispose();
    _remoteRenderers.forEach((key, renderer) => renderer.dispose());
    super.dispose();
  }
}
