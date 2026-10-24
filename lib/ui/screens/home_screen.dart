import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/connection_state.dart';
import '../../models/control_events.dart';
import '../../models/peer_info.dart';
import '../../services/discovery_service.dart';
import '../../services/native_input_service.dart';
import '../../services/network_service.dart';
import '../../services/storage_service.dart';
import '../theme/app_colors.dart';
import '../widgets/connection_request_dialog.dart';
import '../widgets/glass_card.dart';
import '../widgets/key_card.dart';
import '../widgets/status_pill.dart';
import '../widgets/device_avatar.dart';
import 'controller_screen.dart';
import 'receiver_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _keyInputController = TextEditingController();
  final GlobalKey<ReceiverScreenState> _receiverKey = GlobalKey<ReceiverScreenState>();

  String _myKey = '';
  String _myName = 'My Laptop';
  final String _myOs = Platform.isMacOS ? 'macos' : 'windows';
  bool _isConnecting = false;
  String? _statusMessage;
  bool _hasAccessibility = true;

  ConnectionMode _connectionMode = ConnectionMode.idle;
  PeerInfo? _activeControllerPeer;
  ConnectionRequest? _activeReceiverRequest;
  double _remoteScreenWidth = 1920.0;
  double _remoteScreenHeight = 1080.0;

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  @override
  void dispose() {
    _keyInputController.dispose();
    super.dispose();
  }

  Future<void> _initializeServices() async {
    _myKey = StorageService().connectionKey;
    _myName = await NativeInputService().getDeviceName();
    StorageService().deviceName = _myName;

    if (Platform.isMacOS) {
      _hasAccessibility = await NativeInputService().checkAccessibilityPermission();
    }

    if (mounted) setState(() {});

    // Start UDP discovery beacon
    await DiscoveryService().start(
      myKey: _myKey,
      myName: _myName,
      myOs: _myOs,
    );

    // Start TCP server on receiver
    await NetworkService().startServer(
      requestApprovalHandler: _handleIncomingConnectionRequest,
      eventHandler: (event) {
        if (_receiverKey.currentState != null) {
          _receiverKey.currentState?.handleIncomingEvent(event);
        } else {
          _simulateNativeEventDirectly(event);
        }
      },
      disconnectHandler: (reason) {
        if (mounted) {
          setState(() {
            _connectionMode = ConnectionMode.idle;
            _activeControllerPeer = null;
            _activeReceiverRequest = null;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Session ended: $reason'),
              backgroundColor: AppColors.surfaceElevated,
            ),
          );
        }
      },
    );
  }

  /// Called when another laptop connects and requests control (Section 2)
  Future<bool> _handleIncomingConnectionRequest(ConnectionRequest request) async {
    if (!mounted) return false;

    final completer = Completer<bool>();

    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return ConnectionRequestDialog(
          request: request,
          onAccept: () {
            Navigator.of(ctx).pop(true);
          },
          onReject: () {
            Navigator.of(ctx).pop(false);
          },
        );
      },
    ).then((accepted) {
      final isAccepted = accepted ?? false;
      if (isAccepted) {
        setState(() {
          _connectionMode = ConnectionMode.receiver;
          _activeReceiverRequest = request;
        });
      }
      completer.complete(isAccepted);
    });

    return completer.future;
  }

  void _simulateNativeEventDirectly(ControlEvent event) {
    if (event is PauseEvent && event.isPaused) {
      NativeInputService().simulateMouseButton(button: 0, isDown: false);
      NativeInputService().simulateMouseButton(button: 1, isDown: false);
      return;
    }

    if (event is MouseMoveEvent) {
      NativeInputService().simulateMouseMove(
        dx: event.dx,
        dy: event.dy,
        x: event.x,
        y: event.y,
      );
    } else if (event is MouseButtonEvent) {
      NativeInputService().simulateMouseButton(
        button: event.button,
        isDown: event.isDown,
      );
    } else if (event is MouseScrollEvent) {
      NativeInputService().simulateMouseScroll(
        dx: event.dx,
        dy: event.dy,
      );
    } else if (event is KeyEventData) {
      NativeInputService().simulateKey(
        keyCode: event.keyCode,
        windowsVk: event.windowsVk,
        macosVk: event.macosVk,
        isDown: event.isDown,
        characters: event.character ?? (event.label.length == 1 ? event.label : null),
        meta: event.meta,
        ctrl: event.ctrl,
        alt: event.alt,
        shift: event.shift,
      );
    }
  }

  /// Initiates connection to another laptop using entered key (Section 1 & 2)
  Future<void> _initiateConnection([PeerInfo? targetPeer]) async {
    final rawInput = targetPeer != null ? targetPeer.key : _keyInputController.text.trim();
    if (rawInput.isEmpty) {
      _showError('Please enter a connection key');
      return;
    }

    // Check if user is trying to connect to their own key
    if (rawInput.toUpperCase() == _myKey.toUpperCase()) {
      _showError('Cannot connect to your own laptop');
      return;
    }

    setState(() {
      _isConnecting = true;
      _statusMessage = 'Locating device on local network...';
    });

    // Find peer from local discovery or parse manual host/ip
    String host = '';
    int port = StorageService.tcpControlPort;
    String targetKey = rawInput;
    String targetName = 'Remote Laptop';
    String targetOs = 'unknown';

    if (targetPeer != null) {
      host = targetPeer.ip;
      port = targetPeer.port;
      targetKey = targetPeer.key;
      targetName = targetPeer.name;
      targetOs = targetPeer.os;
    } else {
      // Check discovery service first
      final peer = DiscoveryService().findPeerByKey(rawInput);
      if (peer != null) {
        host = peer.ip;
        port = peer.port;
        targetKey = peer.key;
        targetName = peer.name;
        targetOs = peer.os;
      } else if (rawInput.contains('.')) {
        // Direct IP entry fallback (e.g. 192.168.1.45 or CC-1234@192.168.1.45)
        if (rawInput.contains('@')) {
          final parts = rawInput.split('@');
          targetKey = parts[0];
          host = parts[1];
        } else {
          host = rawInput;
        }
      } else {
        setState(() {
          _isConnecting = false;
          _statusMessage = null;
        });
        _showError(
          'Could not find laptop with key "$rawInput" on this local Wi-Fi.\n'
          'Ensure CrossControl is open on the other laptop and connected to the same network.',
        );
        return;
      }
    }

    // Status listener for rich connection status updates
    void onStatusChanged() {
      if (!mounted) return;
      final status = NetworkService().statusNotifier.value;
      setState(() {
        switch (status) {
          case NetworkConnectionStatus.connecting:
            _statusMessage = 'Connecting to $targetName over local Wi-Fi...';
            break;
          case NetworkConnectionStatus.awaitingApproval:
            _statusMessage = 'Request sent to $targetName... Awaiting user approval...';
            break;
          case NetworkConnectionStatus.connected:
            _statusMessage = 'Approval received! Initializing remote control pipeline...';
            break;
          case NetworkConnectionStatus.remoteControlReady:
            _statusMessage = 'Remote control verified and ready!';
            break;
          case NetworkConnectionStatus.failed:
            _statusMessage = 'Connection or initialization failed.';
            break;
          case NetworkConnectionStatus.idle:
            break;
        }
      });
    }

    NetworkService().statusNotifier.addListener(onStatusChanged);

    try {
      final response = await NetworkService().connectToPeer(
        host: host,
        port: port,
        myKey: _myKey,
        myName: _myName,
        myOs: _myOs,
        eventHandler: (event) {},
        disconnectHandler: (reason) {
          if (mounted) {
            setState(() {
              _connectionMode = ConnectionMode.idle;
              _activeControllerPeer = null;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Control session ended: $reason')),
            );
          }
        },
      );

      if (!mounted) return;

      setState(() {
        _isConnecting = false;
        _statusMessage = null;
      });

      if (response.accepted) {
        final connectedPeer = PeerInfo(
          key: targetKey,
          name: targetName,
          ip: host,
          port: port,
          os: targetOs,
        );
        setState(() {
          _connectionMode = ConnectionMode.controller;
          _activeControllerPeer = connectedPeer;
          _remoteScreenWidth = response.screenWidth ?? 1920.0;
          _remoteScreenHeight = response.screenHeight ?? 1080.0;
        });
      } else {
        _showError(
          response.reason ?? 'Connection request was declined by the remote user.',
          retryPeer: targetPeer,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _statusMessage = null;
        });
        _showError('Connection error: $e', retryPeer: targetPeer);
      }
    } finally {
      NetworkService().statusNotifier.removeListener(onStatusChanged);
    }
  }

  void _showError(String message, {PeerInfo? retryPeer}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(
          children: [
            Icon(Icons.error_outline_rounded, color: AppColors.coral, size: 24),
            SizedBox(width: 10),
            Text('Connection Notice', style: TextStyle(color: AppColors.textPrimary, fontSize: 18)),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.4),
        ),
        actions: [
          if (retryPeer != null)
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _initiateConnection(retryPeer);
              },
              child: const Text('Retry', style: TextStyle(color: AppColors.cyan, fontWeight: FontWeight.bold)),
            ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.cyan),
            child: const Text('OK', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // If in Controller Mode -> show Controller Screen
    if (_connectionMode == ConnectionMode.controller && _activeControllerPeer != null) {
      return ControllerScreen(
        peer: _activeControllerPeer!,
        targetScreenWidth: _remoteScreenWidth,
        targetScreenHeight: _remoteScreenHeight,
        onDisconnect: () {
          setState(() {
            _connectionMode = ConnectionMode.idle;
            _activeControllerPeer = null;
          });
        },
      );
    }

    // If in Receiver Mode -> show Receiver Screen
    if (_connectionMode == ConnectionMode.receiver && _activeReceiverRequest != null) {
      return ReceiverScreen(
        key: _receiverKey,
        request: _activeReceiverRequest!,
        onDisconnect: () {
          setState(() {
            _connectionMode = ConnectionMode.idle;
            _activeReceiverRequest = null;
          });
        },
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Background ambient gradient glow
          Positioned(
            top: -120,
            left: MediaQuery.of(context).size.width * 0.3,
            child: Container(
              width: 500,
              height: 350,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.cyan.withOpacity(0.08),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Main Scrollable Area
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 28),
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 820),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header: App Name, Subtitle, Network Pill
                      _buildHeader(),
                      const SizedBox(height: 24),

                      if (Platform.isMacOS && !_hasAccessibility) ...[
                        _buildAccessibilityBanner(),
                        const SizedBox(height: 22),
                      ],

                      // Section 1: Connect to System (This Laptop's Unique Key)
                      ValueListenableBuilder<String?>(
                        valueListenable: DiscoveryService().localIpNotifier,
                        builder: (context, localIp, _) {
                          return KeyCard(
                            connectionKey: _myKey,
                            deviceName: _myName,
                            localIp: localIp ?? '127.0.0.1',
                          );
                        },
                      ),
                      const SizedBox(height: 22),

                      // Section 2: Enter Connection Key & Connect Button
                      _buildEnterKeyCard(),
                      const SizedBox(height: 22),

                      // Section 3: Nearby Laptops on LAN (Auto-Discovery)
                      _buildDiscoveredPeersCard(),
                      const SizedBox(height: 22),

                      // Section 4: System Information & Shortcuts Guide
                      _buildShortcutAndInfoCard(),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Connecting Modal / Overlay
          if (_isConnecting) _buildConnectingOverlay(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Row(
            children: [
              const DeviceAvatar(size: 46, showBadge: false),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'CrossControl',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Cross-Platform Keyboard & Mouse Control for macOS & Windows',
                      style: TextStyle(
                        color: AppColors.textSecondary.withOpacity(0.9),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),

        // Network Status Pill
        ValueListenableBuilder<String?>(
          valueListenable: DiscoveryService().localIpNotifier,
          builder: (context, localIp, _) {
            return StatusPill(
              label: 'LAN: ${localIp ?? "Detecting..."}',
              color: localIp != null ? AppColors.emerald : AppColors.amber,
              icon: Icons.wifi_rounded,
            );
          },
        ),
      ],
    );
  }

  Widget _buildEnterKeyCard() {
    return GlassCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.electricBlue.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.dialpad_rounded, color: AppColors.electricBlue, size: 20),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'REMOTE SYSTEM',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Enter Connection Key',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Input Row with Paste and Connect Button
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.background.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: TextField(
                    controller: _keyInputController,
                    textCapitalization: TextCapitalization.characters,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.0,
                      fontFamily: 'Courier',
                    ),
                    decoration: InputDecoration(
                      hintText: 'e.g. CC-4829',
                      hintStyle: TextStyle(
                        color: AppColors.textMuted.withOpacity(0.6),
                        fontSize: 16,
                        letterSpacing: 1.0,
                      ),
                      prefixIcon: const Icon(Icons.vpn_key_outlined, color: AppColors.textMuted, size: 20),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.paste_rounded, color: AppColors.textSecondary, size: 20),
                        tooltip: 'Paste from clipboard',
                        onPressed: () async {
                          final data = await Clipboard.getData('text/plain');
                          if (data?.text != null) {
                            _keyInputController.text = data!.text!.trim().toUpperCase();
                          }
                        },
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    ),
                    onSubmitted: (_) => _initiateConnection(),
                  ),
                ),
              ),
              const SizedBox(width: 14),

              // Connect Button (Section 1)
              ElevatedButton(
                onPressed: _isConnecting ? null : () => _initiateConnection(),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
                  backgroundColor: AppColors.cyan,
                  elevation: 6,
                  shadowColor: AppColors.cyan.withOpacity(0.35),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.link_rounded, color: Colors.black, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Connect',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Both laptops must be connected to the same local network (Wi-Fi or Ethernet).',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildDiscoveredPeersCard() {
    return ValueListenableBuilder<List<PeerInfo>>(
      valueListenable: DiscoveryService().peersNotifier,
      builder: (context, peers, _) {
        return GlassCard(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.neonPurple.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.radar_rounded, color: AppColors.neonPurple, size: 20),
                      ),
                      const SizedBox(width: 12),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'LOCAL NETWORK DISCOVERY',
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.1,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Nearby Laptops on Local Wi-Fi',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  StatusPill(
                    label: '${peers.length} detected',
                    color: peers.isNotEmpty ? AppColors.emerald : AppColors.cyan,
                    isPulsing: true,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              if (peers.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.background.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border.withOpacity(0.5)),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.cyan),
                      ),
                      SizedBox(width: 14),
                      Flexible(
                        child: Text(
                          'Scanning local Wi-Fi for other laptops running CrossControl...',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: peers.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final peer = peers[index];
                    final isMac = peer.os.toLowerCase().contains('mac');

                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.background.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          DeviceAvatar(
                            size: 34,
                            isMac: isMac,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  peer.name,
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Key: ${peer.key} • IP: ${peer.ip}',
                                  style: const TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 12,
                                    fontFamily: 'Courier',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton(
                            onPressed: () {
                              _keyInputController.text = peer.key;
                              _initiateConnection(peer);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.cyan.withOpacity(0.15),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide(color: AppColors.cyan.withOpacity(0.4)),
                              ),
                            ),
                            child: const Text(
                              'Connect',
                              style: TextStyle(
                                color: AppColors.cyan,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildShortcutAndInfoCard() {
    final shortcutLabel = StorageService().shortcutLabel;

    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.amber.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.keyboard_command_key_rounded, color: AppColors.amber, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Emergency Pause / Resume Shortcut:',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.amber.withOpacity(0.5)),
                      ),
                      child: Text(
                        shortcutLabel,
                        style: const TextStyle(
                          color: AppColors.amber,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Courier',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Triggering this shortcut immediately pauses remote control and restores local mouse and keyboard operation.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectingOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.75),
        child: Center(
          child: GlassCard(
            borderColor: AppColors.cyan.withOpacity(0.5),
            backgroundColor: AppColors.surfaceElevated.withOpacity(0.96),
            padding: const EdgeInsets.all(32),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 48,
                    height: 48,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: AppColors.cyan,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Connecting to Remote Laptop',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _statusMessage ?? 'Waiting for approval from the other laptop...',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 24),
                  OutlinedButton(
                    onPressed: () {
                      NetworkService().disconnect();
                      setState(() {
                        _isConnecting = false;
                        _statusMessage = null;
                      });
                    },
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: AppColors.coral.withOpacity(0.5)),
                    ),
                    child: const Text('Cancel Request', style: TextStyle(color: AppColors.coral)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAccessibilityBanner() {
    return GlassCard(
      borderColor: AppColors.amber.withOpacity(0.6),
      backgroundColor: AppColors.amber.withOpacity(0.08),
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          const Icon(Icons.security_update_warning_rounded, color: AppColors.amber, size: 28),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'macOS Accessibility Permission Needed',
                  style: TextStyle(
                    color: AppColors.amber,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'To allow CrossControl to simulate mouse and keyboard input on this Mac when controlled by another laptop, enable it in System Settings.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          ElevatedButton(
            onPressed: () async {
              await NativeInputService().requestAccessibilityPermission();
              await NativeInputService().openAccessibilitySettings();
              final trusted = await NativeInputService().checkAccessibilityPermission();
              if (mounted) setState(() => _hasAccessibility = trusted);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.amber,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text(
              'Enable Permission',
              style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
