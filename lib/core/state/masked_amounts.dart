import 'package:flutter/widgets.dart';

/// Masquage global des montants, partagé par tous les écrans.
///
/// Un seul état pilote l'œil de l'en-tête, les cartes, les listes et les
/// graphiques : aucun écran ne peut afficher un montant en clair par oubli.
class MaskedAmounts extends InheritedNotifier<ValueNotifier<bool>> {
  const MaskedAmounts({
    super.key,
    required ValueNotifier<bool> notifier,
    required super.child,
  }) : super(notifier: notifier);

  /// Vrai si les montants doivent être remplacés par des points.
  static bool of(BuildContext context) {
    final MaskedAmounts? scope = context
        .dependOnInheritedWidgetOfExactType<MaskedAmounts>();
    return scope?.notifier?.value ?? false;
  }

  /// Inverse le masquage depuis n'importe quel écran.
  static void toggle(BuildContext context) {
    final MaskedAmounts? scope = context
        .getInheritedWidgetOfExactType<MaskedAmounts>();
    final ValueNotifier<bool>? notifier = scope?.notifier;
    if (notifier == null) return;
    notifier.value = !notifier.value;
  }
}
