import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'native_input_service.dart';
import 'storage_service.dart';

class ScreenStreamService {
  static final ScreenStreamService _instance = ScreenStreamService._internal();
  factory ScreenStreamService() => _instance;
  ScreenStreamService._internal();

  // Receiver-side server state
  ServerSocket? _serverSocket;
  Socket? _receiverClientSocket;
  bool _isWritingFrame = false;
  Timer? _fallbackCaptureTimer;
  int _lastFrameTimestamp = 0;

  // Controller-side client state
  Socket? _streamClientSocket;
  StreamSubscription? _streamSubscription;
  final ValueNotifier<Uint8List?> currentFrameNotifier = ValueNotifier<Uint8List?>(null);
  final ValueNotifier<int> fpsNotifier = ValueNotifier<int>(0);
  final ValueNotifier<bool> isStreamingNotifier = ValueNotifier<bool>(false);

  // FPS calculation
  int _frameCountInWindow = 0;
  int _windowStartTime = 0;

  bool get isReceiverServerRunning => _serverSocket != null;
  bool get isControllerStreamConnected => _streamClientSocket != null;

  // ---------------------------------------------------------------------------
  // RECEIVER SIDE: Screen capture server (streams to connected Controller)
  // ---------------------------------------------------------------------------

  Future<void> startStreamingServer({int port = StorageService.tcpScreenPort}) async {
    await stopStreamingServer();

    try {
      _serverSocket = await ServerSocket.bind(
        InternetAddress.anyIPv4,
        port,
        shared: true,
      );

      _serverSocket?.listen(
        _handleIncomingStreamClient,
        onError: (err) {
          debugPrint('ScreenStream Server error: $err');
          stopStreamingServer();
        },
        onDone: () {
          stopStreamingServer();
        },
      );
      debugPrint('ScreenStream Server listening on port $port');
    } catch (e) {
      debugPrint('Error starting ScreenStream Server: $e');
    }
  }

