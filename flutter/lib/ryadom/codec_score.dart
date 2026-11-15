import 'dart:math' as math;

class CodecMeasurement {
  const CodecMeasurement(
      this.codec, this.fps, this.delayMs, this.bytesPerSecond,
      {this.fullColor = false});
  final String codec;
  final double fps, delayMs, bytesPerSecond;
  final bool fullColor;
  bool get usable =>
      fps.isFinite &&
      fps >= 3 &&
      delayMs.isFinite &&
      delayMs >= 0 &&
      bytesPerSecond.isFinite;
  double get score =>
      math.min(fps, 60) * 4 -
      math.min(delayMs, 1000) * .08 -
      math.max(0, bytesPerSecond) / (1024 * 1024) * 2 +
      (fullColor ? 4 : 0);
}

CodecMeasurement? chooseMeasuredCodec(Iterable<CodecMeasurement> trials) {
  CodecMeasurement? best;
  for (final trial in trials) {
    if (trial.usable && (best == null || trial.score > best.score)) {
      best = trial;
    }
  }
  return best;
}
