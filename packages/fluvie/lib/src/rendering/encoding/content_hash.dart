import 'dart:convert';

import 'package:fluvie/src/core/hash/fnv1a.dart';
import 'package:fluvie/src/rendering/render_config.dart';

// The in-house FNV-1a-64 hash lives in `core/hash` so `core` value types can
// also key on it without inverting the layering. It is
// re-exported here to keep the established render-side import stable.
export 'package:fluvie/src/core/hash/fnv1a.dart' show fnv1a64Hex;

/// The fluvie version baked into every render digest (kept in lockstep with
/// `pubspec.yaml`); a version bump invalidates all cached frames.
const String fluvieRenderVersion = '0.3.1+socialstudio.2';

/// The digest that identifies one render's cached frames: a hash over the
/// full [config] JSON, the [compositionKey], and the [fluvieVersion].
///
/// Any change to any of the three produces a new digest, isolating cache
/// entries between configurations, compositions, and library versions. The
/// cache stays *advisory*: composition **code** changes under an
/// unchanged key are not detected — stale frames are evicted by version bumps
/// or a `--no-cache` run.
String renderDigest({
  required RenderConfig config,
  required String compositionKey,
  required String fluvieVersion,
}) => fnv1a64Hex(
  utf8.encode(
    jsonEncode({
      'config': config.toJson(),
      'compositionKey': compositionKey,
      'fluvieVersion': fluvieVersion,
    }),
  ),
);

/// Composition key stored in a frame-cache digest.
///
/// [seeds] lists every video mounted when the key is built, in tree order, and
/// each entry is part of the key, including zero. Pixels cached for one
/// sequence are not replayed for another. One seed keeps the single-video
/// spelling. A video that mounts on a later frame is not in [seeds]; the
/// caller-supplied [compositionKey] has to include that seed. Pass the active
/// [aspectName] to distinguish layout variants that share a canvas size.
String frameCacheCompositionKey(
  String compositionKey, {
  required List<int> seeds,
  String? aspectName,
}) {
  final aspect = aspectName == null ? '' : '-$aspectName';
  return '$compositionKey$aspect-seed-${seeds.join('-')}';
}
