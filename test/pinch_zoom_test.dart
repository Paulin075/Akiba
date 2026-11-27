import 'package:akiba/core/widgets/pinch_zoom.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('le pincement autorise un zoom très élevé', (
    WidgetTester tester,
  ) async {
    expect(AkibaZoom.maxScale, greaterThanOrEqualTo(20));

    final TransformationController controller = TransformationController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PinchZoom(
            controller: controller,
            child: const SizedBox(width: 400, height: 400),
          ),
        ),
      ),
    );

    final InteractiveViewer viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    expect(viewer.maxScale, AkibaZoom.maxScale);
    expect(viewer.maxScale, greaterThanOrEqualTo(20));
    expect(viewer.minScale, AkibaZoom.minScale);
    expect(viewer.panEnabled, isTrue);

    // Le panoramique reste actif une fois agrandi.
    controller.value = Matrix4.identity()..scaleByDouble(10.0, 10.0, 10.0, 1.0);
    await tester.pump();
    expect(controller.value.getMaxScaleOnAxis(), closeTo(10, 0.001));
    expect(tester.takeException(), isNull);
  });

  testWidgets('le panoramique peut être laissé au document non zoomé', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PinchZoom(
            panEnabled: false,
            child: SizedBox(width: 100, height: 100),
          ),
        ),
      ),
    );
    final InteractiveViewer viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    expect(viewer.panEnabled, isFalse);
    expect(viewer.boundaryMargin, AkibaZoom.boundaryMargin);
  });
}
