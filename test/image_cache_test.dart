import 'dart:async';
import 'dart:ui' as ui;

import 'dart:typed_data';
import 'support/image_test_bytes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard/src/editor/image_cache_manager.dart';

Future<Uint8List> _originalPng() async => imageTestPng();

void main() {
  testWidgets('controlled PNG decodes visible multicolored pixels', (
    tester,
  ) async {
    final cache = ImageCacheManager();
    addTearDown(cache.dispose);
    await tester.runAsync(() async {
      final image = await cache.load('png', _originalPng, targetWidth: 64);
      expect(image, isNotNull, reason: cache.errors.toString());
      expect(image!.width, 64);
      expect(image.height, 32);
      final pixels = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final colors = <int>{};
      var visiblePixels = 0;
      for (var offset = 0; offset < pixels.lengthInBytes; offset += 4) {
        if (pixels.getUint8(offset + 3) > 0) {
          visiblePixels++;
          colors.add(pixels.getUint32(offset));
        }
      }
      expect(visiblePixels, greaterThan(0));
      expect(colors.length, greaterThan(2));
      expect(cache.get('png'), same(image));
      expect(cache.currentBytes, 64 * 32 * 4);
    });
  });

  testWidgets('entry eviction allows original asset to be decoded again', (
    tester,
  ) async {
    final cache = ImageCacheManager(maxEntries: 1);
    addTearDown(cache.dispose);
    await tester.runAsync(() async {
      final bytes = await _originalPng();
      final first = await cache.load(
        'first',
        () async => bytes,
        targetWidth: 32,
      );
      expect(first, isNotNull);
      expect(
        await cache.load('second', () async => bytes, targetWidth: 32),
        isNotNull,
      );
      expect(cache.cachedCount, 1);
      expect(cache.get('first'), isNull);
      var reads = 0;
      final reloaded = await cache.load('first', () async {
        reads++;
        return bytes;
      }, targetWidth: 32);
      expect(reloaded, isNotNull);
      expect(identical(reloaded, first), isFalse);
      expect(reads, 1);
      expect(cache.get('second'), isNull);
      expect(cache.cachedCount, 1);
    });
  });

  testWidgets('visible capacity does not evict and endlessly reload peers', (
    tester,
  ) async {
    final cache = ImageCacheManager(maxEntries: 1);
    addTearDown(cache.dispose);
    await tester.runAsync(() async {
      cache.updateVisibleAssets({'a', 'b'}, 'first view');
      expect(await cache.load('a', _originalPng), isNotNull);
      expect(await cache.load('b', _originalPng), isNull);
      expect(cache.get('a'), isNotNull);
      expect(cache.errors['b'], contains(ImageCacheManager.capacityError));
      cache.updateVisibleAssets({'b'}, 'second view');
      expect(cache.errors['b'], isNull);
      expect(await cache.load('b', _originalPng), isNotNull);
      expect(cache.cachedCount, 1);
    });
  });

  testWidgets(
    'removed image discards pending decode and releases cached pixels',
    (tester) async {
      final cache = ImageCacheManager();
      addTearDown(cache.dispose);
      await tester.runAsync(() async {
        final gate = Completer<Uint8List?>();
        final pending = cache.load('removed', () => gate.future);
        cache.retainOnly({});
        gate.complete(await _originalPng());
        expect(await pending, isNull);
        expect(cache.cachedCount, 0);
        expect(await cache.load('removed', _originalPng), isNotNull);
        cache.retainOnly({});
        expect(cache.currentBytes, 0);
        expect(cache.get('removed'), isNull);
      });
    },
  );

  testWidgets('missing and corrupt assets report failures and can retry', (
    tester,
  ) async {
    final cache = ImageCacheManager();
    addTearDown(cache.dispose);
    await tester.runAsync(() async {
      expect(await cache.load('missing', () async => null), isNull);
      expect(cache.errors['missing'], contains('missing'));
      expect(
        await cache.load('corrupt', () async => Uint8List.fromList([1, 2, 3])),
        isNull,
      );
      expect(cache.errors['corrupt'], isNotEmpty);
      for (final id in ['missing', 'corrupt']) {
        expect(await cache.load(id, _originalPng, targetWidth: 32), isNotNull);
        expect(cache.errors.containsKey(id), isFalse);
      }
    });
  });

  testWidgets('old generation cannot remove or publish over a new request', (
    tester,
  ) async {
    final cache = ImageCacheManager();
    addTearDown(cache.dispose);
    await tester.runAsync(() async {
      final oldBytes = Completer<Uint8List?>();
      final newBytes = Completer<Uint8List?>();
      final oldRequest = cache.load('shared', () => oldBytes.future);
      cache.clear();
      final newRequest = cache.load(
        'shared',
        () => newBytes.future,
        targetWidth: 32,
      );
      oldBytes.complete(null);
      expect(await oldRequest, isNull);
      expect(cache.errors, isEmpty);
      var unexpectedRead = false;
      final concurrentRequest = cache.load('shared', () async {
        unexpectedRead = true;
        return null;
      });
      expect(concurrentRequest, same(newRequest));
      newBytes.complete(await _originalPng());
      final image = await newRequest;
      expect(image, isNotNull);
      expect(await concurrentRequest, same(image));
      expect(unexpectedRead, isFalse);
      expect(cache.cachedCount, 1);
    });
  });

  testWidgets(
    'disposal invalidates pending work and releases cache accounting',
    (tester) async {
      final cache = ImageCacheManager();
      addTearDown(cache.dispose);
      await tester.runAsync(() async {
        expect(
          await cache.load('ready', _originalPng, targetWidth: 32),
          isNotNull,
        );
        final delayedBytes = Completer<Uint8List?>();
        final pending = cache.load('pending', () => delayedBytes.future);
        cache.dispose();
        delayedBytes.complete(await _originalPng());
        expect(await pending, isNull);
        expect(cache.isDisposed, isTrue);
        expect(cache.cachedCount, 0);
        expect(cache.currentBytes, 0);
        expect(cache.errors, isEmpty);
        expect(cache.get('ready'), isNull);
        expect(
          await cache.load(
            'after-disposal',
            () => throw StateError('not called'),
          ),
          isNull,
        );
      });
    },
  );

  testWidgets('decoded images stay inside the total byte budget', (
    tester,
  ) async {
    const budget = 64 * 32 * 4;
    final cache = ImageCacheManager(maxBytes: budget);
    addTearDown(cache.dispose);
    await tester.runAsync(() async {
      final first = await cache.load('first', _originalPng);
      expect(first, isNotNull, reason: cache.errors.toString());
      expect(first!.width * first.height * 4, lessThanOrEqualTo(budget));
      expect(cache.currentBytes, lessThanOrEqualTo(budget));
      expect(await cache.load('second', _originalPng), isNotNull);
      expect(cache.currentBytes, lessThanOrEqualTo(budget));
      expect(cache.cachedCount, 1);
      expect(cache.get('first'), isNull);
      cache.clear();
      expect(cache.currentBytes, 0);
      expect(cache.cachedCount, 0);
    });
  });
}
