import 'package:akiba/core/notifications/notification_style.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const String longBody =
      'Rappel du soir : notez vos dépenses de la journée pendant qu’elles '
      'sont encore fraîches. Un mouvement, un montant, une catégorie : '
      'trois secondes suffisent, et votre solde reste juste. Aucun montant '
      'n’apparaît ici si le masquage est actif.';

  test(
    'le message long part en entier dans bigText, sans points de suspension',
    () {
      final AndroidNotificationDetails details = AkibaNotificationStyle.android(
        channelId: AkibaNotificationStyle.remindersChannelId,
        channelName: AkibaNotificationStyle.remindersChannelName,
        channelDescription: 'Rappels',
        title: 'Rappel AKIBA',
        body: longBody,
      );

      expect(details.styleInformation, isA<BigTextStyleInformation>());
      final BigTextStyleInformation style =
          details.styleInformation! as BigTextStyleInformation;
      expect(style.bigText, longBody);
      expect(style.contentTitle, 'Rappel AKIBA');
      expect(style.bigText.contains('…'), isFalse);
      expect(style.bigText.endsWith('actif.'), isTrue);
      // Le corps de la notification (contentText) porte le même texte complet.
      expect(details.ticker, longBody);
    },
  );

  test('la bienvenue utilise le même style étendu', () {
    final AndroidNotificationDetails details = AkibaNotificationStyle.android(
      channelId: AkibaNotificationStyle.welcomeChannelId,
      channelName: AkibaNotificationStyle.welcomeChannelName,
      channelDescription: 'Bienvenue',
      title: 'Bienvenue dans AKIBA',
      body:
          'Ama Koffi, votre tirelire est prête. Tout reste chiffré et hors '
          'ligne, et vos montants ne sortent jamais de cet appareil.',
    );

    final BigTextStyleInformation style =
        details.styleInformation! as BigTextStyleInformation;
    expect(style.bigText, contains('Ama Koffi'));
    expect(style.bigText, isNot(contains('…')));
    expect(details.channelId, AkibaNotificationStyle.welcomeChannelId);
  });
}
