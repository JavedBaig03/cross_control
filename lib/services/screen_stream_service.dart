import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
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
  Timer? _fallbackCaptureTimer;
  int _lastFrameTimestamp = 0;
  Uint8List? _latestPendingFrame;
  bool _isTransmitting = false;

  // Controller-side client state
  Socket? _streamClientSocket;
  StreamSubscription? _streamSubscription;
  final ValueNotifier<Uint8List?> currentFrameNotifier = ValueNotifier<Uint8List?>(null);
  final ValueNotifier<ui.Image?> currentImageNotifier = ValueNotifier<ui.Image?>(null);
  final ValueNotifier<int> fpsNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> receivedFpsNotifier = ValueNotifier<int>(0);
  final ValueNotifier<double> bitrateMbpsNotifier = ValueNotifier<double>(0.0);
  final ValueNotifier<String> streamResolutionNotifier = ValueNotifier<String>('');
  final ValueNotifier<bool> isStreamingNotifier = ValueNotifier<bool>(false);

  // Background decoding state
  bool _isDecoding = false;
  Uint8List? _nextFrameToDecode;

  // FPS and throughput calculation
  int _receivedFramesInWindow = 0;
  int _displayedFramesInWindow = 0;
  int _totalBytesInWindow = 0;
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

    // Start native continuous capture (ScreenCaptureKit / GDI) at 30 FPS, 0.85 quality, native aspect ratio
    await NativeInputService().startScreenCapture(
      fps: 30,
      quality: 0.85,
      width: 0,
      height: 0,
    );

    // If native continuous stream didn't produce frames for > 1500ms, run fallback periodic capture
    _fallbackCaptureTimer?.cancel();
    _fallbackCaptureTimer = Timer.periodic(const Duration(milliseconds: 100), (_) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastFrameTimestamp > 1500) {
        final frame = await NativeInputService().captureScreenFrame(
          quality: 0.85,
          width: 0,
          height: 0,
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

  /// Prioritize latest frame and stream to client without building an outdated backlog
  void _sendFrameToClient(Uint8List frame) {
    if (_receiverClientSocket == null) return;

    _latestPendingFrame = frame;

    if (!_isTransmitting) {
      _transmitLoop();
    }
  }

  Future<void> _transmitLoop() async {
    if (_isTransmitting) return;
    _isTransmitting = true;

    try {
      while (_receiverClientSocket != null && _latestPendingFrame != null) {
        final frameToSend = _latestPendingFrame!;
        _latestPendingFrame = null;

        final client = _receiverClientSocket;
        if (client == null) break;

        final header = ByteData(4)..setUint32(0, frameToSend.length, Endian.big);
        client.add(header.buffer.asUint8List());
        client.add(frameToSend);

        // Yield to the event loop so the socket can write asynchronously without
        // blocking the Dart isolate on TCP acknowledgment round trips.
        await Future<void>.delayed(Duration.zero);
      }
    } catch (e) {
      debugPrint('Error sending frame to stream client: $e');
      _cleanupReceiverClient();
    } finally {
      _isTransmitting = false;
    }
  }

  void _cleanupReceiverClient() {
    _fallbackCaptureTimer?.cancel();
    _fallbackCaptureTimer = null;
    NativeInputService().onScreenFrame = null;
    NativeInputService().stopScreenCapture();

    _latestPendingFrame = null;
    _isTransmitting = false;

    try {
      _receiverClientSocket?.destroy();
    } catch (_) {}
    _receiverClientSocket = null;
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
      _receivedFramesInWindow = 0;
      _displayedFramesInWindow = 0;
      _totalBytesInWindow = 0;

      // High performance zero-copy packet reassembler
      Uint8List? frameBuffer;
      int frameBytesReceived = 0;
      int expectedFrameLength = 0;

      final Uint8List headerBuffer = Uint8List(4);
      int headerBytesReceived = 0;

      _streamSubscription = socket.listen(
        (List<int> chunk) {
          int chunkOffset = 0;

          while (chunkOffset < chunk.length) {
            // Step 1: Read 4-byte big-endian length header
            if (headerBytesReceived < 4) {
              final bytesNeeded = 4 - headerBytesReceived;
              final bytesAvailable = chunk.length - chunkOffset;
              final copyCount = min(bytesNeeded, bytesAvailable);

              headerBuffer.setRange(
                headerBytesReceived,
                headerBytesReceived + copyCount,
                chunk,
                chunkOffset,
              );
              headerBytesReceived += copyCount;
              chunkOffset += copyCount;

              if (headerBytesReceived == 4) {
                expectedFrameLength = ByteData.sublistView(headerBuffer).getUint32(0, Endian.big);
                if (expectedFrameLength <= 0 || expectedFrameLength > 30 * 1024 * 1024) {
                  debugPrint('Invalid stream frame length: $expectedFrameLength');
                  headerBytesReceived = 0;
                  expectedFrameLength = 0;
                  frameBuffer = null;
                  break;
                }
                frameBuffer = Uint8List(expectedFrameLength);
                frameBytesReceived = 0;
              }
              continue;
            }

            // Step 2: Read payload bytes directly into targetBuffer
            final targetBuffer = frameBuffer;
            if (targetBuffer != null && frameBytesReceived < expectedFrameLength) {
              final bytesNeeded = expectedFrameLength - frameBytesReceived;
              final bytesAvailable = chunk.length - chunkOffset;
              final copyCount = min(bytesNeeded, bytesAvailable);

              targetBuffer.setRange(
                frameBytesReceived,
                frameBytesReceived + copyCount,
                chunk,
                chunkOffset,
              );
              frameBytesReceived += copyCount;
              chunkOffset += copyCount;

              if (frameBytesReceived == expectedFrameLength) {
                final completedFrame = targetBuffer;
                headerBytesReceived = 0;
                expectedFrameLength = 0;
                frameBuffer = null;
                frameBytesReceived = 0;

                _deliverFrame(completedFrame, onFrame);
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

  void _deliverFrame(Uint8List frameBytes, void Function(Uint8List frame)? onFrame) {
    currentFrameNotifier.value = frameBytes;
    onFrame?.call(frameBytes);

    _receivedFramesInWindow++;
    _totalBytesInWindow += frameBytes.length + 4;

    _decodeAndNotify(frameBytes);
  }

  void _decodeAndNotify(Uint8List bytes) async {
    if (_isDecoding) {
      _nextFrameToDecode = bytes;
      return;
    }

    _isDecoding = true;
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final codec = await descriptor.instantiateCodec();
      final frameInfo = await codec.getNextFrame();
      final image = frameInfo.image;

      final old = currentImageNotifier.value;
      currentImageNotifier.value = image;
      old?.dispose();

      // Track ACTUAL displayed frames presented to Flutter rendering pipeline
      _displayedFramesInWindow++;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _windowStartTime >= 1000) {
        final double seconds = (now - _windowStartTime) / 1000.0;
        fpsNotifier.value = (_displayedFramesInWindow / seconds).round();
        receivedFpsNotifier.value = (_receivedFramesInWindow / seconds).round();
        bitrateMbpsNotifier.value = ((_totalBytesInWindow * 8.0) / (1024.0 * 1024.0)) / seconds;
        streamResolutionNotifier.value = '${image.width}x${image.height}';

        _displayedFramesInWindow = 0;
        _receivedFramesInWindow = 0;
        _totalBytesInWindow = 0;
        _windowStartTime = now;
      }
    } catch (_) {
      // Gracefully ignore decoding errors for incomplete or synthetic test payloads
    } finally {
      _isDecoding = false;
      if (_nextFrameToDecode != null) {
        final next = _nextFrameToDecode!;
        _nextFrameToDecode = null;
        _decodeAndNotify(next);
      }
    }
  }

  Future<void> disconnectStream() async {
    isStreamingNotifier.value = false;
    fpsNotifier.value = 0;
    receivedFpsNotifier.value = 0;
    bitrateMbpsNotifier.value = 0.0;
    streamResolutionNotifier.value = '';
    currentFrameNotifier.value = null;

    currentImageNotifier.value?.dispose();
    currentImageNotifier.value = null;
    _nextFrameToDecode = null;
    _isDecoding = false;

    _displayedFramesInWindow = 0;
    _receivedFramesInWindow = 0;
    _totalBytesInWindow = 0;

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
