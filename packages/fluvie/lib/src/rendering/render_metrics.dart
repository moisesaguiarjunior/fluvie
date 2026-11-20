/// Elapsed-time summary for one render stage.
///
/// [mean] is the sum of the sample microseconds divided by [samples],
/// truncated toward zero. [p95] is the sample at
/// `ceil(95 * samples / 100) - 1` after sorting ascending. The rank uses
/// integer arithmetic. One sample makes [minimum], [mean], [p95], and
/// [maximum] equal that sample. Zero samples make every duration
/// [Duration.zero].
final class StageTiming {
  /// Creates a summary that already has its rank statistics.
  const StageTiming({
    required this.samples,
    required this.minimum,
    required this.mean,
    required this.p95,
    required this.maximum,
  });

  /// Builds the summary from raw sample durations in microseconds.
  ///
  /// The input order is the order the stage ran. Ranking sorts a copy.
  factory StageTiming.fromMicroseconds(List<int> microseconds) {
    if (microseconds.isEmpty) return empty;
    final sorted = [...microseconds]..sort();
    final count = sorted.length;
    var sum = 0;
    for (final sample in sorted) {
      sum += sample;
    }
    final rank = ((95 * count + 99) ~/ 100) - 1;
    final index = rank < 0 ? 0 : (rank >= count ? count - 1 : rank);
    return StageTiming(
      samples: count,
      minimum: Duration(microseconds: sorted.first),
      mean: Duration(microseconds: sum ~/ count),
      p95: Duration(microseconds: sorted[index]),
      maximum: Duration(microseconds: sorted.last),
    );
  }

  /// A stage that did not run.
  static const empty = StageTiming(
    samples: 0,
    minimum: Duration.zero,
    mean: Duration.zero,
    p95: Duration.zero,
    maximum: Duration.zero,
  );

  /// How many times the stage ran.
  final int samples;

  /// The shortest sample.
  final Duration minimum;

  /// The truncated mean sample.
  final Duration mean;

  /// The 95th-percentile sample.
  final Duration p95;

  /// The longest sample.
  final Duration maximum;

  @override
  String toString() =>
      'StageTiming(samples: $samples, minimum: $minimum, mean: $mean, p95: $p95, maximum: $maximum)';
}

/// Optional timing report for one render.
///
/// Pass one instance into a capture or render entry. The pipeline fills it.
/// Omit it and that entry allocates no stopwatch and no sample list. The
/// captured pixels do not depend on whether a report is present.
///
/// Durations are wall-clock samples. Tests should read [frameCount], the cache
/// counters, and [StageTiming.samples], and should compare pixels with the
/// report on and off. They should not expect a particular number of
/// milliseconds.
final class RenderMetrics {
  final List<int> _preparation = [];
  final List<int> _mounting = [];
  final List<int> _pumping = [];
  final List<int> _readback = [];
  final List<int> _encoding = [];
  int _frameCount = 0;
  int _cacheHits = 0;
  int _cacheMisses = 0;

  /// Frames consumed by the capture loop, or one after a still capture.
  int get frameCount => _frameCount;

  /// Frames whose pixels came from a valid cache entry.
  ///
  /// Stays zero when the frame cache is off. A hit still pumps the frame and
  /// does not add a readback sample.
  int get cacheHits => _cacheHits;

  /// Frames captured because the cache was on and had no valid entry.
  ///
  /// A cached buffer whose length is not the frame size counts as a miss.
  /// Stays zero when the frame cache is off.
  int get cacheMisses => _cacheMisses;

  /// Media pre-resolution and the clip window warmed before the tree mounts.
  StageTiming get preparation => StageTiming.fromMicroseconds(_preparation);

  /// The call that mounts the capture tree.
  StageTiming get mounting => StageTiming.fromMicroseconds(_mounting);

  /// One sample per pumped frame, including frames served from the cache.
  ///
  /// A still capture with `stepThrough` also counts each intermediate pump.
  /// Those pumps can outnumber [frameCount], which counts the consumed frame.
  StageTiming get pumping => StageTiming.fromMicroseconds(_pumping);

  /// One sample per pixel readback.
  ///
  /// Cache hits do not add a sample. Looking up the cache is not a readback.
  StageTiming get readback => StageTiming.fromMicroseconds(_readback);

  /// Encoder invocations. Empty for a capture that does not encode.
  StageTiming get encoding => StageTiming.fromMicroseconds(_encoding);

  /// Records one preparation sample.
  void addPreparation(Duration elapsed) => _preparation.add(elapsed.inMicroseconds);

  /// Records one mounting sample.
  void addMounting(Duration elapsed) => _mounting.add(elapsed.inMicroseconds);

  /// Records one frame-pump sample.
  void addPumping(Duration elapsed) => _pumping.add(elapsed.inMicroseconds);

  /// Records one pixel-readback sample.
  void addReadback(Duration elapsed) => _readback.add(elapsed.inMicroseconds);

  /// Records one encoding sample.
  void addEncoding(Duration elapsed) => _encoding.add(elapsed.inMicroseconds);

  /// Counts one consumed frame.
  void addFrame() => _frameCount++;

  /// Counts one cache hit.
  void addCacheHit() => _cacheHits++;

  /// Counts one cache miss.
  void addCacheMiss() => _cacheMisses++;

  @override
  String toString() =>
      'RenderMetrics(frames: $frameCount, hits: $cacheHits, misses: $cacheMisses, '
      'preparation: $preparation, mounting: $mounting, pumping: $pumping, '
      'readback: $readback, encoding: $encoding)';
}

/// Runs [body] and, when [metrics] is set, records one sample through [record].
///
/// A null report runs [body] and does not start a stopwatch. The returned
/// value is whatever [body] returns.
Future<T> timeStage<T>(
  RenderMetrics? metrics,
  void Function(RenderMetrics metrics, Duration elapsed) record,
  Future<T> Function() body,
) async {
  if (metrics == null) return body();
  final watch = Stopwatch()..start();
  try {
    return await body();
  } finally {
    watch.stop();
    record(metrics, watch.elapsed);
  }
}
