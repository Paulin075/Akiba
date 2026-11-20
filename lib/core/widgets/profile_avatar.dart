import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme/akiba_colors.dart';

/// Avatar rond partagé par l'en-tête de l'accueil, l'écran Profil et l'écran
/// de verrouillage.
///
/// Photo locale chiffrée si elle existe ; sinon l'avatar système
/// `assets/profile/avatar_default.jpg` (visuel `argent.jpg` fourni dans
/// `akiba_spec/`). Aucun appel réseau.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.bytes,
    required this.name,
    this.size = 44,
    this.onTap,
  });

  final Uint8List? bytes;

  /// Prénom affiché pour l'initiale (vide → silhouette).
  final String name;

  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);
    final Uint8List? photo = bytes;
    final String clean = name.trim();
    final String initial = clean.isEmpty ? '' : clean[0].toUpperCase();

    final Widget content = photo != null
        ? ClipOval(
            child: Image.memory(
              photo,
              width: size,
              height: size,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder:
                  (BuildContext context, Object error, StackTrace? s) =>
                      _defaultAvatar(c, initial),
            ),
          )
        : _defaultAvatar(c, initial);

    return Semantics(
      image: true,
      label: photo != null ? 'Photo de profil' : 'Avatar par défaut',
      child: SizedBox(
        width: size,
        height: size,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: content,
          ),
        ),
      ),
    );
  }

  Widget _defaultAvatar(AkibaColors c, String initial) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      color: Colors.white,
      child: ClipOval(
        child: Image.asset(
          'assets/profile/avatar_default.jpg',
          width: size,
          height: size,
          fit: BoxFit.cover,
          excludeFromSemantics: true,
          errorBuilder: (BuildContext context, Object error, StackTrace? s) =>
              initial.isEmpty
              ? Icon(
                  Icons.person_outline_rounded,
                  size: size * 0.5,
                  color: c.terracottaDeep,
                )
              : Text(
                  initial,
                  style: TextStyle(
                    fontSize: size * 0.4,
                    fontWeight: FontWeight.w700,
                    color: c.terracottaDeep,
                  ),
                ),
        ),
      ),
    );
  }
}
