import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

const ryadomRemoteCursorColor = Color(0xffff8a1c);

class RyadomRemoteCursor extends StatefulWidget {
  const RyadomRemoteCursor(
      {super.key,
      required this.position,
      required this.image,
      required this.x,
      required this.y,
      required this.scale});
  final Offset position;
  final ui.Image? image;
  final double x, y, scale;

  @override
  State<RyadomRemoteCursor> createState() => _RemoteCursorState();
}

class _RemoteCursorState extends State<RyadomRemoteCursor> {
  Timer? _idle;
  bool _visible = true;

  void _moved() {
    _idle?.cancel();
    _visible = true;
    _idle = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _visible = false);
    });
  }

  @override
  void initState() {
    super.initState();
    _moved();
  }

  @override
  void didUpdateWidget(covariant RyadomRemoteCursor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.position != oldWidget.position) _moved();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
      painter: _visible
          ? RyadomRemoteCursorPainter(
              image: widget.image,
              x: widget.x,
              y: widget.y,
              scale: widget.scale)
          : null);

  @override
  void dispose() {
    _idle?.cancel();
    super.dispose();
  }
}

class RyadomRemoteCursorPainter extends CustomPainter {
  const RyadomRemoteCursorPainter(
      {required this.image,
      required this.x,
      required this.y,
      required this.scale});
  final ui.Image? image;
  final double x, y, scale;
  @override
  void paint(Canvas canvas, Size size) {
    final shape = image;
    if (shape == null ||
        !x.isFinite ||
        !y.isFinite ||
        !scale.isFinite ||
        scale <= 0) return;
    final position = Offset(x.truncateToDouble(), y.truncateToDouble());
    final paint = Paint()
      ..filterQuality = scale == 1 ? FilterQuality.none : FilterQuality.high;
    canvas.save();
    canvas.scale(scale);
    paint.colorFilter = const ColorFilter.mode(Colors.white, BlendMode.srcIn);
    final edge = 1 / scale;
    for (final offset in [
      Offset(-edge, 0),
      Offset(edge, 0),
      Offset(0, -edge),
      Offset(0, edge)
    ]) {
      canvas.drawImage(shape, position + offset, paint);
    }
    paint.colorFilter =
        const ColorFilter.mode(ryadomRemoteCursorColor, BlendMode.srcIn);
    canvas.drawImage(shape, position, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant RyadomRemoteCursorPainter oldDelegate) =>
      image != oldDelegate.image ||
      x != oldDelegate.x ||
      y != oldDelegate.y ||
      scale != oldDelegate.scale;
}
