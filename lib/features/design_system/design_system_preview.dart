import 'package:flutter/material.dart';

import '../../core/format/akiba_money.dart';
import '../../core/theme/akiba_colors.dart';
import '../../core/theme/akiba_theme.dart';
import '../../core/theme/akiba_tokens.dart';
import '../../core/theme/akiba_typography.dart';
import '../../core/widgets/akiba_surface_card.dart';
import '../../core/widgets/brand_logo.dart';

/// Vitrine du socle design system (Étape 1).
///
/// Cette page ne contient aucune logique métier : elle prouve la palette
/// clair/sombre, le format FCFA, les composants logo + nom des supports et la
/// composition avec la barre basse et les boutons latéraux.
class DesignSystemPreview extends StatefulWidget {
  const DesignSystemPreview({
    super.key,
    required this.themeId,
    required this.onThemeChanged,
  });

  final AkibaThemeId themeId;
  final ValueChanged<AkibaThemeId> onThemeChanged;

  @override
  State<DesignSystemPreview> createState() => _DesignSystemPreviewState();
}

class _DesignSystemPreviewState extends State<DesignSystemPreview> {
  bool _masked = false;

  static const List<({AccountBrand brand, String subtitle, int balance})>
  _accounts = <({AccountBrand brand, String subtitle, int balance})>[
    (
      brand: AccountBrand.flooz,
      subtitle: 'Mobile money · Flooz',
      balance: 25000,
    ),
    (
      brand: AccountBrand.mixxByYas,
      subtitle: 'Mobile money · Mixx by Yas',
      balance: 12500,
    ),
    (brand: AccountBrand.orabank, subtitle: 'Compte courant', balance: 120000),
    (brand: AccountBrand.liquide, subtitle: 'Espèces', balance: 8000),
  ];

  void _cycleTheme() {
    final List<AkibaThemeId> all = AkibaThemeId.values;
    widget.onThemeChanged(all[(all.indexOf(widget.themeId) + 1) % all.length]);
  }