  void _handleIncomingStreamClient(Socket client) async {
    // If another client is already connected, close the new one
    if (_receiverClientSocket != null) {
      try {
        await client.close();
      } catch (_) {}
      return;
    }

    _receiverClientSocket = client;
    try {
      client.setOption(SocketOption.tcpNoDelay, true);
    } catch (_) {}

    debugPrint('ScreenStream client connected from ${client.remoteAddress.address}:${client.remotePort}');

    // Register callback for native frames
    NativeInputService().onScreenFrame = (Uint8List frameBytes) {
      _lastFrameTimestamp = DateTime.now().millisecondsSinceEpoch;
      _sendFrameToClient(frameBytes);
    };

    // Start native continuous capture (ScreenCaptureKit / GDI)
    await NativeInputService().startScreenCapture(
      fps: 25,
      quality: 0.6,
      width: 1280,
      height: 720,
    );

    // If native continuous stream didn't start or hasn't produced frames, run fallback periodic capture
    _fallbackCaptureTimer?.cancel();
    _fallbackCaptureTimer = Timer.periodic(const Duration(milliseconds: 70), (_) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastFrameTimestamp > 300) {
        final frame = await NativeInputService().captureScreenFrame(
          quality: 0.6,
          width: 1280,
          height: 720,
        );
        if (frame != null && frame.isNotEmpty) {
          _sendFrameToClient(frame);
        }
      }
    });

    client.listen(
      (data) {
        // Stream socket is unidirectional; ignore incoming client data
      },
      onError: (err) {
        debugPrint('ScreenStream client error: $err');
        _cleanupReceiverClient();
      },
      onDone: () {
        debugPrint('ScreenStream client disconnected');
        _cleanupReceiverClient();
      },
      cancelOnError: true,
    );
  }

  void _sendFrameToClient(Uint8List frame) async {
    final client = _receiverClientSocket;
    if (client == null || _isWritingFrame) return; // Drop frame if network is backpressured

    _isWritingFrame = true;
    try {
      final header = ByteData(4)..setUint32(0, frame.length, Endian.big);
      client.add(header.buffer.asUint8List());
      client.add(frame);
      await client.flush();
    } catch (e) {
      debugPrint('Error sending frame to stream client: $e');
      _cleanupReceiverClient();
    } finally {
      _isWritingFrame = false;
    }
  }

  void _cleanupReceiverClient() {
    _fallbackCaptureTimer?.cancel();
    _fallbackCaptureTimer = null;
    NativeInputService().onScreenFrame = null;
    NativeInputService().stopScreenCapture();

    try {
      _receiverClientSocket?.destroy();
    } catch (_) {}
    _receiverClientSocket = null;
    _isWritingFrame = false;
  }

  Future<void> stopStreamingServer() async {
    _cleanupReceiverClient();
    try {
      await _serverSocket?.close();
    } catch (_) {}
    _serverSocket = null;
  }

  // ---------------------------------------------------------------------------
  // CONTROLLER SIDE: Screen stream client (displays received frames)
  // ---------------------------------------------------------------------------

  Future<bool> connectToStream({
    required String host,
    int port = StorageService.tcpScreenPort,
    void Function(Uint8List frame)? onFrame,
    void Function(String error)? onError,
  }) async {
    await disconnectStream();

    try {
      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 4),
      );
      try {
        socket.setOption(SocketOption.tcpNoDelay, true);
      } catch (_) {}

      _streamClientSocket = socket;
      isStreamingNotifier.value = true;
      _windowStartTime = DateTime.now().millisecondsSinceEpoch;
      _frameCountInWindow = 0;

      final BytesBuilder buffer = BytesBuilder(copy: false);
      int? expectedLength;

      _streamSubscription = socket.listen(
        (List<int> chunk) {
          buffer.add(chunk);

          while (true) {
            if (expectedLength == null) {
              if (buffer.length < 4) {
                break; // Await more header bytes
              }
              final bytes = buffer.takeBytes();
              final byteData = ByteData.sublistView(bytes);
              expectedLength = byteData.getUint32(0, Endian.big);

              // Put remaining bytes back into buffer
              if (bytes.length > 4) {
                buffer.add(bytes.sublist(4));
              }
            }

            if (expectedLength != null) {
              if (buffer.length < expectedLength!) {
                break; // Await full payload
              }

              final fullBuffer = buffer.takeBytes();
              final Uint8List frameBytes = Uint8List.fromList(fullBuffer.sublist(0, expectedLength!));

              // Re-add extra bytes past current frame
              if (fullBuffer.length > expectedLength!) {
                buffer.add(fullBuffer.sublist(expectedLength!));
              }

              expectedLength = null;

              // Deliver frame
              currentFrameNotifier.value = frameBytes;
              onFrame?.call(frameBytes);

              // Calculate FPS
              _frameCountInWindow++;
              final now = DateTime.now().millisecondsSinceEpoch;
              if (now - _windowStartTime >= 1000) {
                fpsNotifier.value = _frameCountInWindow;
                _frameCountInWindow = 0;
                _windowStartTime = now;
              }
            }
          }
        },
        onError: (err) {
          debugPrint('Controller stream error: $err');
          onError?.call('Screen stream error: $err');
          disconnectStream();
        },
        onDone: () {
          debugPrint('Controller stream connection closed');
          disconnectStream();
        },
        cancelOnError: true,
      );

      return true;
    } catch (e) {
      debugPrint('Could not connect to remote screen stream: $e');
      onError?.call('Could not connect to remote screen stream: $e');
      disconnectStream();
      return false;
    }
  }

  Future<void> disconnectStream() async {
    isStreamingNotifier.value = false;
    fpsNotifier.value = 0;
    currentFrameNotifier.value = null;

    try {
      await _streamSubscription?.cancel();
    } catch (_) {}
    _streamSubscription = null;

    try {
      _streamClientSocket?.destroy();
    } catch (_) {}
    _streamClientSocket = null;
  }
}
