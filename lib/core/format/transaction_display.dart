import 'package:flutter/material.dart';

import '../../data/models/transaction_record.dart';
import '../state/akiba_l10n.dart';
import '../theme/akiba_colors.dart';
import 'akiba_date.dart';
import 'label_icons.dart';

/// Présentation commune d'un mouvement : icône, titre, sous-titre, couleur.
///
/// Partagée par l'accueil et le portefeuille pour que la même écriture se lise
/// exactement de la même façon partout.
abstract final class TransactionDisplay {
  /// Icône du mouvement : déduite du libellé quand il est parlant
  /// (« moniteur », « moto », « loyer »…), sinon celle du type.
  static IconData iconFor(TransactionRecord record) {
    switch (record.kind) {
      case TransactionKind.income:
        return Icons.south_west_rounded;
      case TransactionKind.transfer:
        return Icons.swap_horiz_rounded;
      case TransactionKind.opening:
        return Icons.flag_rounded;
      case TransactionKind.savings:
        return LabelIcons.forText(
          record.note ?? record.category,
          fallback: Icons.savings_rounded,
        );
      case TransactionKind.expense:
        return LabelIcons.forText(
          record.note ?? record.category,
          fallback: Icons.receipt_long_rounded,
        );
    }
  }

  static String titleFor(TransactionRecord record) {
    if (record.isNeutral) return AkibaL10n.tr('third_party_money');
    if (record.note != null && record.note!.trim().isNotEmpty) {
      return record.note!;
    }
    if (record.category != null && record.category!.trim().isNotEmpty) {
      return record.category!;
    }
    return switch (record.kind) {
      TransactionKind.income => AkibaL10n.tr('entry'),
      TransactionKind.expense => AkibaL10n.tr('expense'),
      TransactionKind.transfer => AkibaL10n.tr('transfer'),
      TransactionKind.savings => AkibaL10n.tr('savings'),
      TransactionKind.opening => AkibaL10n.tr('opening_balance'),
    };
  }

  static String subtitleFor(TransactionRecord record) {
    final DateTime local = record.occurredAt.toLocal();
    final String when =
        '${AkibaDate.dayLabel(local)} · ${AkibaDate.time(local)}';
    final String account = record.category ?? record.kind.name;
    return record.category == null ? when : '$account · $when';
  }

  static Color amountColor(TransactionRecord record, AkibaColors c) {
    if (record.kind == TransactionKind.savings) return c.ochre;
    if (record.isNeutral) return c.textMuted;
    return record.amount < 0 ? c.danger : c.success;
  }
}
