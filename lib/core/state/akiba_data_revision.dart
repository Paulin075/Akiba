import 'package:flutter/foundation.dart';

/// Signal de rafraîchissement partagé par les écrans.
///
/// Chaque écriture en base appelle `bump()` : les écrans abonnés relisent leurs
/// données sans avoir à se connaître entre eux.
class AkibaDataRevision extends ChangeNotifier {
  void bump() => notifyListeners();
}
