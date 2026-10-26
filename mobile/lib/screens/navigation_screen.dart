import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../models/navigation_models.dart';
import '../services/api_service.dart';
import '../services/ble_service.dart';
import '../services/tts_service.dart';
import '../widgets/camera_ocr_overlay.dart';
import '../widgets/direction_hud.dart';
import 'ble_setup_screen.dart';

/// Core Navigation Screen integrating Camera OCR, TTS Voice Guidance, and BLE Haptics
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

  // Subscriptions
  StreamSubscription<String>? _hazardSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeServices();
    _loadDestinationNodes();
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
      });
    }
  }

  Future<void> _initializeCamera() async {
    try {
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
    // Throttle OCR to run at ~2 FPS to prevent thermal throttling and maintain 60fps UI
    final now = DateTime.now();
    if (now.difference(_lastOcrScanTime).inMilliseconds < 600 || _isProcessingOcrFrame) {
      return;
    }

    _isProcessingOcrFrame = true;
    _lastOcrScanTime = now;

    try {
      final inputImage = _inputImageFromCameraImage(image);
      if (inputImage == null) return;

      final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);

      for (final block in recognizedText.blocks) {
        final text = block.text.trim().toUpperCase();

        // Check if detected text matches any known room or corridor landmark
        for (final node in _availableNodes) {
          final isMatch = node.signs.any((sign) => text.contains(sign.toUpperCase())) ||
              text.contains(node.label.toUpperCase()) ||
              text.contains(node.id.toUpperCase());

          if (isMatch && text != _detectedAnchorSign) {
            debugPrint('[OCR MATCH] Anchored to sign: "$text" (Node: ${node.id})');
            if (mounted) {
              setState(() {
                _detectedAnchorSign = text;
              });
            }

            // Speak landmark confirmation
            _tts.speak('Sign detected: ${node.label}.');

            // If sign matches next destination landmark, advance or re-anchor
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
    // Check if sign matches our arrival destination
    if (matchedNode.label.toLowerCase().contains(_selectedDestination.toLowerCase()) ||
        matchedNode.id.toLowerCase().contains(_selectedDestination.toLowerCase())) {
      _tts.speakUrgent('You have arrived at your destination: ${matchedNode.label}');
      _ble.sendCommand('S'); // Send stop haptic pulse
    }
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    if (_cameraController == null) return null;
    final camera = _cameraController!.description;
    final sensorOrientation = camera.sensorOrientation;

    final bytes = _concatenatePlanes(image.planes);
    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: InputImageRotationValue.fromRawValue(sensorOrientation) ?? InputImageRotation.rotation0deg,
        format: InputImageFormatValue.fromRawValue(image.format.raw) ?? InputImageFormat.nv21,
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );
  }

  Uint8List _concatenatePlanes(List<Plane> planes) {
    final WriteBuffer allBytes = WriteBuffer();
    for (final Plane plane in planes) {
      allBytes.putUint8List(plane.bytes);
    }
    return allBytes.done().buffer.asUint8List();
  }

  /// Queries the FastAPI backend router for an accessible path
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

        // Announce first navigation directive
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
            content: Text('Route calculation error: $e'),
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

    final step = _activeRoute!.steps[_currentStepIndex];
    _tts.speak(step.instruction);
    _ble.sendCommand(step.bleCommand);
  }

  void _previousStep() {
    if (_currentStepIndex <= 0 || _activeRoute == null) return;

    setState(() {
      _currentStepIndex--;
    });

    final step = _activeRoute!.steps[_currentStepIndex];
    _tts.speak(step.instruction);
    _ble.sendCommand(step.bleCommand);
  }

  void _repeatAudio() {
    if (_activeRoute != null && _activeRoute!.steps.isNotEmpty) {
      final step = _activeRoute!.steps[_currentStepIndex];
      _tts.speak(step.instruction);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    _textRecognizer.close();
    _hazardSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final step = (_activeRoute != null && _activeRoute!.steps.isNotEmpty)
        ? _activeRoute!.steps[_currentStepIndex]
        : null;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('NAVIA Indoor Guidance', style: TextStyle(fontWeight: FontWeight.w800)),
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        actions: [
          // Wearable setup button with connection indicator
          ValueListenableBuilder<bool>(
            valueListenable: _ble.isConnectedNotifier,
            builder: (context, connected, _) {
              return IconButton(
                icon: Icon(
                  connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                  color: connected ? const Color(0xFF10B981) : const Color(0xFFF43F5E),
                ),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const BleSetupScreen()),
                  );
                },
                tooltip: 'Wearable Haptic Setup',
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // Background Camera Stream or Simulated Hallway Feed
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
                color: const Color(0xFF090D16),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.videocam_off_outlined, color: Color(0xFF475569), size: 48),
                      const SizedBox(height: 12),
                      const Text(
                        'Live OCR Sign Recognition Active',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: () => _handleSimulatedSignDetect('Room 214'),
                        icon: const Icon(Icons.qr_code_scanner),
                        label: const Text('Simulate OCR "Room 214"'),
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF334155)),
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

          // Top Quick Settings Bar (Destination & Wheelchair Toggle)
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B).withOpacity(0.92),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.place_rounded, color: Color(0xFF38BDF8), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedDestination,
                        dropdownColor: const Color(0xFF1E293B),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                        isDense: true,
                        items: const [
                          DropdownMenuItem(value: 'Room 214', child: Text('Room 214 (Radiology)')),
                          DropdownMenuItem(value: 'Room 101', child: Text('Room 101 (Registration)')),
                          DropdownMenuItem(value: 'Room 102', child: Text('Room 102 (Pharmacy)')),
                          DropdownMenuItem(value: 'Room 201', child: Text('Room 201 (Cardiology)')),
                          DropdownMenuItem(value: 'Restroom', child: Text('Restroom L1')),
                        ],
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

                  // Wheelchair Accessibility Mode Toggle
                  IconButton(
                    icon: Icon(
                      Icons.accessible_forward,
                      color: _isWheelchairUser ? const Color(0xFF10B981) : const Color(0xFF64748B),
                    ),
                    tooltip: 'Wheelchair / Elevator Mode',
                    onPressed: () {
                      setState(() {
                        _isWheelchairUser = !_isWheelchairUser;
                      });
                      _tts.speak(_isWheelchairUser ? 'Wheelchair mode enabled: Avoiding stairs.' : 'Wheelchair mode disabled.');
                      _fetchRoute();
                    },
                  ),
                ],
              ),
            ),
          ),

          // Bottom Turn HUD
          Positioned(
            bottom: 12,
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

  void _handleSimulatedSignDetect(String sign) {
    setState(() {
      _detectedAnchorSign = sign;
    });
    _tts.speak('Anchored to detected sign: $sign');
    _handleAnchorSignMatched(NavNode(id: 'L2_ROOM_214', label: 'Room 214', floor: 2, x: 20, y: 8, type: 'room'));
  }
}
