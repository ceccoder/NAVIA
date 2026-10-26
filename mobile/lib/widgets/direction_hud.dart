import 'package:flutter/material.dart';
import '../models/navigation_models.dart';

/// Accessible High-Contrast Directional Heads-Up Display (HUD)
class DirectionHud extends StatelessWidget {
  final NavigationStep? currentStep;
  final int currentStepIndex;
  final int totalSteps;
  final String? obstacleWarning;
  final bool isBleConnected;
  final String lastBleCommand;
  final VoidCallback onNextStep;
  final VoidCallback onPreviousStep;
  final VoidCallback onRepeatAudio;

  const DirectionHud({
    super.key,
    required this.currentStep,
    required this.currentStepIndex,
    required this.totalSteps,
    required this.obstacleWarning,
    required this.isBleConnected,
    required this.lastBleCommand,
    required this.onNextStep,
    required this.onPreviousStep,
    required this.onRepeatAudio,
  });

  IconData _getTurnIcon(String turnType) {
    switch (turnType) {
      case 'LEFT':
        return Icons.turn_left_rounded;
      case 'RIGHT':
        return Icons.turn_right_rounded;
      case 'STRAIGHT':
        return Icons.straight_rounded;
      case 'ELEVATOR_UP':
      case 'ELEVATOR_DOWN':
        return Icons.elevator_rounded;
      case 'STAIRS_UP':
      case 'STAIRS_DOWN':
        return Icons.stairs_rounded;
      case 'ARRIVE':
        return Icons.check_circle_rounded;
      default:
        return Icons.navigation_rounded;
    }
  }

  Color _getTurnColor(String turnType) {
    switch (turnType) {
      case 'LEFT':
        return const Color(0xFF38BDF8); // Bright Cyan
      case 'RIGHT':
        return const Color(0xFF818CF8); // Indigo
      case 'STRAIGHT':
        return const Color(0xFF34D399); // Emerald Green
      case 'ELEVATOR_UP':
      case 'ELEVATOR_DOWN':
        return const Color(0xFFFBBF24); // Amber
      case 'ARRIVE':
        return const Color(0xFF10B981); // Solid Green
      default:
        return const Color(0xFF38BDF8);
    }
  }

  @override
  Widget build(BuildContext context) {
    final step = currentStep;
    final hasObstacle = obstacleWarning != null && obstacleWarning!.isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Real-time Obstacle Warning Banner
        if (hasObstacle)
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFDC2626), // Urgent Red
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66DC2626),
                  blurRadius: 16,
                  spreadRadius: 2,
                )
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 36),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'PROXIMITY WARNING (< 70cm)',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.1,
                        ),
                      ),
                      Text(
                        obstacleWarning!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        // Main Turn Card
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B).withOpacity(0.95), // Deep Slate
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFF334155), width: 1.5),
            boxShadow: const [
              BoxShadow(
                color: Colors.black45,
                blurRadius: 20,
                offset: Offset(0, 8),
              )
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row: Status badges & Step count
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF475569)),
                    ),
                    child: Text(
                      'STEP ${currentStepIndex + 1} OF ${totalSteps == 0 ? 1 : totalSteps}',
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),

                  // Wearable Haptic Feedback Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isBleConnected ? const Color(0x2210B981) : const Color(0x22F43F5E),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isBleConnected ? const Color(0xFF10B981) : const Color(0xFFF43F5E),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isBleConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                          color: isBleConnected ? const Color(0xFF10B981) : const Color(0xFFF43F5E),
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isBleConnected ? 'WEARABLE: CMD "$lastBleCommand"' : 'WEARABLE OFFLINE',
                          style: TextStyle(
                            color: isBleConnected ? const Color(0xFF10B981) : const Color(0xFFF43F5E),
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              // Direction Icon and Instruction Text
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: step != null
                          ? _getTurnColor(step.turnType).withOpacity(0.18)
                          : const Color(0xFF334155),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: step != null ? _getTurnColor(step.turnType) : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      step != null ? _getTurnIcon(step.turnType) : Icons.navigation_rounded,
                      color: step != null ? _getTurnColor(step.turnType) : Colors.white70,
                      size: 38,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          step?.instruction ?? 'Acquiring route and signs...',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                          ),
                        ),
                        if (step != null && step.distanceMeters > 0) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Distance: ${step.distanceMeters.toStringAsFixed(1)} m  •  Floor ${step.floor}',
                            style: const TextStyle(
                              color: Color(0xFF38BDF8),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              // Control Actions (Next, Previous, Repeat Audio)
              Row(
                children: [
                  IconButton.filledTonal(
                    onPressed: currentStepIndex > 0 ? onPreviousStep : null,
                    icon: const Icon(Icons.arrow_back),
                    tooltip: 'Previous Step',
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF334155),
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: onRepeatAudio,
                    icon: const Icon(Icons.volume_up_rounded),
                    tooltip: 'Repeat Voice Instruction',
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF0284C7),
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: currentStepIndex < totalSteps - 1 ? onNextStep : null,
                      icon: const Icon(Icons.arrow_forward_rounded),
                      label: Text(
                        currentStepIndex >= totalSteps - 1 ? 'ARRIVED' : 'NEXT STEP',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
