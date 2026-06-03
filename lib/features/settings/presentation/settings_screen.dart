import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/l10n/app_localizations.dart';
import '../../../app/providers/locale_provider.dart';
import '../../../app/providers/theme_provider.dart';
import '../../../app/theme/app_theme_extension.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../core/capabilities/format_capabilities.dart';
import '../../../shared/widgets/widgets.dart';
import '../../image_ops/data/native_avif_encoder.dart';
import '../providers/preferences_providers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SettingsScreen — sectioned settings list. Each tappable cell opens a picker
// sheet for that preference. Defaults / safety / about flesh out in D3.
// ─────────────────────────────────────────────────────────────────────────────

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final hc = context.hc;
    final theme = Theme.of(context);

    final themeMode = ref.watch(themeProvider);
    final locale = ref.watch(localeProvider);
    final numerals = ref.watch(numeralsProvider);
    final defaultFormat = ref.watch(defaultFormatProvider);
    final defaultQuality = ref.watch(defaultQualityProvider);
    final trashRetention = ref.watch(trashRetentionProvider);
    final caps = ref.watch(formatCapabilitiesProvider);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: CustomScrollView(
        // Not primary: the Library grid owns the single PrimaryScrollController
        // so iOS status-bar-tap-to-top has one unambiguous target across tabs.
        primary: false,
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          SliverAppBar.large(
            pinned: true,
            stretch: true,
            backgroundColor: theme.scaffoldBackgroundColor,
            surfaceTintColor: Colors.transparent,
            shadowColor: hc.border,
            scrolledUnderElevation: 0.5,
            automaticallyImplyLeading: false,
            title: Text(l.settingsTitle),
            expandedHeight: 112,
            systemOverlayStyle: theme.brightness == Brightness.dark
                ? SystemUiOverlayStyle.light
                : SystemUiOverlayStyle.dark,
          ),

          SliverPadding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.md, AppSpacing.s2, AppSpacing.md, AppSpacing.lg,
            ),
            sliver: SliverList.list(
              children: [
                // ── Appearance ───────────────────────────────────────────
                HaynListSection(
                  title: l.settingsSectionAppearance,
                  children: [
                    HaynListCell(
                      leadingIcon: Icons.brightness_6_rounded,
                      label: l.settingsTheme,
                      value: _themeLabel(themeMode, l),
                      onTap: () => _pickTheme(context, ref, themeMode, l),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),

                // ── Language & Region ────────────────────────────────────
                HaynListSection(
                  title: l.settingsSectionLanguage,
                  children: [
                    HaynListCell(
                      leadingIcon: Icons.translate_rounded,
                      label: l.settingsLanguage,
                      value: _languageLabel(locale, l),
                      onTap: () => _pickLanguage(context, ref, locale, l),
                    ),
                    HaynListCell(
                      leadingIcon: Icons.tag_rounded,
                      label: l.settingsNumerals,
                      value: _numeralsLabel(numerals, l),
                      onTap: () => _pickNumerals(context, ref, numerals, l),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),

                // ── Defaults ─────────────────────────────────────────────
                HaynListSection(
                  title: l.settingsSectionDefaults,
                  children: [
                    HaynListCell(
                      leadingIcon: Icons.photo_size_select_actual_rounded,
                      label: l.settingsDefaultFormat,
                      value: _formatLabel(defaultFormat, l, caps),
                      onTap: () => _pickFormat(context, ref, defaultFormat, l),
                    ),
                    HaynListCell(
                      leadingIcon: Icons.tune_rounded,
                      label: l.settingsDefaultQuality,
                      value: _qualityLabel(defaultQuality, l),
                      onTap: () =>
                          _pickQuality(context, ref, defaultQuality, l),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),

                // ── Safety ───────────────────────────────────────────────
                HaynListSection(
                  title: l.settingsSectionSafety,
                  children: [
                    HaynListCell(
                      leadingIcon: Icons.delete_outline_rounded,
                      label: l.settingsTrashCell,
                      description: l.settingsTrashCellDesc,
                      onTap: () => context.push('/trash'),
                    ),
                    HaynListCell(
                      leadingIcon: Icons.restore_from_trash_rounded,
                      label: l.settingsTrashRetention,
                      value: l.settingsTrashDays(trashRetention),
                      onTap: () => _pickRetention(
                          context, ref, trashRetention, l),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),

                // ── About ────────────────────────────────────────────────
                HaynListSection(
                  title: l.settingsSectionAbout,
                  children: [
                    HaynListCell(
                      leadingIcon: Icons.info_outline_rounded,
                      label: l.aboutTitle,
                      onTap: () => _openAbout(context),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),

                // ── Privacy footer ───────────────────────────────────────
                Padding(
                  padding: const EdgeInsetsDirectional.symmetric(
                      horizontal: AppSpacing.md, vertical: AppSpacing.md),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.wifi_off_rounded, size: 14, color: hc.text3),
                      const SizedBox(width: AppSpacing.s2),
                      Expanded(
                        child: Text(
                          l.settingsPrivacy,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: hc.text3,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SliverPadding(padding: EdgeInsets.only(bottom: 96)),
        ],
      ),
    );
  }

  // ── Picker callbacks ────────────────────────────────────────────────────

  Future<void> _pickTheme(
    BuildContext context,
    WidgetRef ref,
    ThemeMode current,
    AppLocalizations l,
  ) async {
    await showHaynPickerSheet<ThemeMode>(
      context: context,
      title: l.settingsTheme,
      currentValue: current,
      onChanged: (v) => ref.read(themeProvider.notifier).setTheme(v),
      options: [
        HaynPickerOption(
          value: ThemeMode.system,
          label: l.settingsThemeSystem,
          icon: Icons.brightness_auto_rounded,
        ),
        HaynPickerOption(
          value: ThemeMode.light,
          label: l.settingsThemeLight,
          icon: Icons.light_mode_rounded,
        ),
        HaynPickerOption(
          value: ThemeMode.dark,
          label: l.settingsThemeDark,
          icon: Icons.dark_mode_rounded,
        ),
      ],
    );
  }

  Future<void> _pickLanguage(
    BuildContext context,
    WidgetRef ref,
    Locale? current,
    AppLocalizations l,
  ) async {
    const sentinel = 'system';
    await showHaynPickerSheet<String>(
      context: context,
      title: l.settingsLanguage,
      currentValue: current?.languageCode ?? sentinel,
      onChanged: (v) => ref.read(localeProvider.notifier).setLocale(
            v == sentinel ? null : Locale(v),
          ),
      options: [
        HaynPickerOption(
            value: sentinel,
            label: l.settingsLanguageSystem,
            icon: Icons.translate_rounded),
        HaynPickerOption(value: 'ar', label: l.settingsLangArabic),
        HaynPickerOption(value: 'en', label: l.settingsLangEnglish),
      ],
    );
  }

  Future<void> _pickNumerals(
    BuildContext context,
    WidgetRef ref,
    NumeralsStyle current,
    AppLocalizations l,
  ) async {
    await showHaynPickerSheet<NumeralsStyle>(
      context: context,
      title: l.settingsNumerals,
      currentValue: current,
      onChanged: (v) => ref.read(numeralsProvider.notifier).state = v,
      options: [
        HaynPickerOption(
            value: NumeralsStyle.latin, label: l.settingsNumeralsLatin),
        HaynPickerOption(
            value: NumeralsStyle.arabicIndic, label: l.settingsNumeralsArabic),
      ],
    );
  }

  Future<void> _pickFormat(
    BuildContext context,
    WidgetRef ref,
    DefaultFormat current,
    AppLocalizations l,
  ) async {
    final caps = ref.read(formatCapabilitiesProvider);
    final avifHardware =
        caps.supportsAvifHardware || await NativeAvifEncoder.isAvailable();
    final options = <HaynPickerOption<DefaultFormat>>[
      HaynPickerOption(
          value: DefaultFormat.auto,
          label: l.formatAuto,
          description: l.formatAutoDesc,
          icon: Icons.auto_awesome_rounded),
      HaynPickerOption(
          value: DefaultFormat.avif,
          label: 'AVIF',
          description: l.formatAvifDesc,
          warning: avifHardware ? null : l.formatAvifSoftwareWarning),
      if (caps.supportsHeic)
        HaynPickerOption(
            value: DefaultFormat.heic,
            label: 'HEIC',
            description: l.formatHeicDesc)
      else if (caps.supportsHeif)
        HaynPickerOption(
            value: DefaultFormat.heic,
            label: 'HEIF',
            description: l.formatHeicDesc),
      if (caps.supportsWebp)
        HaynPickerOption(
            value: DefaultFormat.webp,
            label: 'WebP',
            description: l.formatWebpDesc),
      HaynPickerOption(
          value: DefaultFormat.jpeg,
          label: 'JPEG',
          description: l.formatJpegDesc),
    ];

    if (!context.mounted) return;
    await showHaynPickerSheet<DefaultFormat>(
      context: context,
      title: l.settingsDefaultFormat,
      currentValue: current,
      onChanged: (v) => ref.read(defaultFormatProvider.notifier).state = v,
      options: options,
    );
  }

  Future<void> _pickQuality(
    BuildContext context,
    WidgetRef ref,
    DefaultQuality current,
    AppLocalizations l,
  ) async {
    await showHaynPickerSheet<DefaultQuality>(
      context: context,
      title: l.settingsDefaultQuality,
      currentValue: current,
      onChanged: (v) => ref.read(defaultQualityProvider.notifier).state = v,
      options: [
        HaynPickerOption(
          value: DefaultQuality.lightning,
          label: l.qualityLightning,
          description: l.qualityLightningDesc,
          icon: Icons.flash_on_rounded,
        ),
        HaynPickerOption(
          value: DefaultQuality.balanced,
          label: l.qualityBalanced,
          description: l.qualityBalancedDesc,
          icon: Icons.balance_rounded,
        ),
        HaynPickerOption(
          value: DefaultQuality.highest,
          label: l.qualityHighest,
          description: l.qualityHighestDesc,
          icon: Icons.diamond_outlined,
        ),
      ],
    );
  }

  Future<void> _pickRetention(
    BuildContext context,
    WidgetRef ref,
    int current,
    AppLocalizations l,
  ) async {
    await showHaynPickerSheet<int>(
      context: context,
      title: l.settingsTrashRetention,
      currentValue: current,
      onChanged: (v) => ref.read(trashRetentionProvider.notifier).state = v,
      options: [
        HaynPickerOption(value: 7, label: l.settingsTrashDays(7)),
        HaynPickerOption(value: 14, label: l.settingsTrashDays(14)),
        HaynPickerOption(value: 30, label: l.settingsTrashDays(30)),
      ],
    );
  }

  void _openAbout(BuildContext context) {
    HapticFeedback.selectionClick();
    context.push('/about');
  }

  // ── Label helpers ──────────────────────────────────────────────────────

  String _themeLabel(ThemeMode mode, AppLocalizations l) => switch (mode) {
        ThemeMode.system => l.settingsThemeSystem,
        ThemeMode.light => l.settingsThemeLight,
        ThemeMode.dark => l.settingsThemeDark,
      };

  String _languageLabel(Locale? locale, AppLocalizations l) {
    if (locale == null) return l.settingsLanguageSystem;
    return switch (locale.languageCode) {
      'ar' => l.settingsLangArabic,
      'en' => l.settingsLangEnglish,
      _ => locale.languageCode,
    };
  }

  String _numeralsLabel(NumeralsStyle n, AppLocalizations l) => switch (n) {
        NumeralsStyle.latin => l.settingsNumeralsLatin,
        NumeralsStyle.arabicIndic => l.settingsNumeralsArabic,
      };

  String _qualityLabel(DefaultQuality q, AppLocalizations l) => switch (q) {
        DefaultQuality.lightning => l.qualityLightning,
        DefaultQuality.balanced => l.qualityBalanced,
        DefaultQuality.highest => l.qualityHighest,
      };

  String _formatLabel(DefaultFormat f, AppLocalizations l, FormatCapabilities caps) {
    if (f == DefaultFormat.auto) {
      // Surface what Auto will actually use, e.g. "Auto · AVIF" — gives
      // the user a peek at the priority chain without opening the picker.
      final resolved = DefaultFormat.resolveAuto(caps);
      final resolvedLabel = DefaultFormat.labelFor(
        resolved,
        supportsHeic: caps.supportsHeic,
        supportsHeif: caps.supportsHeif,
      );
      return l.formatAutoResolved(resolvedLabel);
    }
    return DefaultFormat.labelFor(
      f,
      supportsHeic: caps.supportsHeic,
      supportsHeif: caps.supportsHeif,
    );
  }
}
