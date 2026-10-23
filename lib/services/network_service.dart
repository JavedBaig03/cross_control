import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/control_events.dart';
import 'native_input_service.dart';
import 'storage_service.dart';

typedef RequestApprovalHandler = Future<bool> Function(ConnectionRequest request);

class NetworkService {
  static final NetworkService _instance = NetworkService._internal();
  factory NetworkService() => _instance;
  NetworkService._internal();

  ServerSocket? _serverSocket;
  Socket? _activeSocket;
  StreamSubscription? _socketSubscription;

  // Real-time state notifiers
  final ValueNotifier<int> latencyMsNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> eventsSentNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> eventsReceivedNotifier = ValueNotifier<int>(0);

  // Callbacks
  RequestApprovalHandler? onRequestApproval;
  void Function(ControlEvent event)? onEventReceived;
  void Function(String reason)? onDisconnected;

  Timer? _pingTimer;
  int _lastPingSentTimestamp = 0;

  bool get isConnected => _activeSocket != null;

  /// Start TCP Server on the laptop to listen for incoming connections
  Future<void> startServer({
    required RequestApprovalHandler requestApprovalHandler,
    required void Function(ControlEvent event) eventHandler,
    required void Function(String reason) disconnectHandler,
  }) async {
    onRequestApproval = requestApprovalHandler;
    onEventReceived = eventHandler;
    onDisconnected = disconnectHandler;

    if (_serverSocket != null) return;

    try {
      _serverSocket = await ServerSocket.bind(
        InternetAddress.anyIPv4,
        StorageService.tcpControlPort,
        shared: true,
      );

      _serverSocket?.listen(_handleIncomingClient);
      debugPrint('TCP Server listening on port ${StorageService.tcpControlPort}');
    } catch (e) {
      debugPrint('Error starting TCP Server: $e');
    }
  }

