import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/peer_info.dart';
import 'storage_service.dart';

class DiscoveryService {
  static final DiscoveryService _instance = DiscoveryService._internal();
  factory DiscoveryService() => _instance;
  DiscoveryService._internal();

  RawDatagramSocket? _socket;
  Timer? _beaconTimer;
  Timer? _cleanupTimer;

  final Map<String, PeerInfo> _peers = {};
  final ValueNotifier<List<PeerInfo>> peersNotifier = ValueNotifier<List<PeerInfo>>([]);
  final ValueNotifier<String?> localIpNotifier = ValueNotifier<String?>(null);

  bool _isStarted = false;

  Future<void> start({
    required String myKey,
    required String myName,
    required String myOs,
  }) async {
    if (_isStarted) return;
    _isStarted = true;

    await _detectLocalIp();

    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        StorageService.udpDiscoveryPort,
        reuseAddress: true,
        reusePort: Platform.isMacOS,
      );
      _socket?.broadcastEnabled = true;

      _socket?.listen(
        (RawSocketEvent event) {
          if (event == RawSocketEvent.read) {
            final datagram = _socket?.receive();
            if (datagram != null) {
              _handleIncomingBeacon(datagram, myKey);
            }
          }
        },
        onError: (error) {
          debugPrint('Discovery UDP socket error: $error');
        },
      );

      // Beacon timer: send broadcast every 2 seconds
      _beaconTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        _broadcastBeacon(myKey: myKey, myName: myName, myOs: myOs);
      });

      // Peer cleanup timer: check every 3 seconds for peers silent > 8 seconds
      _cleanupTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        _cleanupStalePeers();
      });

      // Immediate first beacon
      _broadcastBeacon(myKey: myKey, myName: myName, myOs: myOs);
    } catch (e) {
      debugPrint('DiscoveryService socket bind failed (fallback to manual IP connect): $e');
    }
  }

  Future<String?> _detectLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );

      for (final interface in interfaces) {
        // Prefer Wi-Fi / en0 / Ethernet
        for (final addr in interface.addresses) {
          if (!addr.isLoopback && !addr.address.startsWith('169.254.')) {
            localIpNotifier.value = addr.address;
            return addr.address;
          }
        }
      }
    } catch (e) {
      debugPrint('Error detecting local IP: $e');
    }
    localIpNotifier.value ??= '127.0.0.1';
    return localIpNotifier.value;
  }

  void _broadcastBeacon({
    required String myKey,
    required String myName,
    required String myOs,
  }) {
    if (_socket == null) return;
    try {
      final localIp = localIpNotifier.value ?? '127.0.0.1';
      final payload = jsonEncode({
        'key': myKey,
        'name': myName,
        'ip': localIp,
        'port': StorageService.tcpControlPort,
        'os': myOs,
      });
      final bytes = utf8.encode(payload);

      // Send to global broadcast address
      try {
        _socket?.send(bytes, InternetAddress('255.255.255.255'), StorageService.udpDiscoveryPort);
      } catch (_) {}

      // Also send to subnet broadcast if detectable
      final parts = localIp.split('.');
      if (parts.length == 4) {
        final subnetBroadcast = '${parts[0]}.${parts[1]}.${parts[2]}.255';
        try {
          _socket?.send(bytes, InternetAddress(subnetBroadcast), StorageService.udpDiscoveryPort);
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('Error sending discovery beacon: $e');
    }
  }

  void _handleIncomingBeacon(Datagram datagram, String myKey) {
    try {
      final text = utf8.decode(datagram.data);
      final json = jsonDecode(text) as Map<String, dynamic>;
      final peerKey = json['key'] as String?;

      if (peerKey == null || peerKey == myKey) {
        // Ignore self
        return;
      }

      final senderIp = datagram.address.address;
      final peer = PeerInfo.fromJson(json, senderIp);

      _peers[peer.key] = peer;
      _notifyPeersUpdated();
    } catch (_) {}
  }

  void _cleanupStalePeers() {
    final now = DateTime.now();
    final initialCount = _peers.length;
    _peers.removeWhere((key, peer) => now.difference(peer.lastSeen).inSeconds > 8);
    if (_peers.length != initialCount) {
      _notifyPeersUpdated();
    }
  }

  void _notifyPeersUpdated() {
    peersNotifier.value = _peers.values.toList()
      ..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
  }

  /// Lookup a peer by their unique connection key
  PeerInfo? findPeerByKey(String key) {
    final normalized = key.trim().toUpperCase();
    for (final peer in _peers.values) {
      if (peer.key.toUpperCase() == normalized) return peer;
    }
    return null;
  }

  void stop() {
    _beaconTimer?.cancel();
    _cleanupTimer?.cancel();
    _socket?.close();
    _socket = null;
    _isStarted = false;
    _peers.clear();
    peersNotifier.value = [];
  }
}
