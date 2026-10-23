import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/control_events.dart';
import 'native_input_service.dart';
import 'storage_service.dart';

typedef RequestApprovalHandler = Future<bool> Function(ConnectionRequest request);

enum NetworkConnectionStatus {
  idle,
  connecting,
  awaitingApproval,
  connected,
  remoteControlReady,
  failed,
}

class NetworkService {
  static final NetworkService _instance = NetworkService._internal();
  factory NetworkService() => _instance;
  NetworkService._internal();

  ServerSocket? _serverSocket;
  Socket? _activeSocket;
  StreamSubscription? _socketSubscription;
  bool _isClientMode = false;

  // Real-time state notifiers
  final ValueNotifier<int> latencyMsNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> eventsSentNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> eventsReceivedNotifier = ValueNotifier<int>(0);
  final ValueNotifier<NetworkConnectionStatus> statusNotifier =
      ValueNotifier<NetworkConnectionStatus>(NetworkConnectionStatus.idle);

  // Receiver-side handlers (Server)
  RequestApprovalHandler? onRequestApproval;
  void Function(ControlEvent event)? _serverEventHandler;
  void Function(String reason)? _serverDisconnectHandler;

  // Controller-side handlers (Client)
  void Function(ControlEvent event)? _clientEventHandler;
  void Function(String reason)? _clientDisconnectHandler;

  // Pipeline readiness completer for Controller side
  Completer<bool>? _readyAckCompleter;

  Timer? _pingTimer;
  int _lastPingSentTimestamp = 0;
  int _sentEventsCount = 0;
  int _lastSentNotifierUpdate = 0;
  int _receivedEventsCount = 0;
  int _lastReceivedNotifierUpdate = 0;

  bool get isConnected => _activeSocket != null;

  /// Start TCP Server on the laptop to listen for incoming connections
  Future<void> startServer({
    required RequestApprovalHandler requestApprovalHandler,
    required void Function(ControlEvent event) eventHandler,
    required void Function(String reason) disconnectHandler,
  }) async {
    onRequestApproval = requestApprovalHandler;
    _serverEventHandler = eventHandler;
    _serverDisconnectHandler = disconnectHandler;

    await _ensureServerRunning();
  }

