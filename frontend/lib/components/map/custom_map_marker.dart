import 'dart:math';
import 'package:flutter/material.dart';

class CustomMapMarker extends StatelessWidget {
  final String pinColorHex;
  final String pinStyle;
  final String pinIconType;
  final String? pinEmoji;
  final String? profileImageUrl;
  final String initials;
  final VoidCallback? onTap;
  final String? semanticsLabel;

  const CustomMapMarker({
    super.key,
    required this.pinColorHex,
    required this.pinStyle,
    required this.pinIconType,
    this.pinEmoji,
    this.profileImageUrl,
    this.initials = '',
    this.onTap,
    this.semanticsLabel,
  });

  Color _parseColor(String hexColor) {
    String hex = hexColor.replaceAll('#', '');
    if (hex.length == 6) {
      hex = 'FF$hex'; // Add alpha if missing
    }
    return Color(int.parse('0x$hex'));
  }

  Widget _buildInnerContent() {
    switch (pinIconType) {
      case 'emoji':
        return Text(
          pinEmoji ?? '',
          style: const TextStyle(fontSize: 16),
          textAlign: TextAlign.center,
        );
      case 'initials':
        return Text(
          initials.toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
          textAlign: TextAlign.center,
        );
      case 'picture':
        if (profileImageUrl != null) {
          return CircleAvatar(
            radius: 12,
            backgroundImage: NetworkImage(profileImageUrl!),
          );
        }
        return const Icon(Icons.person, size: 20, color: Colors.white);
      case 'none':
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildShape(Color color, Widget innerContent) {
    const double size = 36.0;

    switch (pinStyle) {
      case 'circle':
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: innerContent,
        );
      case 'square':
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: innerContent,
        );
      case 'diamond':
        return Transform.rotate(
          angle: pi / 4,
          child: Container(
            width: size * 0.8,
            height: size * 0.8,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Transform.rotate(angle: -pi / 4, child: innerContent),
          ),
        );
      case 'triangle':
        return CustomPaint(
          size: const Size(size, size),
          painter: TrianglePainter(color: color),
          child: SizedBox(
            width: size,
            height: size,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: innerContent,
              ),
            ),
          ),
        );
      case 'teardrop':
      default:
        return Transform.rotate(
          angle: pi / 4,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: color,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(size / 2),
                topRight: Radius.circular(size / 2),
                bottomLeft: Radius.circular(size / 2),
                bottomRight: Radius.circular(4),
              ),
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 4,
                  offset: Offset(2, 2),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Transform.rotate(angle: -pi / 4, child: innerContent),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _parseColor(pinColorHex);
    final innerContent = _buildInnerContent();

    return Semantics(
      label: semanticsLabel,
      button: onTap != null,
      child: GestureDetector(
        onTap: onTap,
        child: _buildShape(color, innerContent),
      ),
    );
  }
}

class TrianglePainter extends CustomPainter {
  final Color color;

  TrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawShadow(path, Colors.black, 4, false);
    canvas.drawPath(path, paint);
    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(covariant TrianglePainter oldDelegate) =>
      color != oldDelegate.color;
}
