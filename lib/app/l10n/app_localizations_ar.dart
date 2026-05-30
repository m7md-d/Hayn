// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appName => 'هين';

  @override
  String get commonCancel => 'إلغاء';

  @override
  String get commonDone => 'تم';

  @override
  String get commonContinue => 'متابعة';

  @override
  String get commonRetry => 'إعادة المحاولة';

  @override
  String get commonClose => 'إغلاق';

  @override
  String get commonDelete => 'حذف';

  @override
  String get commonSave => 'حفظ';

  @override
  String get commonExport => 'تصدير';

  @override
  String get commonStart => 'ابدأ';

  @override
  String get tabLibrary => 'المكتبة';

  @override
  String get tabTools => 'الأدوات';

  @override
  String get tabTasks => 'المهام';

  @override
  String get tabSettings => 'الإعدادات';

  @override
  String get libraryTitle => 'المكتبة';

  @override
  String get filterAll => 'الكل';

  @override
  String get filterPhotos => 'صور';

  @override
  String get filterVideos => 'فيديو';

  @override
  String get libraryRecents => 'الأحدث';

  @override
  String get libraryAlbumsTitle => 'الألبومات';

  @override
  String get librarySearchAlbums => 'ابحث في الألبومات';

  @override
  String get librarySelectAll => 'تحديد الكل';

  @override
  String get librarySelectMode => 'تحديد';

  @override
  String get librarySelectionClearAll => 'إلغاء التحديد';

  @override
  String get libraryPermissionTitle => 'لا يوجد وصول للصور';

  @override
  String get libraryPermissionMessage =>
      'امنح الوصول لتتصفّح صورك وفيديوهاتك وتعالجها.';

  @override
  String get libraryPermissionButton => 'منح الوصول';

  @override
  String get libraryEmptyTitle => 'لا توجد وسائط';

  @override
  String get libraryEmptyMessage => 'يبدو أن مكتبتك فارغة.';

  @override
  String librarySelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count عنصرًا محدّدًا',
      many: '$count عنصرًا محدّدًا',
      few: '$count عناصر محدّدة',
      two: 'عنصران محدّدان',
      one: 'عنصر واحد محدّد',
    );
    return '$_temp0';
  }

  @override
  String get librarySortAndFilter => 'ترتيب وتصفية';

  @override
  String get librarySortBy => 'الترتيب حسب';

  @override
  String get librarySortNewest => 'الأحدث أولاً';

  @override
  String get librarySortOldest => 'الأقدم أولاً';

  @override
  String get librarySortLargest => 'الأكبر حجمًا أولاً';

  @override
  String get librarySortSmallest => 'الأصغر حجمًا أولاً';

  @override
  String get libraryFilterBySize => 'الحجم';

  @override
  String get libraryFilterAnySize => 'أي حجم';

  @override
  String get libraryFilterSmall => 'أقل من 1 ميجابايت';

  @override
  String get libraryFilterMedium => 'بين 1 و 10 ميجابايت';

  @override
  String get libraryFilterLarge => 'أكبر من 10 ميجابايت';

  @override
  String get libraryFilterByFormat => 'الصيغة';

  @override
  String get libraryFilterAnyFormat => 'أي صيغة';

  @override
  String get libraryApplyFilters => 'تطبيق';

  @override
  String get libraryClearFilters => 'مسح';

  @override
  String get selectionCompress => 'ضغط';

  @override
  String get selectionConvert => 'تحويل';

  @override
  String get selectionInfo => 'معلومات';

  @override
  String get selectionStripMetadata => 'تنظيف البيانات';

  @override
  String get selectionSurgical => 'استبدال';

  @override
  String get selectionMore => 'المزيد';

  @override
  String get selectionDelete => 'حذف';

  @override
  String get selectionCancel => 'إلغاء';

  @override
  String get toolsTitle => 'الأدوات';

  @override
  String get toolsSearch => 'ابحث في الأدوات';

  @override
  String get toolsComingSoon => 'قريبًا';

  @override
  String get toolsCompressGroup => 'ضغط وتحويل';

  @override
  String get toolsEditGroup => 'تعديل وقص';

  @override
  String get toolsAudioGroup => 'الصوت';

  @override
  String get toolsAnimatedGroup => 'المتحرّكة والفريمات';

  @override
  String get toolsPrivacyGroup => 'خصوصية وتنظيف';

  @override
  String get toolCompressMedia => 'ضغط الميديا';

  @override
  String get toolCompressMediaDesc => 'صورة، فيديو، صوت — أي صيغة';

  @override
  String get toolCompress => 'ضغط';

  @override
  String get toolCompressDesc => 'تقليل حجم الملف';

  @override
  String get toolCrop => 'قص';

  @override
  String get toolCropDesc => 'قص وتدوير';

  @override
  String get toolStripMetadata => 'تنظيف بيانات الصورة';

  @override
  String get toolStripDesc => 'إزالة معلومات الكاميرا والموقع';

  @override
  String get toolSurgicalReplace => 'استبدال جراحي';

  @override
  String get toolSurgicalDesc => 'استبدال الأصل بأمان';

  @override
  String get toolTrim => 'قص';

  @override
  String get toolTrimDesc => 'قص بلا فقد جودة، أو ذكي';

  @override
  String get toolCropVideo => 'قص الحواف';

  @override
  String get toolCropVideoDesc => 'اقطع حواف الإطار';

  @override
  String get toolCompressVideo => 'ضغط';

  @override
  String get toolCompressVideoDesc => 'تقليل حجم الفيديو';

  @override
  String get toolRemoveAudio => 'حذف الصوت';

  @override
  String get toolRemoveAudioDesc => 'إسكات الفيديو دون فقد جودته';

  @override
  String get toolSeparateMusic => 'إزالة الموسيقى';

  @override
  String get toolSeparateDesc => 'إزالة الموسيقى، إبقاء الأصوات';

  @override
  String get toolAnimateFromVideo => 'فيديو إلى متحرّكة';

  @override
  String get toolAnimateFromVideoDesc => 'حوّل مقطعًا إلى متحرّكة (GIF / WebP)';

  @override
  String get toolAnimateFromPhotos => 'صور إلى متحرّكة';

  @override
  String get toolAnimateFromPhotosDesc => 'اجمع صورًا في صورة متحرّكة';

  @override
  String get toolExtractFrames => 'استخراج فريمات';

  @override
  String get toolExtractFramesDesc => 'احفظ فريمات منفصلة من الفيديو';

  @override
  String get tasksTitle => 'المهام';

  @override
  String get tasksEmptyTitle => 'لا توجد مهام نشطة';

  @override
  String get tasksEmptyMessage => 'ابدأ مهمة من المكتبة أو الأدوات.';

  @override
  String get tasksFilterAll => 'الكل';

  @override
  String get tasksFilterRunning => 'جارية';

  @override
  String get tasksFilterDone => 'مكتملة';

  @override
  String get tasksFilterFailed => 'فاشلة';

  @override
  String get tasksClearCompleted => 'مسح المكتملة';

  @override
  String get taskCancelButton => 'إلغاء';

  @override
  String get taskRetryButton => 'إعادة المحاولة';

  @override
  String get taskViewOutputButton => 'عرض';

  @override
  String get taskDoneLabel => 'اكتمل';

  @override
  String get taskStatusPending => 'بالانتظار';

  @override
  String get taskStatusRunning => 'جارية';

  @override
  String get taskStatusCompleted => 'اكتملت';

  @override
  String get taskStatusCancelled => 'ملغاة';

  @override
  String get taskStatusFailed => 'فشلت';

  @override
  String get taskRemaining => 'متبقّية';

  @override
  String taskProgressLabel(String phase, int percent) {
    return '$phase — $percent٪';
  }

  @override
  String taskSavedBytes(String bytes) {
    return 'وُفّر $bytes';
  }

  @override
  String get settingsTitle => 'الإعدادات';

  @override
  String get settingsSectionAppearance => 'المظهر';

  @override
  String get settingsSectionLanguage => 'اللغة والمنطقة';

  @override
  String get settingsSectionDefaults => 'الافتراضيات';

  @override
  String get settingsSectionSafety => 'الأمان';

  @override
  String get settingsSectionAbout => 'حول التطبيق';

  @override
  String get settingsLanguage => 'اللغة';

  @override
  String get settingsLanguageSystem => 'لغة النظام';

  @override
  String get settingsTheme => 'السمة';

  @override
  String get settingsThemeSystem => 'تلقائي';

  @override
  String get settingsThemeLight => 'فاتح';

  @override
  String get settingsThemeDark => 'داكن';

  @override
  String get settingsLangArabic => 'العربية';

  @override
  String get settingsLangEnglish => 'الإنجليزية';

  @override
  String get settingsNumerals => 'شكل الأرقام';

  @override
  String get settingsNumeralsLatin => 'لاتينية (123)';

  @override
  String get settingsNumeralsArabic => 'عربية-هندية (١٢٣)';

  @override
  String get settingsDefaultFormat => 'الصيغة الافتراضية';

  @override
  String get settingsDefaultQuality => 'الجودة الافتراضية';

  @override
  String get settingsTrashRetention => 'مدة الاحتفاظ في سلة المهملات';

  @override
  String settingsTrashDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days يومًا',
      many: '$days يومًا',
      few: '$days أيام',
      two: 'يومان',
      one: 'يوم واحد',
    );
    return '$_temp0';
  }

  @override
  String get settingsTrashCell => 'سلة المهملات';

  @override
  String get settingsTrashCellDesc => 'العناصر المستبدلة مؤخّرًا';

  @override
  String get settingsAbout => 'حول التطبيق';

  @override
  String get settingsPrivacy =>
      'يعمل بدون إنترنت بالكامل — لا اتصال شبكة ولا تتبّع.';

  @override
  String get settingsPrivacyTitle => 'الخصوصية';

  @override
  String get settingsLicenses => 'تراخيص المكتبات المفتوحة المصدر';

  @override
  String get settingsVersion => 'الإصدار';

  @override
  String get qualityLightning => 'خاطف';

  @override
  String get qualityLightningDesc => 'الأسرع، أقل جودة';

  @override
  String get qualityBalanced => 'متوازن';

  @override
  String get qualityBalancedDesc => 'موصى به';

  @override
  String get qualityHighest => 'الأعلى';

  @override
  String get qualityHighestDesc => 'الأبطأ، أعلى جودة';

  @override
  String get formatAuto => 'تلقائي';

  @override
  String get formatAutoDesc => 'الأنسب لجهازك';

  @override
  String formatAutoResolved(String format) {
    return 'تلقائي · $format';
  }

  @override
  String get formatAvifDesc => 'الأصغر، حديث، خالٍ من الإتاوات';

  @override
  String get formatAvifSoftwareWarning => 'أثقل قليلًا على هذا الجهاز';

  @override
  String get formatHeicDesc => 'نفس الجودة، نصف الحجم';

  @override
  String get formatWebpDesc => 'أصغر من JPEG، مدعوم في كثير من البرامج';

  @override
  String get formatJpegDesc => 'يعمل على كل جهاز';

  @override
  String get aboutTitle => 'عن هين';

  @override
  String get aboutTagline => 'استوديو ميديا يعمل بالكامل على جهازك.';

  @override
  String get aboutPhilosophy =>
      'بُني هين على قناعة بسيطة: الأدوات التي تلمس صورك وفيديوهاتك يجب أن تبقى على جهازك — لا على خادم أحدهم. كل عملية تجري بلا إنترنت، ولا تُرسَل أي بيانات إلى الخارج، والشيفرة مفتوحة المصدر لتتحقّق بنفسك.';

  @override
  String get aboutSourceCode => 'الشيفرة المصدرية';

  @override
  String get aboutSourceCodeDesc => 'اقرأها، انسخها، أو ابنِها بنفسك';

  @override
  String get aboutLicenseLine => 'مرخَّص تحت GPL-3.0';

  @override
  String get onboardingWelcomeTitle => 'أهلًا بك في هين';

  @override
  String get onboardingWelcomeMessage =>
      'استوديو ميديا يعمل بالكامل على جهازك.';

  @override
  String get onboardingPrivacyTitle => 'لا حاجة لإنترنت';

  @override
  String get onboardingPrivacyMessage =>
      'لا اتصال بالشبكة ولا تتبّع. كل شيء يحدث على هاتفك.';

  @override
  String get onboardingPermissionTitle => 'الوصول إلى صورك';

  @override
  String get onboardingPermissionMessage =>
      'نحتاج الإذن لتتصفّح وسائطك وتعدّلها. لا شيء يُرفع إلى الإنترنت.';

  @override
  String get onboardingPermissionGrant => 'منح الإذن';

  @override
  String get onboardingSkip => 'لاحقًا';

  @override
  String get onboardingContinue => 'متابعة';

  @override
  String get onboardingGetStarted => 'هيا نبدأ';

  @override
  String get errorUnknown => 'حدث خطأ غير متوقّع.';

  @override
  String get errorFileAccess => 'تعذّر الوصول إلى الملف.';

  @override
  String get errorPermission => 'الإذن مرفوض.';

  @override
  String get errorEncoding => 'فشل الترميز.';

  @override
  String get errorCancelled => 'تم الإلغاء.';

  @override
  String get metaDimensions => 'الأبعاد';

  @override
  String get metaSize => 'الحجم';

  @override
  String get metaDuration => 'المدة';

  @override
  String get metaLocation => 'الموقع';

  @override
  String get assetDetailDone => 'تم';

  @override
  String assetDetailComingSoon(String name) {
    return '$name — قريبًا في المرحلة التالية';
  }

  @override
  String get compressTitle => 'ضغط';

  @override
  String get compressMode => 'وضع الضغط';

  @override
  String get compressModeAuto => 'تلقائي';

  @override
  String get compressModeAdvanced => 'متقدّم';

  @override
  String get compressFormat => 'الصيغة';

  @override
  String get compressQuality => 'الجودة';

  @override
  String get compressEstimatedSize => 'الحجم المتوقّع';

  @override
  String get compressKeepMeta => 'احفظ بيانات الصورة';

  @override
  String get compressKeepMetaDesc => 'ابقِ معلومات الكاميرا والتاريخ والموقع';

  @override
  String get compressLowQ => 'جودة أقل — حجم أصغر';

  @override
  String get compressMidQ => 'متوازن';

  @override
  String get compressHighQ => 'قرب الأصل — حجم أكبر';

  @override
  String compressAutoChose(String format) {
    return 'اختار التلقائي $format — أفضل توازن لجهازك.';
  }

  @override
  String compressQueued(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'أُضيفت $count مهمة ضغط',
      many: 'أُضيفت $count مهمة ضغط',
      few: 'أُضيفت $count مهام ضغط',
      two: 'أُضيفت مهمتا ضغط',
      one: 'أُضيفت مهمة ضغط',
    );
    return '$_temp0';
  }

  @override
  String get surgicalBefore => 'الأصل';

  @override
  String get surgicalAfter => 'البديل';

  @override
  String get surgicalSaved => 'التوفير';

  @override
  String get surgicalConfirm => 'تأكيد الاستبدال';

  @override
  String get surgicalPreserved => 'محفوظ';

  @override
  String get surgicalPreservedFilename => 'اسم الملف';

  @override
  String get surgicalPreservedCaptureDate => 'تاريخ الالتقاط';

  @override
  String get surgicalPreservedGps => 'الموقع (GPS)';

  @override
  String get surgicalPreservedAllMeta => 'كل بيانات الصورة';

  @override
  String get surgicalPreservedOrder => 'ترتيب المكتبة';

  @override
  String get surgicalIosBadge => 'حذف وإنشاء';

  @override
  String get surgicalIosHint =>
      'قد تظهر في «المضافة حديثًا» — الترتيب الزمني محفوظ.';

  @override
  String surgicalReversible(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'قابل للاستعادة من سلة المهملات لمدة $days يومًا',
      many: 'قابل للاستعادة من سلة المهملات لمدة $days يومًا',
      few: 'قابل للاستعادة من سلة المهملات لمدة $days أيام',
      two: 'قابل للاستعادة من سلة المهملات ليومين',
      one: 'قابل للاستعادة من سلة المهملات ليوم واحد',
    );
    return '$_temp0';
  }

  @override
  String get surgicalCompleted => 'اكتمل الاستبدال';

  @override
  String get surgicalModeAuto => 'تلقائي';

  @override
  String get surgicalModeAdvanced => 'متقدّم';

  @override
  String get surgicalKeepBackup => 'الاحتفاظ بالأصل في سلة المهملات';

  @override
  String get surgicalKeepBackupDesc => 'يمكنك استعادته قبل انتهاء مدة الاحتفاظ';

  @override
  String get surgicalSettingsAuto => 'تلقائي — أفضل توازن لجهازك';

  @override
  String get surgicalConfirmTitle => 'استبدال الأصل؟';

  @override
  String get surgicalConfirmMessage =>
      'ينتقل الأصل إلى سلة المهملات ويمكن استعادته خلال مدة الاحتفاظ المضبوطة.';

  @override
  String get compressOriginalLabel => 'الأصل';

  @override
  String get compressPreviewLabel => 'بعد الضغط';

  @override
  String get compressOpenComparison => 'افتح المقارنة';

  @override
  String get compressComputing => 'جارٍ الضغط…';

  @override
  String get compressAlphaFlattenWarning =>
      'JPEG لا يحفظ الشفافية — ستُحفظ صورتك بصيغة تحفظ الشفافية بدلًا من ذلك.';

  @override
  String get cropApplied => 'تم القص';

  @override
  String get cropRotateCw => 'تدوير يمين';

  @override
  String get cropRotateCcw => 'تدوير يسار';

  @override
  String get cropFlipH => 'قلب';

  @override
  String get cropFlipV => 'قلب رأسي';

  @override
  String get cropReset => 'إعادة تعيين';

  @override
  String get cropRatioFree => 'حر';

  @override
  String get cropRatioOriginal => 'الأصل';

  @override
  String get removeAudioBadge => 'بدون صوت';

  @override
  String get removeAudioExplain =>
      'يُنسخ مجرى الفيديو كما هو دون أي إعادة ترميز. تُحذف قناة الصوت بدون فقد جودة.';

  @override
  String get removeAudioActionLabel => 'احفظ بدون صوت';

  @override
  String get removeAudioQueued => 'جاري الحفظ بدون صوت';

  @override
  String get trimActionLabel => 'احفظ المقطع المقصوص';

  @override
  String get trimQueued => 'جاري حفظ المقطع المقصوص';

  @override
  String get cropVideoQueued => 'جاري حفظ الفيديو المقصوص';

  @override
  String get trashTitle => 'سلة المهملات';

  @override
  String get trashEmptyAction => 'إفراغ';

  @override
  String get trashEmptyStateTitle => 'السلة فارغة';

  @override
  String trashEmptyStateMessage(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other:
          'العناصر المستبدلة جراحيًا تبقى هنا لمدة $days يومًا. استعدها قبل أن تختفي.',
      many:
          'العناصر المستبدلة جراحيًا تبقى هنا لمدة $days يومًا. استعدها قبل أن تختفي.',
      few:
          'العناصر المستبدلة جراحيًا تبقى هنا لمدة $days أيام. استعدها قبل أن تختفي.',
      two:
          'العناصر المستبدلة جراحيًا تبقى هنا لمدة يومين. استعدها قبل أن تختفي.',
      one:
          'العناصر المستبدلة جراحيًا تبقى هنا لمدة يوم واحد. استعدها قبل أن تختفي.',
    );
    return '$_temp0';
  }

  @override
  String trashRetentionBanner(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other:
          'العناصر في السلة تُحذف بعد $days يومًا. الاستعادة تُرجعها للمكتبة.',
      many:
          'العناصر في السلة تُحذف بعد $days يومًا. الاستعادة تُرجعها للمكتبة.',
      few: 'العناصر في السلة تُحذف بعد $days أيام. الاستعادة تُرجعها للمكتبة.',
      two: 'العناصر في السلة تُحذف بعد يومين. الاستعادة تُرجعها للمكتبة.',
      one: 'العناصر في السلة تُحذف بعد يوم واحد. الاستعادة تُرجعها للمكتبة.',
    );
    return '$_temp0';
  }

  @override
  String get trashConfirmEmpty => 'إفراغ السلة؟';

  @override
  String get trashConfirmEmptyMsg =>
      'سيحذف هذا كل العناصر في السلة بشكل نهائي. لن تتأثّر المكتبة الحالية.';

  @override
  String get trashConfirmEmptyAll => 'إفراغ الكل';

  @override
  String get trashConfirmDelete => 'حذف نهائي؟';

  @override
  String trashConfirmDeleteMsg(String filename) {
    return 'سيُحذف $filename نهائيًا.';
  }

  @override
  String trashRestored(String filename) {
    return 'تم استعادة $filename';
  }

  @override
  String trashDaysLeft(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days يومًا متبقّيًا',
      many: '$days يومًا متبقّيًا',
      few: '$days أيام متبقّية',
      two: 'يومان متبقّيان',
      one: 'يوم واحد متبقّي',
      zero: 'ينتهي اليوم',
    );
    return '$_temp0';
  }

  @override
  String get trashRestoreTooltip => 'استعادة';

  @override
  String get trashDeleteForeverTooltip => 'حذف نهائي';

  @override
  String get audioStrengthLabel => 'قوة الفصل';

  @override
  String get audioAutoBadge => 'تلقائي';

  @override
  String get audioResetToAuto => 'العودة للتلقائي';

  @override
  String get audioStrengthLight => 'خفيف — الموسيقى مسموعة قليلًا';

  @override
  String get audioStrengthBalanced => 'متوازن — موصى به';

  @override
  String get audioStrengthAggressive => 'قوي — أفضل عزل، أبطأ';

  @override
  String get audioEstimatedTime => 'الوقت المتوقّع';

  @override
  String get audioTip =>
      'قوة أعلى = وقت أطول. وصّل الشاحن للمقاطع الطويلة وأبقِ الشاشة مضاءة.';

  @override
  String get audioStartSeparation => 'بدء الفصل';

  @override
  String get audioCompareResult => 'مقارنة النتيجة';

  @override
  String get audioOriginalLabel => 'الأصلي';

  @override
  String get audioOriginalDesc => 'موسيقى + أصوات';

  @override
  String get audioVocalsOnly => 'الأصوات فقط';

  @override
  String get audioVocalsOnlyDesc => 'أُزيلت الموسيقى';

  @override
  String get audioNewBadge => 'جديد';

  @override
  String get audioDiscardRedo => 'تجاهل وإعادة';

  @override
  String get audioCompareInstructions =>
      'اضغط تشغيل على أيٍّ من المقطعين للمقارنة. الأصوات فقط هي ما سيُحفظ.';

  @override
  String get audioGeneratedOnDevice => 'أُنتج على هذا الجهاز.';

  @override
  String get animatedRange => 'النطاق';

  @override
  String get animatedLength => 'الطول';

  @override
  String get animatedFormat => 'الصيغة';

  @override
  String get animatedFrameRate => 'معدّل الفريمات';

  @override
  String get animatedFpsUnit => 'فريم/ث';

  @override
  String get animatedSize => 'الحجم';

  @override
  String get animatedEstimatedSize => 'الحجم المتوقّع';

  @override
  String get animatedExport => 'تصدير';

  @override
  String get animatedExportQueued => 'أُضيفت مهمة التصدير';

  @override
  String get animatedPhotosExportQueued => 'أُضيفت مهمة تصدير الصورة المتحرّكة';

  @override
  String get animatedReorderHint => 'اضغط مطوّلًا ثم اسحب لإعادة الترتيب';

  @override
  String animatedFramesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count فريمًا',
      many: '$count فريمًا',
      few: '$count فريمات',
      two: 'فريمان',
      one: 'فريم واحد',
    );
    return '$_temp0';
  }

  @override
  String get animatedLoop => 'تكرار';

  @override
  String get animatedLoopDesc => 'تشغيل متواصل عند الدعم';

  @override
  String get animatedSelectAtLeast2 =>
      'اختر صورتين على الأقل لإنشاء صورة متحرّكة.';

  @override
  String get animatedSlideshow => 'إيقاع عرض شرائح';

  @override
  String get animatedSmooth => 'حركة سلسة';

  @override
  String get animatedStandard => 'قياسي';

  @override
  String get framesInterval => 'فاصل';

  @override
  String get framesFps => 'معدّل الفريمات';

  @override
  String get framesSingle => 'واحد';

  @override
  String get framesEvery => 'كل';

  @override
  String get framesPosition => 'الموقع';

  @override
  String get framesSecondsUnit => 'ث';

  @override
  String get framesSingleAtTimestamp => 'فريم واحد عند هذا التوقيت';

  @override
  String get framesPreview => 'معاينة';

  @override
  String framesMore(int count) {
    return '‎+$count المزيد';
  }

  @override
  String framesSaveCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'احفظ $count فريمًا',
      many: 'احفظ $count فريمًا',
      few: 'احفظ $count فريمات',
      two: 'احفظ فريمَين',
      one: 'احفظ فريمًا واحدًا',
    );
    return '$_temp0';
  }

  @override
  String framesSavingCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'يحفظ $count فريمًا…',
      many: 'يحفظ $count فريمًا…',
      few: 'يحفظ $count فريمات…',
      two: 'يحفظ فريمَين…',
      one: 'يحفظ فريمًا واحدًا…',
    );
    return '$_temp0';
  }

  @override
  String framesEstimatedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '≈ $count فريمًا',
      many: '≈ $count فريمًا',
      few: '≈ $count فريمات',
      two: '≈ فريمان',
      one: '≈ فريم واحد',
    );
    return '$_temp0';
  }

  @override
  String get videoEditorTitle => 'تعديل الفيديو';

  @override
  String get videoEditorExport => 'تصدير';

  @override
  String get videoEditorExporting => 'يجري التصدير…';

  @override
  String get videoEditorStart => 'البداية';

  @override
  String get videoEditorEnd => 'النهاية';

  @override
  String get videoEditorAspectRatio => 'نسبة العرض إلى الارتفاع';

  @override
  String get videoEditorAspectFree => 'حرّ';

  @override
  String get videoEditorTrimLossless =>
      'قص بلا فقد — المقابض تنطبق على الـ keyframes. فوري وبدون فقد جودة.';

  @override
  String get videoEditorTrimSmart =>
      'قص ذكي — الحواف المختارة تتطلّب إعادة ترميز خفيفة لمرّة واحدة.';

  @override
  String get videoEditorCropWarning => 'القص يتطلّب إعادة ترميز لمرّة واحدة.';

  @override
  String get videoEditorRemoveLossless =>
      'إزالة الصوت بدون فقد — يُنسخ تيار الفيديو كما هو.';

  @override
  String get videoEditorCodec => 'الترميز';

  @override
  String get videoEditorResolution => 'الدقّة';

  @override
  String get videoEditorResolutionOriginal => 'الأصلية';
}