  Future<void> _ensureServerRunning() async {
    if (_serverSocket != null) return;

    try {
      _serverSocket = await ServerSocket.bind(
        InternetAddress.anyIPv4,
        StorageService.tcpControlPort,
        shared: true,
      );

      _serverSocket?.listen(
        _handleIncomingClient,
        onError: (err) {
          debugPrint('TCP Server error: $err. Attempting auto-recovery...');
          _serverSocket?.close();
          _serverSocket = null;
          Future.delayed(const Duration(seconds: 1), _ensureServerRunning);
        },
        onDone: () {
          _serverSocket = null;
        },
      );
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
      try {
        client.writeln(jsonEncode(reject.toMap()));
        await client.flush();
        await client.close();
      } catch (_) {}
      return;
    }

    try {
      client.setOption(SocketOption.tcpNoDelay, true);
    } catch (_) {}

    _activeSocket = client;
    _isClientMode = false;
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
            statusNotifier.value = NetworkConnectionStatus.awaitingApproval;

            // Check accessibility permissions on macOS prior to approval
            if (Platform.isMacOS) {
              final hasPerm = await NativeInputService().checkAccessibilityPermission();
              if (!hasPerm) {
                final response = ConnectionResponse(
                  accepted: false,
                  reason: 'Accessibility permission is not granted on this Mac. Please grant permission in System Settings > Privacy & Security > Accessibility.',
                );
                client.writeln(jsonEncode(response.toMap()));
                await client.flush();
                disconnect(reason: 'Accessibility permission required');
                return;
              }
            }

            // Ask receiving user for approval
            final bool accepted = onRequestApproval != null
                ? await onRequestApproval!(request)
                : false;

            if (accepted) {
              isHandshakeApproved = true;
              statusNotifier.value = NetworkConnectionStatus.connected;
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

        _receivedEventsCount++;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - _lastReceivedNotifierUpdate > 250) {
          _lastReceivedNotifierUpdate = now;
          eventsReceivedNotifier.value = _receivedEventsCount;
        }

        // Handle pipeline readiness handshake
        if (event is ReadyInitEvent) {
          final screenSize = await NativeInputService().getScreenSize();
          sendEvent(ReadyAckEvent(
            screenWidth: screenSize.width,
            screenHeight: screenSize.height,
          ));
          statusNotifier.value = NetworkConnectionStatus.remoteControlReady;
          return;
        }

        if (event is PingEvent) {
          final pong = PongEvent(timestamp: event.timestamp);
          sendEvent(pong);
          return;
        }

        if (event is DisconnectEvent) {
          disconnect(reason: event.reason ?? 'Remote user disconnected');
          return;
        }

        _serverEventHandler?.call(event);
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
    _clientEventHandler = eventHandler;
    _clientDisconnectHandler = disconnectHandler;
    _isClientMode = true;
    statusNotifier.value = NetworkConnectionStatus.connecting;

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
          .listen((line) async {
        if (line.trim().isEmpty) return;

        if (!isHandshakeComplete) {
          try {
            final data = jsonDecode(line) as Map<String, dynamic>;
            final type = data['type'] as String?;

            if (type == 'connect_response') {
              final response = ConnectionResponse.fromMap(data);

              if (response.accepted) {
                isHandshakeComplete = true;
                statusNotifier.value = NetworkConnectionStatus.connected;
                _startPingTimer();

                // Send 3-way initialization check
                _readyAckCompleter = Completer<bool>();
                sendEvent(ReadyInitEvent());

                // Wait up to 4s for Receiver to acknowledge pipeline ready
                try {
                  await _readyAckCompleter!.future.timeout(const Duration(seconds: 4));
                  statusNotifier.value = NetworkConnectionStatus.remoteControlReady;
                  if (!completer.isCompleted) completer.complete(response);
                } catch (_) {
                  if (!completer.isCompleted) {
                    completer.complete(ConnectionResponse(
                      accepted: false,
                      reason: 'Remote control pipeline initialization timed out. Please try connecting again.',
                    ));
                  }
                  disconnect(reason: 'Pipeline initialization timeout');
                }
              } else {
                statusNotifier.value = NetworkConnectionStatus.failed;
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

          _receivedEventsCount++;
          final now = DateTime.now().millisecondsSinceEpoch;
          if (now - _lastReceivedNotifierUpdate > 250) {
            _lastReceivedNotifierUpdate = now;
            eventsReceivedNotifier.value = _receivedEventsCount;
          }

          if (event is ReadyAckEvent) {
            if (_readyAckCompleter != null && !_readyAckCompleter!.isCompleted) {
              _readyAckCompleter?.complete(true);
            }
            statusNotifier.value = NetworkConnectionStatus.remoteControlReady;
            return;
          }

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

          _clientEventHandler?.call(event);
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
      statusNotifier.value = NetworkConnectionStatus.awaitingApproval;
      final request = ConnectionRequest(
        fromKey: myKey,
        deviceName: myName,
        platform: myOs,
        ip: host,
      );

      socket.writeln(jsonEncode(request.toMap()));
      await socket.flush();
    } catch (e) {
      statusNotifier.value = NetworkConnectionStatus.failed;
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
      _sentEventsCount++;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastSentNotifierUpdate > 250) {
        _lastSentNotifierUpdate = now;
        eventsSentNotifier.value = _sentEventsCount;
      }
    } catch (e) {
      debugPrint('Error sending event: $e');
    }
  }

  /// Disconnect active session safely
  void disconnect({String reason = 'Disconnected'}) {
    _pingTimer?.cancel();
    _pingTimer = null;

    if (_readyAckCompleter != null && !_readyAckCompleter!.isCompleted) {
      _readyAckCompleter?.complete(false);
    }
    _readyAckCompleter = null;

    if (_activeSocket != null) {
      try {
        _activeSocket?.writeln(DisconnectEvent(reason: reason).serialize());
        _activeSocket?.flush();
      } catch (_) {}

      _socketSubscription?.cancel();
      _socketSubscription = null;
      _activeSocket?.destroy();
      _activeSocket = null;

      if (_isClientMode) {
        _clientDisconnectHandler?.call(reason);
      } else {
        _serverDisconnectHandler?.call(reason);
      }
      _isClientMode = false;
      _sentEventsCount = 0;
      _receivedEventsCount = 0;
      eventsSentNotifier.value = 0;
      eventsReceivedNotifier.value = 0;
      statusNotifier.value = NetworkConnectionStatus.idle;
    }
  }

  /// Stop TCP server and close all sockets
  void stopServer() {
    disconnect();
    _serverSocket?.close();
    _serverSocket = null;
  }
}

