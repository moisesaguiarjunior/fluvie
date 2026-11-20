/// @docImport 'package:fluvie/src/core/audio/band_table.dart';
library;

import 'package:flutter/widgets.dart' show BuildContext, MediaQuery, Size;
import 'package:fluvie/src/animation/runtime/noise_scope.dart';
import 'package:fluvie/src/animation/runtime/reactive_scope.dart';
import 'package:fluvie/src/composition/runtime/aspect_scope.dart';
import 'package:fluvie/src/composition/runtime/frame_scene_scope.dart';
import 'package:fluvie/src/core/anchor.dart';
import 'package:fluvie/src/core/aspect.dart';
import 'package:fluvie/src/core/audio_band.dart';
import 'package:fluvie/src/core/errors/fluvie_render_exception.dart';
import 'package:fluvie/src/rendering/runtime/frame_provider.dart';
import 'package:fluvie/src/rendering/runtime/render_mode_context.dart';
import 'package:fluvie/src/timing/time_scope_data.dart';
import 'package:fluvie/src/timing/time_scope_provider.dart';
import 'package:meta/meta.dart';

/// The resolved render state a `FrameBuilder` paints from: the
/// frame clock and element window, canvas and aspect, deterministic seed and
/// noise source, and the analysed audio bands.
///
/// Every value is read from the same scopes the rest of Fluvie reads — the
/// [FrameProvider] clock, the enclosing [TimeScopeData], the [NoiseScope],
/// and the [ReactiveScope] band tables — so a builder stays
/// deterministic: the frame is the only clock and noise/audio are precomputed,
/// never live. It is `@experimental` alongside `FrameBuilder` itself.
///
/// [audio] / [audioBand] read the analysed audio bands. They mirror
/// the `ReactiveEffect` discipline: in capture without a precomputed
/// [ReactiveScope] they throw a [FluvieRenderException] naming the band and the
/// precompute pass; in a live preview they return `0` so a builder still runs.
@experimental
final class FrameContext {
  /// Wraps the [BuildContext] of the `FrameBuilder` so the builder can read the
  /// frame clock, scope, noise, and audio through one handle.
  FrameContext(this._context);

  final BuildContext _context;

  /// The absolute video frame this build is for (the [FrameProvider] clock).
  int get frame => FrameProvider.of(_context).frame;

  /// The enclosing time scope — exposes `fps`, `startFrame`, `durationFrames`.
  TimeScopeData get scope => TimeScopeProvider.of(_context);

  /// The frames-per-second of the enclosing scope.
  int get fps => scope.fps;

  /// Elapsed time from frame zero. Rounds up to the first whole microsecond
  /// at or after the frame's start, so indexing that instant at [fps] selects
  /// this frame when the frame lasts at least one microsecond.
  ///
  /// A faster clock can share one [Duration] across frames. Read [frame] then.
  /// Throws an [ArgumentError] when [fps] is not positive, and a [RangeError]
  /// when the result cannot fit in a [Duration].
  Duration get time {
    if (fps <= 0) {
      throw ArgumentError.value(fps, 'fps', 'must be positive');
    }
    final numerator = BigInt.from(frame) * BigInt.from(Duration.microsecondsPerSecond);
    final divisor = BigInt.from(fps);
    final microseconds = (numerator + divisor - BigInt.one) ~/ divisor;
    if (!microseconds.isValidInt) {
      throw RangeError('The time of frame $frame at $fps fps is too large.');
    }
    return Duration(microseconds: microseconds.toInt());
  }

  /// The capture canvas in pixels, or the enclosing video's authored size in
  /// preview. A standalone builder uses the inherited view size if available.
  Size get size {
    final scene = FrameSceneScope.maybeOf(_context);
    return scene?.captureSize ??
        scene?.compositionSize ??
        MediaQuery.maybeSizeOf(_context) ??
        Size.zero;
  }

  /// The active layout variant, using the same fallback as [AspectScope].
  Aspect get aspect => AspectScope.of(_context);

  /// The seed declared on the enclosing video, or zero for a standalone
  /// builder. Use it to seed your own materials and painters.
  int get seed => FrameSceneScope.maybeOf(_context)?.seed ?? 0;

  /// Progress `0..1` across this element's resolved window: the frames elapsed
  /// since the scope began over its `durationFrames`, clamped. A zero-length
  /// window reads `1`.
  double get progress {
    final window = scope.durationFrames;
    if (window <= 0) return 1;
    return ((frame - scope.startFrame) / window).clamp(0.0, 1.0);
  }

  /// The seeded noise scalar in `[0, 1]` for [seed] — the same source the
  /// effects read, so `ctx.noise('petal-$i')` and a `grain`/`particles`
  /// effect agree. Defaults to the const `ValueNoise` with no [NoiseScope].
  double noise(String seed) => NoiseScope.of(_context).valueForSeed(seed);

  /// The analysed bass energy of [track] (or the master mix when `null`) at the
  /// current frame — the headline reactive value.
  double audio(Anchor? track) => audioBand(track, AudioBand.bass);

  /// The analysed energy of [band] on [track] (or the master mix when `null`)
  /// at the current frame, read from the precomputed [ReactiveScope].
  ///
  /// Throws a [FluvieRenderException] in capture without a scope (a determinism
  /// violation); returns `0` in a live preview.
  double audioBand(Anchor? track, AudioBand band) {
    final table = ReactiveScope.tableFor(_context, track);
    if (table == null) {
      if (RenderModeContext.isCapture(_context)) {
        throw FluvieRenderException(
          'ctx.audioBand(AudioBand.${band.name}) cannot render in capture '
          'without a precomputed BandTable. Mount a ReactiveScope and analyse '
          'the audio track in the precompute pass before the frame loop.',
        );
      }
      return 0;
    }
    return table.energyAt(frame, band);
  }
}
