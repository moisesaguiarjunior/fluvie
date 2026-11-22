import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fluvie/src/audio/encoding/resolved_audio_track.dart';
import 'package:fluvie/src/audio/runtime/frame_list_beat_grid.dart';
import 'package:fluvie/src/core/audio/band_table.dart';
import 'package:fluvie/src/core/audio_band.dart';
import 'package:fluvie/src/core/contracts/beat_grid.dart';

/// Places a scene track's source analysis on the encoder's playback clock.
final class ReactiveAudioWindow {
  /// Resolves the encoder's offsets to the analysis frame rate.
  ReactiveAudioWindow(ResolvedAudioTrack track, this._frameCount, {required int fps})
    : _start = (track.delayMs * fps / 1000).round(),
      _length = (track.maxPlaybackSeconds! * fps).round(),
      _trimStart = math.max(0, ((track.trimStartSeconds ?? 0) * fps).round()),
      _trimEnd = track.trimEndSeconds == null ? null : (track.trimEndSeconds! * fps).round(),
      _loop = track.loop;

  final int _start;
  final int _length;
  final int _trimStart;
  final int? _trimEnd;
  final bool _loop;
  final int _frameCount;

  int get _playedFrames => math.max(0, math.min(_frameCount - _start, _length));

  /// Source analysis coverage required by this window.
  int get analysisFrames => math.min(
    _trimStart + _playedFrames,
    math.max(_trimStart, _trimEnd ?? _trimStart + _playedFrames),
  );

  double _sourceLength(BandTable source) {
    final available = source.sourceFrames ?? source.totalFrames.toDouble();
    return math.max(0, math.min(_trimEnd?.toDouble() ?? available, available) - _trimStart);
  }

  /// Builds composition-indexed band values, with zero energy outside playback.
  BandTable placeBands(BandTable source) {
    final sourceLength = _sourceLength(source);
    final played = _loop ? _playedFrames : math.min(_playedFrames, sourceLength.ceil());
    final bands = <AudioBand, Float64List>{};
    for (final band in AudioBand.values) {
      final energies = source.energiesFor(band);
      if (energies.isEmpty) continue;
      final aligned = Float64List(_frameCount);
      if (sourceLength > 0) {
        for (var frame = 0; frame < played; frame++) {
          final index = _trimStart + (frame % sourceLength).floor();
          if (index < energies.length) aligned[_start + frame] = energies[index];
        }
      }
      bands[band] = aligned;
    }
    return BandTable(bands);
  }

  /// Places the beats before filtering every n-th occurrence on the output clock.
  BeatGrid placeBeats(BeatGrid source, BandTable table) {
    final sourceLength = _sourceLength(table);
    final played = _playedFrames;
    if (sourceLength == 0 || played == 0) return FrameListBeatGrid(const []);
    final sourceBeats = <int>[];
    var beat = source.firstBeatAtOrAfter(_trimStart);
    while (beat != null && beat < _trimStart + sourceLength && beat < _trimStart + played) {
      sourceBeats.add(beat - _trimStart);
      beat = source.firstBeatAtOrAfter(beat + 1);
    }
    if (sourceBeats.isEmpty) return FrameListBeatGrid(const []);
    final frames = <int>[];
    // At sub-frame periods, every output frame can represent the same beat.
    final period = math.max(1, sourceLength);
    final cycles = _loop ? (played / period).ceil() : 1;
    for (var repeat = 0; repeat < cycles; repeat++) {
      for (final sourceBeat in sourceBeats) {
        final frame = (repeat * period + sourceBeat).round();
        if (frame < played) frames.add(_start + frame);
      }
    }
    return FrameListBeatGrid(frames);
  }
}
