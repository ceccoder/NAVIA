import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/navigation_models.dart';
import '../services/api_service.dart';
import '../services/ble_service.dart';
import '../services/tts_service.dart';
import '../services/update_service.dart';
import '../widgets/camera_ocr_overlay.dart';
import '../widgets/direction_hud.dart';
import 'ble_setup_screen.dart';

/// Next-Generation Accessible Indoor Navigation Screen
/// Integrates Camera OCR, TTS Guidance, BLE Wearable Haptics, and In-App Updates.
class NavigationScreen extends StatefulWidget {
  const NavigationScreen({super.key});

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> with WidgetsBindingObserver {
  // Hardware & sensor services
  final BleService _ble = BleService();
  final TtsService _tts = TtsService();

  // Camera & ML Kit OCR
  CameraController? _cameraController;
  final TextRecognizer _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
  bool _isCameraReady = false;
  bool _isProcessingOcrFrame = false;
  DateTime _lastOcrScanTime = DateTime.now();
  String? _detectedAnchorSign;

  // Navigation State
  RouteResponse? _activeRoute;
  int _currentStepIndex = 0;
  bool _isLoadingRoute = false;
  String _selectedDestination = 'Room 214';
  String _currentStartAnchor = 'L1_ENTRANCE';
  bool _isWheelchairUser = false;
  List<NavNode> _availableNodes = [];
  bool _isServerOnline = false;

  // Subscriptions
  StreamSubscription<String>? _hazardSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeServices();
    _loadDestinationNodes();
    _checkServerStatus();
    _checkForAppUpdates();
  }

  Future<void> _checkServerStatus() async {
    final healthy = await ApiService.checkHealth();
    if (mounted) {
      setState(() {
        _isServerOnline = healthy;
      });
    }
  }

  Future<void> _checkForAppUpdates() async {
    final release = await UpdateService.checkForUpdate();
    if (release != null && mounted) {
      UpdateService.showUpdateDialog(context, release);
    }
  }

  Future<void> _initializeServices() async {
    // 1. Initialize Text-to-Speech
    await _tts.init();

    // 2. Initialize Camera and ML Kit OCR Pipeline
    await _initializeCamera();

    // 3. Listen for wearable proximity alerts (VL53L0X ToF obstacle < 70cm)
    _hazardSubscription = _ble.onHazardAlert.listen((alertMessage) {
      _tts.speakUrgent('Hazard alert! Obstacle detected within 70 centimeters. Stop!');
    });

    // 4. Auto-calculate initial route
    _fetchRoute();
  }

  Future<void> _loadDestinationNodes() async {
    final nodes = await ApiService.fetchNodes();
    if (mounted) {
      setState(() {
        _availableNodes = nodes;
        if (nodes.isNotEmpty && !nodes.any((n) => n.label == _selectedDestination)) {
          _selectedDestination = nodes.first.label;
        }
      });
    }
  }

  Future<void> _initializeCamera() async {
    try {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        debugPrint('[CAMERA] Camera permission denied by user');
        return;
      }

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        debugPrint('[CAMERA] No physical cameras detected (emulator mode)');
        return;
      }

