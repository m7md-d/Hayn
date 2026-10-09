import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hayn/core/isolates/heavy_work.dart';
import 'package:hayn/features/image_ops/data/image_encoder.dart';
import 'package:hayn/features/image_ops/presentation/preview_encodes.dart';
import 'package:hayn/features/settings/providers/preferences_providers.dart';

// RV-01: the compress screen's preview result belongs to the request that
// produced it. Before, the screen stamped a finished encode with the settings
// of the moment it ended, so one that finished inside the 350 ms debounce
// after "keep metadata" was turned off was saved as if made without it; and
// in a batch, image A's encode finishing while B loaded was saved as B.

PreviewRequest _request({
  String id = 'A',
  bool keepMetadata = true,
  DefaultFormat format = DefaultFormat.heic,
  int quality = 80,
}) => PreviewRequest(
  assetId: id,
  format: format,
  quality: quality,
  keepMetadata: keepMetadata,
  keepOriginalTime: false,
  bitDepth: 0,
);

EncodedImage _result(int tag) =>
    EncodedImage(Uint8List.fromList([tag]), DefaultFormat.heic);

void main() {
  test('a result is reused only under the request it was made for', () {
    final previews = PreviewEncodes();
    final job = previews.begin(_request());
    expect(previews.complete(job, _result(1)), isTrue);

    expect(previews.reusable(_request())?.bytes, [1]);
    expect(previews.reusable(_request(keepMetadata: false)), isNull);
    expect(previews.reusable(_request(format: DefaultFormat.jpeg)), isNull);
    expect(previews.reusable(_request(quality: 81)), isNull);
    expect(previews.reusable(_request(id: 'B')), isNull);
  });

  test('an encode that ends inside the debounce after a change is not the '
      "new settings' result", () {
    final previews = PreviewEncodes();
    final kept = previews.begin(_request());
    // The user turns "keep metadata" off: the screen invalidates at once and
    // schedules the next encode 350 ms later. The old one ends first.
    previews.invalidate();
    expect(previews.isCurrent(kept), isFalse);
    expect(previews.complete(kept, _result(1)), isFalse);
    // Save pressed before the next encode starts: nothing to reuse.
    expect(previews.reusable(_request(keepMetadata: false)), isNull);
  });

  test('a change and its undo inside the debounce reuse the first result', () {
    final previews = PreviewEncodes();
    final job = previews.begin(_request());
    expect(previews.complete(job, _result(1)), isTrue);
    previews.invalidate(); // off …
    previews.invalidate(); // … and on again, before any encode ran
    expect(previews.reusable(_request())?.bytes, [1]);
  });

  test("image A's late encode is never B's, nor A's after A→B→A", () {
    final previews = PreviewEncodes();
    final a = previews.begin(_request(id: 'A'));
    // Switch to B: the screen invalidates and forgets A's result.
    previews
      ..invalidate()
      ..clear();
    expect(previews.complete(a, _result(1)), isFalse);
    expect(previews.reusable(_request(id: 'B')), isNull);

    // Back to A before its first load ended: a new job, the old one stale.
    previews
      ..invalidate()
      ..clear();
    final again = previews.begin(_request(id: 'A'));
    expect(previews.complete(a, _result(1)), isFalse);
    expect(previews.complete(again, _result(2)), isTrue);
    expect(previews.reusable(_request(id: 'A'))?.bytes, [2]);
  });

  test(
    'a newer job withdraws an older one still waiting in the gate',
    () async {
      final gate = HeavyWork(memory: () async => null, maxConcurrent: 1);
      final busy = Completer<void>();
      final running = gate.run(estimateBytes: 0, body: () => busy.future);
      final previews = PreviewEncodes();
      final first = previews.begin(_request());
      final waiting = gate.run(
        estimateBytes: 0,
        ticket: first.ticket,
        body: () async => fail('a stale preview must not start'),
      );
      previews.begin(_request(quality: 60));
      await expectLater(waiting, throwsA(isA<HeavyWorkWithdrawn>()));
      busy.complete();
      await running;
    },
  );
}
