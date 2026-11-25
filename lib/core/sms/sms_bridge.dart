import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// Pont entre le récepteur SMS Android et l'application Flutter.
///
/// Le récepteur natif (`SmsReceiver.kt`) ne lit rien d'autre que le SMS reçu et
/// ne stocke rien sur disque : il dépose le texte dans l'`Intent` de la
/// notification. Au clic, `MainActivity` le remet à Flutter par ce canal, et
/// l'application ouvre la fiche préremplie. Aucune écriture en base n'est faite
/// ici.
abstract final class SmsBridge {
  static const MethodChannel _method = MethodChannel('akiba/sms');
  static const EventChannel _events = EventChannel('akiba/sms_events');

  /// Le récepteur n'existe que sur Android.
  static bool get supported => !kIsWeb && Platform.isAndroid;

  /// Texte SMS en attente d'ouverture (notification touchée, application
  /// fermée), ou `null`. Une seule consommation par SMS.
  static Future<String?> consumePending() async {
    if (!supported) return null;
    try {
      final String? body = await _method.invokeMethod<String>(
        'consumePendingSms',
      );
      final String trimmed = (body ?? '').trim();
      return trimmed.isEmpty ? null : trimmed;
    } on MissingPluginException {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// SMS reçus pendant que l'application tourne, via le récepteur natif.
  static Stream<String> get messages {
    if (!supported) return const Stream<String>.empty();
    return _events
        .receiveBroadcastStream()
        .map((Object? event) => '${event ?? ''}'.trim())
        .where((String body) => body.isNotEmpty)
        .handleError((Object _) {});
  }
}