      // Select back-facing camera for scanning hallway signage
      final backCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );

      await _cameraController!.initialize();

      if (!mounted) return;
      setState(() {
        _isCameraReady = true;
      });

      // Stream frames to Google ML Kit OCR
      _cameraController!.startImageStream(_processCameraFrameForOcr);
    } catch (e) {
      debugPrint('[CAMERA] Initialization error: $e');
    }
  }

  /// Processes streaming camera frames for real-time sign recognition
  void _processCameraFrameForOcr(CameraImage image) async {
    final now = DateTime.now();
    if (now.difference(_lastOcrScanTime).inMilliseconds < 600 || _isProcessingOcrFrame) {
      return;
    }

    _isProcessingOcrFrame = true;
    _lastOcrScanTime = now;

    try {
      final inputImage = _inputImageFromCameraImage(image);
      if (inputImage == null) return;

      final recognizedText = await _textRecognizer.processImage(inputImage);

      for (final block in recognizedText.blocks) {
        final text = block.text.trim().toUpperCase();

        for (final node in _availableNodes) {
          final isMatch = node.signs.any((s) => text.contains(s.toUpperCase())) ||
              text.contains(node.label.toUpperCase()) ||
              text.contains(node.id.toUpperCase());

          if (isMatch && text != _detectedAnchorSign) {
            debugPrint('[OCR MATCH] Anchored to sign: "$text" (Node: ${node.id})');
            if (mounted) {
              setState(() {
                _detectedAnchorSign = text;
              });
            }

            _tts.speak('Sign detected: ${node.label}.');
            _handleAnchorSignMatched(node);
            break;
          }
        }
      }
    } catch (e) {
      debugPrint('[OCR] Processing error: $e');
    } finally {
      _isProcessingOcrFrame = false;
    }
  }

  void _handleAnchorSignMatched(NavNode matchedNode) {
    if (_activeRoute != null && _currentStepIndex < _activeRoute!.steps.length) {
      final currentExpectedNode = _activeRoute!.steps[_currentStepIndex].toNode;

      if (matchedNode.id == currentExpectedNode) {
        _nextStep();
        return;
      }
    }

    setState(() {
      _currentStartAnchor = matchedNode.id;
    });
    _fetchRoute();
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    if (_cameraController == null) return null;

    final camera = _cameraController!.description;
    final sensorOrientation = camera.sensorOrientation;
    InputImageRotation? rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null || format != InputImageFormat.nv21) return null;

    if (image.planes.isEmpty) return null;
    final plane = image.planes.first;

    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  Future<void> _fetchRoute() async {
    setState(() {
      _isLoadingRoute = true;
    });

    try {
      final request = RouteRequest(
        buildingId: 'campus_med_center',
        startNodeId: _currentStartAnchor,
        destinationLabel: _selectedDestination,
        userProfile: UserProfile(
          wheelchairUser: _isWheelchairUser,
          avoidStairs: _isWheelchairUser,
          minDoorWidth: _isWheelchairUser ? 0.9 : 0.7,
        ),
      );

      final route = await ApiService.calculateRoute(request);

      if (mounted) {
        setState(() {
          _activeRoute = route;
          _currentStepIndex = 0;
          _isLoadingRoute = false;
        });

        if (route.steps.isNotEmpty) {
          final firstStep = route.steps[0];
          _tts.speak(firstStep.instruction);
          _ble.sendCommand(firstStep.bleCommand);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingRoute = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Route calculation: $e'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    }
  }

  void _nextStep() {
    if (_activeRoute == null || _currentStepIndex >= _activeRoute!.steps.length - 1) return;

    setState(() {
      _currentStepIndex++;
    });

    final currentStep = _activeRoute!.steps[_currentStepIndex];
    _tts.speak(currentStep.instruction);
    _ble.sendCommand(currentStep.bleCommand);
  }

  void _previousStep() {
    if (_currentStepIndex <= 0 || _activeRoute == null) return;

    setState(() {
      _currentStepIndex--;
    });

    final currentStep = _activeRoute!.steps[_currentStepIndex];
    _tts.speak(currentStep.instruction);
    _ble.sendCommand(currentStep.bleCommand);
  }

  void _repeatAudio() {
    if (_activeRoute == null || _currentStepIndex >= _activeRoute!.steps.length) return;
    final currentStep = _activeRoute!.steps[_currentStepIndex];
    _tts.speak(currentStep.instruction);
    _ble.sendCommand(currentStep.bleCommand);
  }

  void _showServerConfigDialog() {
    final controller = TextEditingController(text: ApiService.baseUrl);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFF334155)),
        ),
        title: const Row(
          children: [
            Icon(Icons.cloud_sync_rounded, color: Color(0xFF38BDF8)),
            SizedBox(width: 10),
            Text('Server Connection', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Backend API URL:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF0F172A),
                hintText: 'https://navia-ritk.onrender.com',
                hintStyle: const TextStyle(color: Color(0xFF475569)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  _isServerOnline ? Icons.check_circle_rounded : Icons.error_rounded,
                  color: _isServerOnline ? const Color(0xFF10B981) : const Color(0xFFF43F5E),
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  _isServerOnline ? 'Live Render Server Connected' : 'Server Offline (Using Fallback)',
                  style: TextStyle(
                    color: _isServerOnline ? const Color(0xFF10B981) : const Color(0xFFF43F5E),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF38BDF8),
              foregroundColor: const Color(0xFF0F172A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              ApiService.setBaseUrl(controller.text.trim());
              Navigator.of(ctx).pop();
              await _checkServerStatus();
              await _loadDestinationNodes();
              _fetchRoute();
            },
            child: const Text('Save & Reconnect', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    _textRecognizer.close();
    _hazardSubscription?.cancel();
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final step = (_activeRoute != null && _currentStepIndex < _activeRoute!.steps.length)
        ? _activeRoute!.steps[_currentStepIndex]
        : null;

    final destinationList = _availableNodes.isNotEmpty
        ? _availableNodes.map((n) => n.label).toSet().toList()
        : ['Room 214', 'Room 101', 'Room 102', 'Room 201', 'Restroom'];

    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19),
      body: Stack(
        children: [
          // Background Camera Feed or Hallway Vision Surface
          if (_isCameraReady && _cameraController != null)
            Positioned.fill(
              child: AspectRatio(
                aspectRatio: _cameraController!.value.aspectRatio,
                child: CameraPreview(_cameraController!),
              ),
            )
          else
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0B0F19), Color(0xFF1E293B)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: const Color(0xFF38BDF8).withOpacity(0.1),
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.3)),
                        ),
                        child: const Icon(Icons.center_focus_strong_rounded, color: Color(0xFF38BDF8), size: 40),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Live OCR Visual Navigation',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Align hallway signs inside viewfinder to auto-anchor',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Camera Reticle and Sign Recognition Overlay
          Positioned.fill(
            child: CameraOcrOverlay(
              recognizedSign: _detectedAnchorSign,
              isProcessingOcr: _isProcessingOcrFrame,
            ),
          ),

          // Top Floating Navigation Bar
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B).withOpacity(0.95),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF334155), width: 1.2),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 16, offset: const Offset(0, 6)),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      // Destination Icon
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF38BDF8).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.directions_rounded, color: Color(0xFF38BDF8), size: 22),
                      ),
                      const SizedBox(width: 12),

                      // Destination Dropdown
                      Expanded(
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: destinationList.contains(_selectedDestination) ? _selectedDestination : destinationList.first,
                            dropdownColor: const Color(0xFF1E293B),
                            icon: const Icon(Icons.arrow_drop_down_rounded, color: Color(0xFF38BDF8)),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                            isDense: true,
                            items: destinationList.map((room) {
                              return DropdownMenuItem<String>(
                                value: room,
                                child: Text(room, overflow: TextOverflow.ellipsis),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  _selectedDestination = val;
                                });
                                _fetchRoute();
                              }
                            },
                          ),
                        ),
                      ),

                      // Wheelchair Mode Toggle
                      IconButton(
                        icon: Icon(
                          Icons.accessible_forward_rounded,
                          color: _isWheelchairUser ? const Color(0xFF10B981) : const Color(0xFF64748B),
                          size: 24,
                        ),
                        tooltip: 'Wheelchair / Avoid Stairs',
                        onPressed: () {
                          setState(() {
                            _isWheelchairUser = !_isWheelchairUser;
                          });
                          _tts.speak(_isWheelchairUser ? 'Wheelchair mode: Avoiding stairs.' : 'Wheelchair mode off.');
                          _fetchRoute();
                        },
                      ),

                      // Server Connection Setup Modal
                      IconButton(
                        icon: Icon(
                          _isServerOnline ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                          color: _isServerOnline ? const Color(0xFF38BDF8) : const Color(0xFFF43F5E),
                          size: 22,
                        ),
                        tooltip: 'Server Connection',
                        onPressed: _showServerConfigDialog,
                      ),

                      // Wearable BLE Pairing
                      ValueListenableBuilder<bool>(
                        valueListenable: _ble.isConnectedNotifier,
                        builder: (context, connected, _) {
                          return IconButton(
                            icon: Icon(
                              connected ? Icons.bluetooth_connected_rounded : Icons.bluetooth_disabled_rounded,
                              color: connected ? const Color(0xFF10B981) : const Color(0xFFF43F5E),
                              size: 22,
                            ),
                            tooltip: 'BLE Wearable Setup',
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const BleSetupScreen()),
                              );
                            },
                          );
                        },
                      ),
                    ],
                  ),

                  // Status Indicator Row (Live Server + In-App Update Trigger)
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _isServerOnline ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _isServerOnline ? 'Cloud Backend (Live)' : 'Offline Local Fallback',
                            style: TextStyle(
                              color: _isServerOnline ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      InkWell(
                        onTap: () async {
                          final rel = await UpdateService.checkForUpdate();
                          if (rel != null && mounted) {
                            UpdateService.showUpdateDialog(context, rel, isManual: true);
                          } else if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('NAVIA is up to date! (v1.0.0)'),
                                backgroundColor: Color(0xFF10B981),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                        child: const Row(
                          children: [
                            Icon(Icons.system_update_rounded, size: 13, color: Color(0xFF38BDF8)),
                            SizedBox(width: 4),
                            Text('Check Updates', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Bottom Turn Direction HUD
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: ValueListenableBuilder<String?>(
              valueListenable: _ble.obstacleWarningNotifier,
              builder: (context, warning, _) {
                return ValueListenableBuilder<bool>(
                  valueListenable: _ble.isConnectedNotifier,
                  builder: (context, connected, _) {
                    return ValueListenableBuilder<String>(
                      valueListenable: _ble.lastCommandSentNotifier,
                      builder: (context, lastCmd, _) {
                        return DirectionHud(
                          currentStep: step,
                          currentStepIndex: _currentStepIndex,
                          totalSteps: _activeRoute?.steps.length ?? 0,
                          obstacleWarning: warning,
                          isBleConnected: connected,
                          lastBleCommand: lastCmd,
                          onNextStep: _nextStep,
                          onPreviousStep: _previousStep,
                          onRepeatAudio: _repeatAudio,
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),

          if (_isLoadingRoute)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(color: Color(0xFF38BDF8)),
              ),
            ),
        ],
      ),
    );
  }
}
