import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/akiba_colors.dart';
import '../theme/akiba_tokens.dart';
import '../theme/akiba_typography.dart';

/// Recadrage local de la photo de profil, **avant** validation.
///
/// Aucun service distant, aucune dépendance supplémentaire : l'image choisie
/// est affichée dans un carré, déplaçable au doigt et zoomable, puis recadrée
/// en 512 × 512 avec `dart:ui` et renvoyée pour le chiffrement.
Future<Uint8List?> showAvatarEditor(BuildContext context, Uint8List source) {
  return showDialog<Uint8List>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) => _AvatarEditorDialog(source: source),
  );
}

/// Visionneuse plein écran d'une photo de profil déjà enregistrée.
Future<void> showAvatarViewer(BuildContext context, Uint8List bytes) {
  final AkibaColors c = AkibaColors.of(context);
  return showDialog<void>(
    context: context,
    builder: (BuildContext context) => Dialog(
      backgroundColor: c.surface,
      insetPadding: const EdgeInsets.all(AkibaSpacing.lg),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AkibaRadii.card),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AkibaSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(AkibaRadii.field),
              child: InteractiveViewer(
                maxScale: 4,
                child: Image.memory(bytes, fit: BoxFit.contain),
              ),
            ),
            const SizedBox(height: AkibaSpacing.md),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Fermer'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _AvatarEditorDialog extends StatefulWidget {
  const _AvatarEditorDialog({required this.source});

  final Uint8List source;

  @override
  State<_AvatarEditorDialog> createState() => _AvatarEditorDialogState();
}

class _AvatarEditorDialogState extends State<_AvatarEditorDialog> {
  static const double _preview = 280;

  ui.Image? _image;
  double _zoom = 1;
  Offset _offset = Offset.zero;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  Future<void> _decode() async {
    try {
      final ui.Codec codec = await ui.instantiateImageCodec(widget.source);
      final ui.FrameInfo frame = await codec.getNextFrame();
      if (!mounted) return;
      setState(() => _image = frame.image);
    } catch (_) {
      if (mounted) setState(() => _error = 'Image illisible.');
    }
  }

  /// Échelle qui couvre entièrement le carré d'aperçu.
  double get _baseScale {
    final ui.Image? image = _image;
    if (image == null || image.width == 0 || image.height == 0) return 1;
    return _preview / (image.width < image.height ? image.width : image.height);
  }

  double get _effectiveScale => _baseScale * _zoom;

  Offset _clampOffset(Offset value) {
    final ui.Image? image = _image;
    if (image == null) return value;
    final double scale = _effectiveScale;
    final double halfX = ((image.width * scale - _preview) / 2).clamp(
      0,
      double.infinity,
    );
    final double halfY = ((image.height * scale - _preview) / 2).clamp(
      0,
      double.infinity,
    );
    return Offset(value.dx.clamp(-halfX, halfX), value.dy.clamp(-halfY, halfY));
  }

  Future<void> _validate() async {
    final ui.Image? image = _image;
    if (image == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final double scale = _effectiveScale;
      final double left = _preview / 2 - image.width * scale / 2 + _offset.dx;
      final double top = _preview / 2 - image.height * scale / 2 + _offset.dy;

      double srcX = (-left / scale).clamp(0, image.width.toDouble());
      double srcY = (-top / scale).clamp(0, image.height.toDouble());
      double srcSide = (_preview / scale).clamp(
        1,
        image.width.toDouble() < image.height.toDouble()
            ? image.width.toDouble()
            : image.height.toDouble(),
      );
      if (srcX + srcSide > image.width) srcX = image.width - srcSide;
      if (srcY + srcSide > image.height) srcY = image.height - srcSide;

      final int out = 512;
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder);
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(srcX, srcY, srcSide, srcSide),
        Rect.fromLTWH(0, 0, out.toDouble(), out.toDouble()),
        Paint()..filterQuality = FilterQuality.high,
      );
      final ui.Picture picture = recorder.endRecording();
      final ui.Image cropped = await picture.toImage(out, out);
      final ByteData? data = await cropped.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (!mounted) return;
      if (data == null) {
        setState(() => _error = 'Recadrage impossible.');
        return;
      }
      Navigator.of(context).pop(data.buffer.asUint8List());
    } catch (_) {
      if (mounted) setState(() => _error = 'Recadrage impossible.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);
    final ui.Image? image = _image;

    return Dialog(
      backgroundColor: c.surface,
      insetPadding: const EdgeInsets.all(AkibaSpacing.lg),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AkibaRadii.card),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AkibaSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'Ajuster la photo',
              style: AkibaTypography.sectionTitle.copyWith(
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: AkibaSpacing.xs),
            Text(
              'Déplacez l’image et zoomez pour centrer votre visage.',
              textAlign: TextAlign.center,
              style: AkibaTypography.legend.copyWith(color: c.textMuted),
            ),
            const SizedBox(height: AkibaSpacing.lg),
            SizedBox(
              width: _preview,
              height: _preview,
              child: ClipOval(
                child: Container(
                  color: c.surfaceElevated,
                  child: image == null
                      ? Center(
                          child: _error == null
                              ? const CircularProgressIndicator()
                              : Text(
                                  _error!,
                                  style: AkibaTypography.legend.copyWith(
                                    color: c.danger,
                                  ),
                                ),
                        )
                      : GestureDetector(
                          onPanUpdate: (DragUpdateDetails details) {
                            setState(() {
                              _offset = _clampOffset(_offset + details.delta);
                            });
                          },
                          child: Stack(
                            alignment: Alignment.center,
                            children: <Widget>[
                              Transform.translate(
                                offset: _offset,
                                child: Transform.scale(
                                  scale: _effectiveScale,
                                  child: RawImage(
                                    image: image,
                                    width: image.width.toDouble(),
                                    height: image.height.toDouble(),
                                    filterQuality: FilterQuality.high,
                                  ),
                                ),
                              ),
                              IgnorePointer(
                                child: Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: c.surface.withValues(alpha: 0.9),
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: AkibaSpacing.md),
            Row(
              children: <Widget>[
                Icon(Icons.zoom_out_rounded, size: 18, color: c.textMuted),
                Expanded(
                  child: Slider(
                    value: _zoom,
                    min: 1,
                    max: 3,
                    activeColor: c.terracotta,
                    onChanged: _busy
                        ? null
                        : (double value) {
                            setState(() {
                              _zoom = value;
                              _offset = _clampOffset(_offset);
                            });
                          },
                  ),
                ),
                Icon(Icons.zoom_in_rounded, size: 18, color: c.textMuted),
              ],
            ),
            const SizedBox(height: AkibaSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                TextButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  child: const Text('Annuler'),
                ),
                const SizedBox(width: AkibaSpacing.sm),
                FilledButton.icon(
                  onPressed: _busy ? null : _validate,
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: Text(_busy ? 'Recadrage…' : 'Valider'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