  String get _themeLabel => widget.themeId.label;

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AkibaSpacing.screen,
        AkibaSpacing.lg,
        AkibaSpacing.screen,
        140,
      ),
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'AKIBA',
                    style: AkibaTypography.label.copyWith(
                      color: c.textMuted,
                      letterSpacing: 2.4,
                    ),
                  ),
                  const SizedBox(height: AkibaSpacing.xs),
                  Text(
                    'Socle design system',
                    style: AkibaTypography.screenTitle.copyWith(
                      color: c.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            _CircleIconButton(
              icon: _masked
                  ? Icons.visibility_off_rounded
                  : Icons.visibility_rounded,
              tooltip: _masked
                  ? 'Afficher les montants'
                  : 'Masquer les montants',
              onTap: () => setState(() => _masked = !_masked),
            ),
            const SizedBox(width: AkibaSpacing.sm),
            _CircleIconButton(
              icon: c.isDark
                  ? Icons.dark_mode_rounded
                  : Icons.light_mode_rounded,
              tooltip: 'Apparence : $_themeLabel',
              onTap: _cycleTheme,
            ),
          ],
        ),
        const SizedBox(height: AkibaSpacing.xxl),
        _BalanceCard(masked: _masked),
        const SizedBox(height: AkibaSpacing.xxl),
        _SectionTitle(title: 'Supports et logos'),
        const SizedBox(height: AkibaSpacing.md),
        AkibaSurfaceCard(
          padding: const EdgeInsets.symmetric(
            horizontal: AkibaSpacing.xl,
            vertical: AkibaSpacing.md,
          ),
          child: Column(
            children: <Widget>[
              for (int i = 0; i < _accounts.length; i++) ...<Widget>[
                AccountBadge(
                  brand: _accounts[i].brand,
                  subtitle: _accounts[i].subtitle,
                  amountLabel: AkibaMoney.format(
                    _accounts[i].balance,
                    masked: _masked,
                  ),
                ),
                if (i != _accounts.length - 1)
                  Divider(
                    height: AkibaSpacing.md,
                    color: c.surfaceElevated,
                    thickness: 1,
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AkibaSpacing.xxl),
        _SectionTitle(title: 'Formats FCFA'),
        const SizedBox(height: AkibaSpacing.md),
        AkibaSurfaceCard(
          child: Column(
            children: <Widget>[
              _FormatRow(
                label: 'Montant courant',
                value: AkibaMoney.format(15000),
              ),
              _FormatRow(
                label: 'Montant élevé',
                value: AkibaMoney.format(1250000),
              ),
              _FormatRow(
                label: 'Sortie',
                value: AkibaMoney.formatSigned(-3500),
                color: c.danger,
              ),
              _FormatRow(
                label: 'Entrée',
                value: AkibaMoney.formatSigned(10000),
                color: c.success,
              ),
              _FormatRow(
                label: 'Masqué',
                value: AkibaMoney.format(42853, masked: true),
              ),
            ],
          ),
        ),
        const SizedBox(height: AkibaSpacing.xxl),
        _SectionTitle(title: 'Palette du thème'),
        const SizedBox(height: AkibaSpacing.md),
        Wrap(
          spacing: AkibaSpacing.md,
          runSpacing: AkibaSpacing.md,
          children: <Widget>[
            _Swatch(name: 'Fond', color: c.background),
            _Swatch(name: 'Surface', color: c.surface),
            _Swatch(name: 'Élevée', color: c.surfaceElevated),
            _Swatch(name: 'Tuile', color: c.iconTile),
            _Swatch(name: 'Terre cuite', color: c.terracotta),
            _Swatch(name: 'Profonde', color: c.terracottaDeep),
            _Swatch(name: 'Ocre', color: c.ochre),
            _Swatch(name: 'Sable', color: c.sand),
            _Swatch(name: 'Texte', color: c.textPrimary),
            _Swatch(name: 'Atténué', color: c.textMuted),
            _Swatch(name: 'Succès', color: c.success),
            _Swatch(name: 'Alerte', color: c.warning),
            _Swatch(name: 'Erreur', color: c.danger),
          ],
        ),
        const SizedBox(height: AkibaSpacing.xxl),
        _SectionTitle(title: 'Typographie'),
        const SizedBox(height: AkibaSpacing.md),
        AkibaSurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Titre d’écran',
                style: AkibaTypography.screenTitle.copyWith(
                  color: c.textPrimary,
                ),
              ),
              const SizedBox(height: AkibaSpacing.sm),
              Text(
                'Titre de section',
                style: AkibaTypography.sectionTitle.copyWith(
                  color: c.textPrimary,
                ),
              ),
              const SizedBox(height: AkibaSpacing.sm),
              Text(
                'Corps de texte courant, 14 pt, pour expliquer une règle.',
                style: AkibaTypography.body.copyWith(color: c.textMuted),
              ),
              const SizedBox(height: AkibaSpacing.sm),
              Text(
                'LÉGENDE · 12 PT',
                style: AkibaTypography.legend.copyWith(color: c.textMuted),
              ),
              const SizedBox(height: AkibaSpacing.md),
              Text(
                AkibaMoney.format(42853),
                style: AkibaTypography.money(26, color: c.terracotta),
              ),
            ],
          ),
        ),
        const SizedBox(height: AkibaSpacing.xxl),
        Text(
          'Barre basse ancrée, bouton cochon et icône IA sur le côté droit : '
          'voir le cadre de navigation.',
          style: AkibaTypography.legend.copyWith(color: c.textMuted),
        ),
      ],
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.masked});

  final bool masked;

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);

    return Container(
      padding: const EdgeInsets.all(AkibaSpacing.xl),
      decoration: BoxDecoration(
        gradient: c.balanceGradient,
        borderRadius: BorderRadius.circular(AkibaRadii.hero),
        boxShadow: c.heroShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'SOLDE DISPONIBLE',
            style: AkibaTypography.label.copyWith(
              color: c.onTerracotta.withValues(alpha: 0.88),
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: AkibaSpacing.sm),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              AkibaMoney.format(42853, masked: masked),
              style: AkibaTypography.money(34, color: c.onTerracotta),
              maxLines: 1,
            ),
          ),
          const SizedBox(height: AkibaSpacing.sm),
          Text(
            'Total des comptes − argent de tiers',
            style: AkibaTypography.legend.copyWith(
              color: c.onTerracotta.withValues(alpha: 0.82),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);
    return Text(
      title,
      style: AkibaTypography.sectionTitle.copyWith(color: c.textPrimary),
    );
  }
}

class _FormatRow extends StatelessWidget {
  const _FormatRow({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AkibaSpacing.sm),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: AkibaTypography.body.copyWith(color: c.textMuted),
            ),
          ),
          Text(
            value,
            style: AkibaTypography.money(
              15,
              weight: FontWeight.w600,
              color: color ?? c.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.name, required this.color});

  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 64,
          height: 44,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(AkibaRadii.iconTile),
            boxShadow: c.isDark
                ? const <BoxShadow>[]
                : const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x0F1A1816),
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
          ),
        ),
        const SizedBox(height: AkibaSpacing.xs),
        Text(
          name,
          style: AkibaTypography.legend.copyWith(
            color: c.textMuted,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AkibaColors c = AkibaColors.of(context);

    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: Material(
          color: c.surface,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: AkibaSizes.touchTarget,
              height: AkibaSizes.touchTarget,
              child: Icon(icon, size: 20, color: c.textPrimary),
            ),
          ),
        ),
      ),
    );
  }
}
