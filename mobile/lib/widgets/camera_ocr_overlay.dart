import 'package:flutter/material.dart';

/// Overlay displaying the camera viewfinder reticle and detected OCR text badges
class CameraOcrOverlay extends StatelessWidget {
  final String? recognizedSign;
  final bool isProcessingOcr;

  const CameraOcrOverlay({
    super.key,
    required this.recognizedSign,
    required this.isProcessingOcr,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Viewfinder targeting frame
        Center(
          child: Container(
            width: 280,
            height: 180,
            decoration: BoxDecoration(
              border: Border.all(
                color: recognizedSign != null ? const Color(0xFF10B981) : Colors.white54,
                width: 2.5,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Stack(
              children: [
                // Top-left corner accent
                Positioned(
                  top: 0,
                  left: 0,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: recognizedSign != null ? const Color(0xFF10B981) : const Color(0xFF38BDF8), width: 5),
                        left: BorderSide(color: recognizedSign != null ? const Color(0xFF10B981) : const Color(0xFF38BDF8), width: 5),
                      ),
                    ),
                  ),
                ),
                // Top-right corner accent
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: recognizedSign != null ? const Color(0xFF10B981) : const Color(0xFF38BDF8), width: 5),
                        right: BorderSide(color: recognizedSign != null ? const Color(0xFF10B981) : const Color(0xFF38BDF8), width: 5),
                      ),
                    ),
                  ),
                ),
                // Center scanning line animation or text
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.document_scanner_rounded,
                        color: recognizedSign != null ? const Color(0xFF10B981) : Colors.white38,
                        size: 32,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isProcessingOcr ? 'Scanning Signs & Braille...' : 'Point Camera at Room Signs',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.85),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          backgroundColor: Colors.black45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // Recognized OCR Sign Anchor Notification Badge
        if (recognizedSign != null && recognizedSign!.isNotEmpty)
          Positioned(
            top: 20,
            left: 20,
            right: 20,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A).withOpacity(0.92),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: const Color(0xFF10B981), width: 1.5),
                  boxShadow: const [
                    BoxShadow(color: Color(0x6610B981), blurRadius: 12, spreadRadius: 1)
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'ANCHOR MATCHED: "$recognizedSign"',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
