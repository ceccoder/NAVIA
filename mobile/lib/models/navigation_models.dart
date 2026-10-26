/// Data models for the NAVIA indoor navigation system.

class UserProfile {
  final bool wheelchairUser;
  final bool visuallyImpaired;
  final double minDoorWidth;
  final bool avoidStairs;
  final double walkingSpeedMps;

  const UserProfile({
    this.wheelchairUser = false,
    this.visuallyImpaired = true,
    this.minDoorWidth = 0.8,
    this.avoidStairs = false,
    this.walkingSpeedMps = 1.0,
  });

  Map<String, dynamic> toJson() => {
        'wheelchair_user': wheelchairUser,
        'visually_impaired': visuallyImpaired,
        'min_door_width': minDoorWidth,
        'avoid_stairs': avoidStairs,
        'walking_speed_mps': walkingSpeedMps,
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        wheelchairUser: json['wheelchair_user'] as bool? ?? false,
        visuallyImpaired: json['visually_impaired'] as bool? ?? true,
        minDoorWidth: (json['min_door_width'] as num?)?.toDouble() ?? 0.8,
        avoidStairs: json['avoid_stairs'] as bool? ?? false,
        walkingSpeedMps: (json['walking_speed_mps'] as num?)?.toDouble() ?? 1.0,
      );
}

class RouteRequest {
  final String buildingId;
  final String startNodeId;
  final String destinationLabel;
  final UserProfile userProfile;

  const RouteRequest({
    this.buildingId = 'campus_med_center',
    required this.startNodeId,
    required this.destinationLabel,
    this.userProfile = const UserProfile(),
  });

  Map<String, dynamic> toJson() => {
        'building_id': buildingId,
        'start_node_id': startNodeId,
        'destination_label': destinationLabel,
        'user_profile': userProfile.toJson(),
      };
}

class NavigationStep {
  final int stepIndex;
  final String fromNode;
  final String toNode;
  final String instruction;
  final String turnType; // STRAIGHT, LEFT, RIGHT, ELEVATOR_UP, ELEVATOR_DOWN, STAIRS_UP, STAIRS_DOWN, ARRIVE
  final String bleCommand; // 'L', 'R', 'S', 'F'
  final double distanceMeters;
  final int floor;
  final String? landmarkHint;

  const NavigationStep({
    required this.stepIndex,
    required this.fromNode,
    required this.toNode,
    required this.instruction,
    required this.turnType,
    required this.bleCommand,
    required this.distanceMeters,
    required this.floor,
    this.landmarkHint,
  });

  factory NavigationStep.fromJson(Map<String, dynamic> json) => NavigationStep(
        stepIndex: json['step_index'] as int? ?? 0,
        fromNode: json['from_node'] as String? ?? '',
        toNode: json['to_node'] as String? ?? '',
        instruction: json['instruction'] as String? ?? '',
        turnType: json['turn_type'] as String? ?? 'STRAIGHT',
        bleCommand: json['ble_command'] as String? ?? 'F',
        distanceMeters: (json['distance_meters'] as num?)?.toDouble() ?? 0.0,
        floor: json['floor'] as int? ?? 1,
        landmarkHint: json['landmark_hint'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'step_index': stepIndex,
        'from_node': fromNode,
        'to_node': toNode,
        'instruction': instruction,
        'turn_type': turnType,
        'ble_command': bleCommand,
        'distance_meters': distanceMeters,
        'floor': floor,
        'landmark_hint': landmarkHint,
      };
}

class RouteResponse {
  final String buildingId;
  final String startNodeId;
  final String destinationNodeId;
  final String destinationLabel;
  final double totalDistanceMeters;
  final int estimatedTimeSeconds;
  final bool accessible;
  final List<String> routeNodes;
  final List<NavigationStep> steps;

  const RouteResponse({
    required this.buildingId,
    required this.startNodeId,
    required this.destinationNodeId,
    required this.destinationLabel,
    required this.totalDistanceMeters,
    required this.estimatedTimeSeconds,
    required this.accessible,
    required this.routeNodes,
    required this.steps,
  });

  factory RouteResponse.fromJson(Map<String, dynamic> json) => RouteResponse(
        buildingId: json['building_id'] as String? ?? '',
        startNodeId: json['start_node_id'] as String? ?? '',
        destinationNodeId: json['destination_node_id'] as String? ?? '',
        destinationLabel: json['destination_label'] as String? ?? '',
        totalDistanceMeters: (json['total_distance_meters'] as num?)?.toDouble() ?? 0.0,
        estimatedTimeSeconds: json['estimated_time_seconds'] as int? ?? 0,
        accessible: json['accessible'] as bool? ?? true,
        routeNodes: (json['route_nodes'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
        steps: (json['steps'] as List<dynamic>?)
                ?.map((e) => NavigationStep.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );
}

class NavNode {
  final String id;
  final String label;
  final int floor;
  final double x;
  final double y;
  final String type;
  final List<String> signs;

  const NavNode({
    required this.id,
    required this.label,
    required this.floor,
    required this.x,
    required this.y,
    required this.type,
    this.signs = const [],
  });

  factory NavNode.fromJson(Map<String, dynamic> json) => NavNode(
        id: json['id'] as String? ?? '',
        label: json['label'] as String? ?? '',
        floor: json['floor'] as int? ?? 1,
        x: (json['x'] as num?)?.toDouble() ?? 0.0,
        y: (json['y'] as num?)?.toDouble() ?? 0.0,
        type: json['type'] as String? ?? 'room',
        signs: (json['signs'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      );
}