  /// Handle an incoming client on the server (Receiver side)
  void _handleIncomingClient(Socket client) async {
    // If already in an active session, decline new one
    if (_activeSocket != null) {
      final reject = ConnectionResponse(
        accepted: false,
        reason: 'Device is currently busy in another control session',
      );
      client.writeln(jsonEncode(reject.toMap()));
      await client.flush();
      await client.close();
      return;
    }

    try {
      client.setOption(SocketOption.tcpNoDelay, true);
    } catch (_) {}

    _activeSocket = client;
    eventsReceivedNotifier.value = 0;
    eventsSentNotifier.value = 0;
    bool isHandshakeApproved = false;

    // Single stream listener for the entire lifetime of this socket connection
    _socketSubscription = client
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) async {
      if (line.trim().isEmpty) return;

      if (!isHandshakeApproved) {
        try {
          final data = jsonDecode(line) as Map<String, dynamic>;
          final type = data['type'] as String?;

          if (type == 'connect_request') {
            final request = ConnectionRequest.fromMap(data);

            // Ask receiving user for approval
            final bool accepted = onRequestApproval != null
                ? await onRequestApproval!(request)
                : false;

            if (accepted) {
              isHandshakeApproved = true;
              final screenSize = await NativeInputService().getScreenSize();
              final response = ConnectionResponse(
                accepted: true,
                screenWidth: screenSize.width,
                screenHeight: screenSize.height,
              );

              client.writeln(jsonEncode(response.toMap()));
              await client.flush();
            } else {
              final response = ConnectionResponse(
                accepted: false,
                reason: 'Connection request was declined by the user',
              );
              client.writeln(jsonEncode(response.toMap()));
              await client.flush();
              disconnect(reason: 'Connection request declined');
            }
          }
        } catch (e) {
          debugPrint('Handshake error on server: $e');
          disconnect(reason: 'Handshake parse error: $e');
        }
        return;
      }

      // Handshake is approved: stream incoming ControlEvents
      try {
        final event = ControlEvent.deserialize(line);
        if (event == null) return;

        eventsReceivedNotifier.value++;

        if (event is PingEvent) {
          // Respond with Pong immediately for RTT measurement
          final pong = PongEvent(timestamp: event.timestamp);
          sendEvent(pong);
          return;
        }

        if (event is DisconnectEvent) {
          disconnect(reason: event.reason ?? 'Remote user disconnected');
          return;
        }

        onEventReceived?.call(event);
      } catch (e) {
        debugPrint('Error parsing control event: $e');
      }
    }, onDone: () {
      disconnect(reason: 'Connection closed by peer');
    }, onError: (err) {
      disconnect(reason: 'Connection error: $err');
    });
  }

  /// Connect to a remote laptop (Initiator / Controller side)
  Future<ConnectionResponse> connectToPeer({
    required String host,
    required int port,
    required String myKey,
    required String myName,
    required String myOs,
    required void Function(ControlEvent event) eventHandler,
    required void Function(String reason) disconnectHandler,
  }) async {
    onEventReceived = eventHandler;
    onDisconnected = disconnectHandler;

    final completer = Completer<ConnectionResponse>();

    try {
      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 8),
      );

      try {
        socket.setOption(SocketOption.tcpNoDelay, true);
      } catch (_) {}

      _activeSocket = socket;
      eventsReceivedNotifier.value = 0;
      eventsSentNotifier.value = 0;
      bool isHandshakeComplete = false;

      // Single stream listener for the entire lifetime of this socket connection
      _socketSubscription = socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (line.trim().isEmpty) return;

        if (!isHandshakeComplete) {
          try {
            final data = jsonDecode(line) as Map<String, dynamic>;
            final type = data['type'] as String?;

            if (type == 'connect_response') {
              final response = ConnectionResponse.fromMap(data);

              if (response.accepted) {
                isHandshakeComplete = true;
                _startPingTimer();
                if (!completer.isCompleted) completer.complete(response);
              } else {
                if (!completer.isCompleted) completer.complete(response);
                disconnect(reason: response.reason ?? 'Connection declined by remote laptop');
              }
            } else {
              if (!completer.isCompleted) {
                completer.complete(ConnectionResponse(
                  accepted: false,
                  reason: 'Unexpected response during handshake',
                ));
              }
              disconnect(reason: 'Unexpected handshake response');
            }
          } catch (e) {
            if (!completer.isCompleted) {
              completer.complete(ConnectionResponse(
                accepted: false,
                reason: 'Malformed handshake response: $e',
              ));
            }
            disconnect(reason: 'Malformed handshake response');
          }
          return;
        }

        // Handshake already approved: stream incoming ControlEvents
        try {
          final event = ControlEvent.deserialize(line);
          if (event == null) return;

          eventsReceivedNotifier.value++;

          if (event is PongEvent) {
            final now = DateTime.now().millisecondsSinceEpoch;
            final rtt = now - event.timestamp;
            latencyMsNotifier.value = rtt.clamp(0, 999);
            return;
          }

          if (event is DisconnectEvent) {
            disconnect(reason: event.reason ?? 'Remote user disconnected');
            return;
          }

          onEventReceived?.call(event);
        } catch (e) {
          debugPrint('Error parsing incoming event: $e');
        }
      }, onDone: () {
        disconnect(reason: 'Connection closed by remote system');
      }, onError: (err) {
        if (!completer.isCompleted) {
          completer.complete(ConnectionResponse(
            accepted: false,
            reason: 'Connection error: $err',
          ));
        }
        disconnect(reason: 'Socket error: $err');
      });

      // Send connection request
      final request = ConnectionRequest(
        fromKey: myKey,
        deviceName: myName,
        platform: myOs,
        ip: host,
      );

      socket.writeln(jsonEncode(request.toMap()));
      await socket.flush();
    } catch (e) {
      if (!completer.isCompleted) {
        completer.complete(ConnectionResponse(
          accepted: false,
          reason: 'Could not connect to host ($e). Ensure both laptops are on the same local Wi-Fi.',
        ));
      }
    }

    return completer.future;
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      _sendPing();
    });
    _sendPing();
  }

  void _sendPing() {
    if (_activeSocket == null) return;
    _lastPingSentTimestamp = DateTime.now().millisecondsSinceEpoch;
    sendEvent(PingEvent(timestamp: _lastPingSentTimestamp));
  }

  /// Send a control event over the active TCP stream
  void sendEvent(ControlEvent event) {
    if (_activeSocket == null) return;
    try {
      _activeSocket?.writeln(event.serialize());
      eventsSentNotifier.value++;
    } catch (e) {
      debugPrint('Error sending event: $e');
    }
  }

  /// Disconnect active session
  void disconnect({String reason = 'Disconnected'}) {
    _pingTimer?.cancel();
    _pingTimer = null;

    if (_activeSocket != null) {
      try {
        _activeSocket?.writeln(DisconnectEvent(reason: reason).serialize());
        _activeSocket?.flush();
      } catch (_) {}

      _socketSubscription?.cancel();
      _socketSubscription = null;
      _activeSocket?.destroy();
      _activeSocket = null;

      onDisconnected?.call(reason);
    }
  }

  /// Stop TCP server and close all sockets
  void stopServer() {
    disconnect();
    _serverSocket?.close();
    _serverSocket = null;
  }
}
