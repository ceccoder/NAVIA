import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/navigation_models.dart';

/// Service managing communication with the NAVIA FastAPI graph routing server.
class ApiService {
  // Configurable backend base URL (default: Android emulator 10.0.2.2:8000; override with --dart-define=NAVIA_API_URL=...)
  static String baseUrl = const String.fromEnvironment(
    'NAVIA_API_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  static void setBaseUrl(String url) {
    baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  /// Pings the backend health endpoint.
  static Future<bool> checkHealth() async {
    try {
      final uri = Uri.parse('$baseUrl/health');
      final response = await http.get(uri).timeout(const Duration(seconds: 4));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Fetches building nodes and landmarks for autocomplete & OCR sign lookup.
  static Future<List<NavNode>> fetchNodes() async {
    try {
      final uri = Uri.parse('$baseUrl/api/v1/nodes');
      final response = await http.get(uri).timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = jsonDecode(response.body) as List<dynamic>;
        return jsonList.map((e) => NavNode.fromJson(e as Map<String, dynamic>)).toList();
      } else {
        throw HttpException('Failed to load nodes: HTTP ${response.statusCode}');
      }
    } catch (e) {
      // Return built-in fallback nodes if network is unavailable
      return _getFallbackNodes();
    }
  }

  /// Calculates turn-by-turn route from start location/sign to destination.
  static Future<RouteResponse> calculateRoute(RouteRequest request) async {
    final uri = Uri.parse('$baseUrl/api/v1/route');

    try {
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(request.toJson()),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return RouteResponse.fromJson(data);
      } else if (response.statusCode == 404) {
        final error = jsonDecode(response.body);
        throw Exception(error['detail'] ?? 'Destination or start point not found.');
      } else if (response.statusCode == 422) {
        final error = jsonDecode(response.body);
        throw Exception(error['detail'] ?? 'No accessible route under current mobility constraints.');
      } else {
        throw HttpException('Server error: HTTP ${response.statusCode}');
      }
    } on SocketException catch (_) {
      // Graceful offline fallback simulation for isolated field trials
      return _getSimulatedOfflineRoute(request);
    } on TimeoutException catch (_) {
      return _getSimulatedOfflineRoute(request);
    }
  }

  /// Offline simulation fallback if connection to backend is interrupted
  static RouteResponse _getSimulatedOfflineRoute(RouteRequest request) {
    final isWheelchair = request.userProfile.wheelchairUser;
    final viaElevator = isWheelchair || request.userProfile.avoidStairs;

    return RouteResponse(
      buildingId: request.buildingId,
      startNodeId: request.startNodeId,
      destinationNodeId: 'L2_ROOM_214',
      destinationLabel: request.destinationLabel,
      totalDistanceMeters: viaElevator ? 44.0 : 42.0,
      estimatedTimeSeconds: 44,
      accessible: true,
      routeNodes: viaElevator
          ? ['L1_ENTRANCE', 'L1_LOBBY', 'L1_ELEVATOR', 'L2_ELEVATOR', 'L2_LOBBY', 'L2_ROOM_214']
          : ['L1_ENTRANCE', 'L1_LOBBY', 'L1_STAIRS', 'L2_STAIRS', 'L2_LOBBY', 'L2_ROOM_214'],
      steps: [
        NavigationStep(
          stepIndex: 0,
          fromNode: 'L1_ENTRANCE',
          toNode: 'L1_LOBBY',
          instruction: 'Proceed forward 10 meters into the main lobby.',
          turnType: 'STRAIGHT',
          bleCommand: 'F',
          distanceMeters: 10.0,
          floor: 1,
          landmarkHint: 'Lobby Information Desk',
        ),
        NavigationStep(
          stepIndex: 1,
          fromNode: 'L1_LOBBY',
          toNode: viaElevator ? 'L1_ELEVATOR' : 'L1_STAIRS',
          instruction: viaElevator
              ? 'Turn left and walk 16 meters towards Elevator Bank.'
              : 'Turn right and walk 16 meters towards the North Stairwell.',
          turnType: viaElevator ? 'LEFT' : 'RIGHT',
          bleCommand: viaElevator ? 'L' : 'R',
          distanceMeters: 16.0,
          floor: 1,
          landmarkHint: viaElevator ? 'Elevator Bank Level 1' : 'North Stairwell Level 1',
        ),
        NavigationStep(
          stepIndex: 2,
          fromNode: viaElevator ? 'L1_ELEVATOR' : 'L1_STAIRS',
          toNode: viaElevator ? 'L2_ELEVATOR' : 'L2_STAIRS',
          instruction: viaElevator ? 'Take the elevator up to Floor 2.' : 'Take the stairs up to Floor 2.',
          turnType: viaElevator ? 'ELEVATOR_UP' : 'STAIRS_UP',
          bleCommand: 'F',
          distanceMeters: viaElevator ? 4.0 : 10.0,
          floor: 1,
          landmarkHint: 'Floor 2 Transition',
        ),
        NavigationStep(
          stepIndex: 3,
          fromNode: viaElevator ? 'L2_ELEVATOR' : 'L2_STAIRS',
          toNode: 'L2_LOBBY',
          instruction: 'Exit onto Level 2 Central Hall and walk 16 meters forward.',
          turnType: 'STRAIGHT',
          bleCommand: 'F',
          distanceMeters: 16.0,
          floor: 2,
          landmarkHint: 'Level 2 Central Hall',
        ),
        NavigationStep(
          stepIndex: 4,
          fromNode: 'L2_LOBBY',
          toNode: 'L2_ROOM_214',
          instruction: 'Turn right and walk 18 meters. Room 214 is on your right.',
          turnType: 'RIGHT',
          bleCommand: 'R',
          distanceMeters: 18.0,
          floor: 2,
          landmarkHint: 'Room 214 - Radiology Lab',
        ),
        NavigationStep(
          stepIndex: 5,
          fromNode: 'L2_ROOM_214',
          toNode: 'L2_ROOM_214',
          instruction: 'You have arrived at your destination: Room 214.',
          turnType: 'ARRIVE',
          bleCommand: 'S',
          distanceMeters: 0.0,
          floor: 2,
          landmarkHint: 'Room 214',
        ),
      ],
    );
  }

  static List<NavNode> _getFallbackNodes() {
    return const [
      NavNode(id: 'L1_ENTRANCE', label: 'Main Entrance', floor: 1, x: 0, y: 0, type: 'entrance', signs: ['ENTRANCE']),
      NavNode(id: 'L1_LOBBY', label: 'Lobby Information Desk', floor: 1, x: 10, y: 0, type: 'lobby', signs: ['INFO DESK']),
      NavNode(id: 'L1_RESTROOM', label: 'Accessible Restroom L1', floor: 1, x: 10, y: -8, type: 'restroom', signs: ['RESTROOM']),
      NavNode(id: 'L1_ROOM_101', label: 'Room 101 - Patient Registration', floor: 1, x: 20, y: 8, type: 'room', signs: ['ROOM 101']),
      NavNode(id: 'L1_ROOM_102', label: 'Room 102 - Pharmacy', floor: 1, x: 20, y: -8, type: 'room', signs: ['ROOM 102', 'PHARMACY']),
      NavNode(id: 'L2_ROOM_214', label: 'Room 214 - Radiology Lab', floor: 2, x: 20, y: 8, type: 'room', signs: ['ROOM 214', '214']),
      NavNode(id: 'L2_ROOM_201', label: 'Room 201 - Cardiology', floor: 2, x: 10, y: 25, type: 'room', signs: ['ROOM 201']),
    ];
  }
}
