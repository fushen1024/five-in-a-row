import 'dart:math';
import 'package:flutter/material.dart';
import '../domain/game.dart';

class Board extends StatelessWidget {
  final Game game;
  final bool enabled;
  final void Function(int, int) onPlace;
  const Board({
    super.key,
    required this.game,
    required this.enabled,
    required this.onPlace,
  });
  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 1,
    child: Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x243C2B15),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final side = constraints.maxWidth;
            final step = side / 16;
            return Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(painter: BoardPainter(game)),
                ),
                for (var y = 0; y < Game.size; y++)
                  for (var x = 0; x < Game.size; x++)
                    Positioned(
                      left: step * (x + .5),
                      top: step * (y + .5),
                      width: step,
                      height: step,
                      child: Semantics(
                        button: true,
                        enabled: enabled && game.at(x, y) == 0,
                        label:
                            '第${x + 1}列第${y + 1}行，${['空位', '黑子', '白子'][game.at(x, y)]}',
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: enabled && game.at(x, y) == 0
                              ? () => onPlace(x, y)
                              : null,
                        ),
                      ),
                    ),
              ],
            );
          },
        ),
      ),
    ),
  );
}

class BoardPainter extends CustomPainter {
  final Game game;
  BoardPainter(this.game);
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 16;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEED3A1), Color(0xFFE6BF84), Color(0xFFF1D7AA)],
        ).createShader(Offset.zero & size),
    );
    final grain = Paint()
      ..color = const Color(0x0B825B2C)
      ..strokeWidth = .8;
    for (var i = 0; i < 100; i++) {
      final y = size.height * i / 100;
      final path = Path()
        ..moveTo(0, y)
        ..cubicTo(
          size.width * .3,
          y + sin(i) * 7,
          size.width * .7,
          y - cos(i) * 5,
          size.width,
          y + sin(i * 2) * 3,
        );
      canvas.drawPath(path, grain..style = PaintingStyle.stroke);
    }
    final grid = Paint()
      ..color = const Color(0x88795835)
      ..strokeWidth = .65;
    for (var i = 1; i <= 15; i++) {
      canvas.drawLine(Offset(s, s * i), Offset(s * 15, s * i), grid);
      canvas.drawLine(Offset(s * i, s), Offset(s * i, s * 15), grid);
    }
    for (final p in [(4, 4), (12, 4), (8, 8), (4, 12), (12, 12)]) {
      canvas.drawCircle(
        Offset(s * p.$1, s * p.$2),
        2.5,
        Paint()..color = const Color(0xFF826138),
      );
    }
    for (var y = 0; y < 15; y++) {
      for (var x = 0; x < 15; x++) {
        final stone = game.at(x, y);
        if (stone == 0) continue;
        final center = Offset(s * (x + 1), s * (y + 1)), r = s * .44;
        canvas.drawCircle(
          center + Offset(0, s * .09),
          r,
          Paint()
            ..color = const Color(0x55402C16)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * .08),
        );
        canvas.drawCircle(
          center,
          r,
          Paint()
            ..shader = RadialGradient(
              center: const Alignment(-.45, -.55),
              radius: 1,
              colors: stone == 1
                  ? [const Color(0xFF5D6261), const Color(0xFF121916)]
                  : [Colors.white, const Color(0xFFD8D9CF)],
            ).createShader(Rect.fromCircle(center: center, radius: r)),
        );
        if (game.moves.isNotEmpty && game.moves.last == (x, y)) {
          canvas.drawCircle(
            center,
            r * .17,
            Paint()..color = const Color(0xFFD5A348),
          );
        }
      }
    }
    if (game.winningCells.isNotEmpty) {
      final a = game.winningCells.first, b = game.winningCells.last;
      canvas.drawLine(
        Offset((a.$1 + 1) * s, (a.$2 + 1) * s),
        Offset((b.$1 + 1) * s, (b.$2 + 1) * s),
        Paint()
          ..color = const Color(0xFFE1AB46)
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant BoardPainter oldDelegate) => true;
}
