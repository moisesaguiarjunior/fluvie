# The piece

The useful identity of this fork is a widget scene that becomes a finished
piece: a cover, a preview, and a social crop, with alpha, a stable seed, and
more than one size. Upstream Fluvie organizes the work around the film.
Family Story and Social Studio need the piece.

The package stays Fluvie. A rename is justified only when three things exist
together: the first README sentence describes the piece, a consumer would
break if it returned to published 0.3.1, and the imported package matches
that job. Social Studio still pins published `fluvie: 0.3.1`. None of the
three is true yet.

## Current path

One reviewed change at a time:

1. Single-frame capture. On main as `66d2870` (PR #6).
2. Scene context. On main as `a3d7f2c` (PR #7).
3. Render metrics. The current change. An optional report. Captured pixels
   stay the same. See [Render metrics](../documentation/guides/render-metrics.md).
4. Export modes.
5. Size variants.

A public resource scope waits until a consumer needs a lifecycle the widget
tree cannot express.

The Handcrafted scene was not measured on both paths in this change. The
pixel-identity check lives in the fluvie tests.

## Later ring

These utilities are recorded so the direction is not only in conversation.
They are not steps 3 to 5, and they are not a decision to build them now.

1. Recipe with slots. The same scene binds a photo, a name, a sentence, and
   a language. The seed stays. `VideoTemplate` is the embryo. Explicit binding
   is the new utility.
2. Proof. Each file carries the scene revision, the hashes of the slot
   assets, the seed, the size, and the engine version. A later render can
   compare. This does not promise that the files are kept forever. The
   cache key is the start.
3. Plates. Besides the flat PNG, deliver alpha layers for paper, photo,
   type, and ornament. `Snapshot` already freezes a subtree. The expansion
   is to emit those pieces as output.
4. Contact sheet. A grid of instants and a grid of seeds, chosen without
   encoding. `captureFrame` is the primitive.
5. Poster and short loop. Frame 0 is the poster. A one- or two-second loop
   is the open motion. It is not a film with acts.
6. Page and crop together. The same recipe at print-page size, with bleed,
   and at Story, Feed, and square. The book is the main Family Story
   experience. The social crop is what Social Studio publishes.

Derived text and a translation sit beside the image. The original sentence
and the original audio are not replaced by what was rendered.

Leave a timeline editor, a public resource scope, and a new name out of
this expansion.
