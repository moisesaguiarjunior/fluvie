# External material surfaces and the frame timeline

Material packages can compose ordinary widgets around Fluvie media. Keep the
material dependency in the consumer or an adapter, not in Fluvie's core. The
existing public CollectibleChildren interface lets a consumer-owned stateful
or stateless wrapper expose constructor children to media pre-resolution.

```dart
class MaterialWrapper extends StatelessWidget implements CollectibleChildren {
  const MaterialWrapper({super.key, required this.child});
  final Widget child;

  @override
  Iterable<Widget> get collectibleChildren => [child];

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(color: Color(0xFFF3EADC)),
    child: child,
  );
}
```

An adapter can replace the decoration with a CraftSurface from
handcrafted_flutter. Declare Fluvie's Image/Clip outside a FrameBuilder callback
and return that declared child through collectibleChildren. The shared structural
walk does not build arbitrary widgets or invoke frame callbacks before capture.
A wrapper that hides its media in build cannot expect those sources to be
pre-resolved. Normal Flutter render-object wrappers remain traversable.

Use FrameBuilder only where values depend on its resolved frame/progress. For
example, feed progress to PartPose or derive a bounded pendulum sample from the
resolved scene interval. Do not mount another entrance ticker in a frame export.
Static material seed/palette belong to the authored recipe and should remain
stable across repeated or out-of-order frame requests.

Social Studio's crafted Story adapter uses this boundary with its own versioned
material recipe. Image discovery, decoding, scene timing and captions remain
Fluvie's responsibility; textures, cut edges and thread remain the material
package's responsibility. No additional media collector or frame clock is needed.

## Verification boundary

The default collector suite covers an external stateful surface containing an
animated declared image and a decorative FrameBuilder. Collection returns the
image without building either wrapper or callback. Removing the public-interface
walk must break that regression. The consumer must still test its actual frame
capture/export and local media/network boundaries. This fork does not gain a
handcrafted_flutter dependency or claim device performance from this test.
