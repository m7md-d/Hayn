// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Hayn';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonDone => 'Done';

  @override
  String get commonContinue => 'Continue';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonClose => 'Close';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonSave => 'Save';

  @override
  String get commonExport => 'Export';

  @override
  String get commonStart => 'Start';

  @override
  String get tabLibrary => 'Library';

  @override
  String get tabTools => 'Tools';

  @override
  String get tabTasks => 'Tasks';

  @override
  String get tabSettings => 'Settings';

  @override
  String get libraryTitle => 'Library';

  @override
  String get filterAll => 'All';

  @override
  String get filterPhotos => 'Photos';

  @override
  String get filterVideos => 'Videos';

  @override
  String get libraryRecents => 'Recents';

  @override
  String get libraryAlbumsTitle => 'Albums';

  @override
  String get librarySearchAlbums => 'Search albums';

  @override
  String get librarySelectAll => 'Select all';

  @override
  String get librarySelectMode => 'Select';

  @override
  String get librarySelectionClearAll => 'Clear all';

  @override
  String get libraryPermissionTitle => 'No photo access';

  @override
  String get libraryPermissionMessage =>
      'Grant access to browse and process your photos and videos.';

  @override
  String get libraryPermissionButton => 'Grant access';

  @override
  String get libraryEmptyTitle => 'No media found';

  @override
  String get libraryEmptyMessage => 'Your library appears to be empty.';

  @override
  String librarySelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count selected',
      one: '1 selected',
    );
    return '$_temp0';
  }

  @override
  String get librarySortAndFilter => 'Sort & filter';

  @override
  String get librarySortBy => 'Sort by';

  @override
  String get librarySortNewest => 'Newest first';

  @override
  String get librarySortOldest => 'Oldest first';

  @override
  String get librarySortLargest => 'Largest first';

  @override
  String get librarySortSmallest => 'Smallest first';

  @override
  String get libraryFilterBySize => 'Size';

  @override
  String get libraryFilterAnySize => 'Any size';

  @override
  String get libraryFilterSmall => 'Under 1 MB';

  @override
  String get libraryFilterMedium => '1 – 10 MB';

  @override
  String get libraryFilterLarge => 'Over 10 MB';

  @override
  String get libraryFilterByFormat => 'Format';

  @override
  String get libraryFilterAnyFormat => 'Any format';

  @override
  String get libraryApplyFilters => 'Apply';

  @override
  String get libraryClearFilters => 'Clear';

  @override
  String get selectionCompress => 'Compress';

  @override
  String get selectionConvert => 'Convert';

  @override
  String get selectionInfo => 'Info';

  @override
  String get selectionStripMetadata => 'Clean data';

  @override
  String get selectionSurgical => 'Surgical';

  @override
  String get selectionMore => 'More';

  @override
  String get selectionDelete => 'Delete';

  @override
  String get selectionCancel => 'Cancel';

  @override
  String get toolsTitle => 'Tools';

  @override
  String get toolsSearch => 'Search tools';

  @override
  String get toolsComingSoon => 'Coming soon';

  @override
  String get toolsCompressGroup => 'Compress & convert';

  @override
  String get toolsEditGroup => 'Edit & cut';

  @override
  String get toolsAudioGroup => 'Audio';

  @override
  String get toolsAnimatedGroup => 'Animated & frames';

  @override
  String get toolsPrivacyGroup => 'Privacy & cleanup';

  @override
  String get toolCompressMedia => 'Compress media';

  @override
  String get toolCompressMediaDesc => 'Image, video, audio — any format';

  @override
  String get toolCompress => 'Compress';

  @override
  String get toolCompressDesc => 'Reduce file size';

  @override
  String get toolCrop => 'Crop';

  @override
  String get toolCropDesc => 'Crop & rotate';

  @override
  String get toolStripMetadata => 'Clean image data';

  @override
  String get toolStripDesc => 'Remove camera info & location';

  @override
  String get toolSurgicalReplace => 'Surgical replace';

  @override
  String get toolSurgicalDesc => 'Replace originals safely';

  @override
  String get toolTrim => 'Trim';

  @override
  String get toolTrimDesc => 'Lossless or smart cut';

  @override
  String get toolCropVideo => 'Crop';

  @override
  String get toolCropVideoDesc => 'Trim edges';

  @override
  String get toolCompressVideo => 'Compress';

  @override
  String get toolCompressVideoDesc => 'Reduce video size';

  @override
  String get toolRemoveAudio => 'Remove sound';

  @override
  String get toolRemoveAudioDesc => 'Mute video without quality loss';

  @override
  String get toolSeparateMusic => 'Remove music';

  @override
  String get toolSeparateDesc => 'Remove music, keep voices';

  @override
  String get toolAnimateFromVideo => 'Video → animated';

  @override
  String get toolAnimateFromVideoDesc => 'Loop a clip as GIF / WebP';

  @override
  String get toolAnimateFromPhotos => 'Photos → animated';

  @override
  String get toolAnimateFromPhotosDesc => 'Stitch frames into a loop';

  @override
  String get toolExtractFrames => 'Extract frames';

  @override
  String get toolExtractFramesDesc => 'Save still frames from video';

  @override
  String get tasksTitle => 'Tasks';

  @override
  String get tasksEmptyTitle => 'No active tasks';

  @override
  String get tasksEmptyMessage => 'Start a task from the Library or Tools.';

  @override
  String get tasksFilterAll => 'All';

  @override
  String get tasksFilterRunning => 'Running';

  @override
  String get tasksFilterDone => 'Done';

  @override
  String get tasksFilterFailed => 'Failed';

  @override
  String get tasksClearCompleted => 'Clear finished';

  @override
  String get taskCancelButton => 'Cancel';

  @override
  String get taskRetryButton => 'Retry';

  @override
  String get taskViewOutputButton => 'View';

  @override
  String taskItemsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count images',
      one: '1 image',
    );
    return '$_temp0';
  }

  @override
  String get taskOpenError => 'Couldn\'t open the result';

  @override
  String get taskRemove => 'Remove';

  @override
  String get taskTimeTaken => 'Time taken';

  @override
  String get taskQueuedLabel => 'Queued';

  @override
  String get taskOutputDeleted => 'The result is no longer on the device';

  @override
  String get timeJustNow => 'just now';

  @override
  String timeMinutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count min ago',
      one: '1 min ago',
    );
    return '$_temp0';
  }

  @override
  String timeHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hr ago',
      one: '1 hr ago',
    );
    return '$_temp0';
  }

  @override
  String timeDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days ago',
      one: '1 day ago',
    );
    return '$_temp0';
  }

  @override
  String get taskDoneLabel => 'Done';

  @override
  String get taskStatusPending => 'Pending';

  @override
  String get taskStatusRunning => 'Running';

  @override
  String get taskStatusCompleted => 'Done';

  @override
  String get taskStatusCancelled => 'Cancelled';

  @override
  String get taskStatusFailed => 'Failed';

  @override
  String get taskRemaining => 'remaining';

  @override
  String taskProgressLabel(String phase, int percent) {
    return '$phase — $percent%';
  }

  @override
  String taskSavedBytes(String bytes) {
    return 'Saved $bytes';
  }

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsSectionAppearance => 'Appearance';

  @override
  String get settingsSectionLanguage => 'Language & region';

  @override
  String get settingsSectionDefaults => 'Defaults';

  @override
  String get settingsSectionSafety => 'Safety';

  @override
  String get settingsSectionAbout => 'About';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguageSystem => 'System';

  @override
  String get settingsTheme => 'Appearance';

  @override
  String get settingsThemeSystem => 'System';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsLangArabic => 'Arabic';

  @override
  String get settingsLangEnglish => 'English';

  @override
  String get settingsNumerals => 'Numerals';

  @override
  String get settingsNumeralsLatin => 'Latin (123)';

  @override
  String get settingsNumeralsArabic => 'Arabic-Indic (١٢٣)';

  @override
  String get settingsDefaultFormat => 'Default format';

  @override
  String get settingsDefaultQuality => 'Default quality';

  @override
  String get settingsTrashRetention => 'Trash retention';

  @override
  String settingsTrashDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days',
      one: '1 day',
    );
    return '$_temp0';
  }

  @override
  String get settingsTrashCell => 'Trash';

  @override
  String get settingsTrashCellDesc => 'Recently replaced items';

  @override
  String get settingsAbout => 'About';

  @override
  String get settingsPrivacy =>
      'Works without internet — no network, no tracking.';

  @override
  String get settingsPrivacyTitle => 'Privacy';

  @override
  String get settingsLicenses => 'Open-source licenses';

  @override
  String get settingsVersion => 'Version';

  @override
  String get qualityLightning => 'Lightning';

  @override
  String get qualityLightningDesc => 'Fastest, lowest quality';

  @override
  String get qualityBalanced => 'Balanced';

  @override
  String get qualityBalancedDesc => 'Recommended';

  @override
  String get qualityHighest => 'Highest';

  @override
  String get qualityHighestDesc => 'Slowest, best quality';

  @override
  String get formatAuto => 'Auto';

  @override
  String get formatAutoDesc => 'Best for your device';

  @override
  String formatAutoResolved(String format) {
    return 'Auto · $format';
  }

  @override
  String get formatAvifDesc => 'Smallest, modern, royalty-free';

  @override
  String get formatAvifSoftwareWarning => 'A bit heavier on this device';

  @override
  String get formatHeicDesc => 'Same quality, half the size';

  @override
  String get formatWebpDesc => 'Smaller than JPEG, broadly supported';

  @override
  String get formatJpegDesc => 'Works on every device';

  @override
  String get formatPngDesc => 'Lossless — keeps transparency, larger files';

  @override
  String get aboutTitle => 'About Hayn';

  @override
  String get aboutTagline =>
      'A media studio that runs entirely on your device.';

  @override
  String get aboutPhilosophy =>
      'Hayn was built on a simple belief: the tools that touch your photos and videos should stay on your phone — not on someone\'s server. Every operation runs offline, no telemetry leaves the device, and the source is open so you can verify it yourself.';

  @override
  String get aboutSourceCode => 'Source code';

  @override
  String get aboutSourceCodeDesc => 'Read, fork, and self-build';

  @override
  String get aboutLicenseLine => 'Licensed under GPL-3.0';

  @override
  String get onboardingWelcomeTitle => 'Welcome to Hayn';

  @override
  String get onboardingWelcomeMessage =>
      'A media studio that runs entirely on your device.';

  @override
  String get onboardingPrivacyTitle => 'No internet needed';

  @override
  String get onboardingPrivacyMessage =>
      'No network, no tracking. Everything happens on your phone.';

  @override
  String get onboardingPermissionTitle => 'Access your photos';

  @override
  String get onboardingPermissionMessage =>
      'We need access so you can browse and edit your media. Nothing is uploaded.';

  @override
  String get onboardingPermissionGrant => 'Grant access';

  @override
  String get onboardingSkip => 'Maybe later';

  @override
  String get onboardingContinue => 'Continue';

  @override
  String get onboardingGetStarted => 'Get started';

  @override
  String get errorUnknown => 'Something went wrong.';

  @override
  String get errorFileAccess => 'Could not access file.';

  @override
  String get errorPermission => 'Permission denied.';

  @override
  String get errorEncoding => 'Encoding failed.';

  @override
  String get errorCancelled => 'Cancelled.';

  @override
  String get metaDimensions => 'Dimensions';

  @override
  String get metaSize => 'Size';

  @override
  String get metaDuration => 'Duration';

  @override
  String get metaLocation => 'Location';

  @override
  String get metaFormat => 'Format';

  @override
  String get metaMegapixels => 'Resolution';

  @override
  String get metaTechnical => 'Technical details';

  @override
  String get metaCamera => 'Camera';

  @override
  String get metaLens => 'Lens';

  @override
  String get metaExposure => 'Exposure';

  @override
  String get metaIso => 'ISO';

  @override
  String get metaBitrate => 'Bit rate';

  @override
  String get metaFrames => 'Frames';

  @override
  String get metaCodec => 'Codec';

  @override
  String get metaFrameRate => 'Frame rate';

  @override
  String get metaOpenInMaps => 'Open in Maps';

  @override
  String get metaBitDepth => 'Bit depth';

  @override
  String get metaTransparency => 'Transparency';

  @override
  String get metaDynamicRange => 'Dynamic range';

  @override
  String bitDepthBits(int n) {
    return '$n-bit';
  }

  @override
  String get commonYes => 'Yes';

  @override
  String get commonNo => 'No';

  @override
  String get assetDetailDone => 'Done';

  @override
  String assetDetailComingSoon(String name) {
    return '$name — coming in next phase';
  }

  @override
  String get actionShare => 'Share';

  @override
  String get actionDuplicate => 'Duplicate';

  @override
  String get actionMoreTitle => 'Options';

  @override
  String get deleteConfirmTitle => 'Delete from device?';

  @override
  String get deleteConfirmMessage =>
      'This removes it from your gallery. iOS keeps it in Recently Deleted for 30 days.';

  @override
  String get deleteDone => 'Deleted';

  @override
  String get duplicateDone => 'Duplicated';

  @override
  String get actionFailed => 'Something went wrong';

  @override
  String get shareLimitTitle => 'Share fewer at once';

  @override
  String shareLimitMessage(int count, int cap) {
    return 'You selected $count items, but only $cap can be shared at a time. Share the first $cap?';
  }

  @override
  String shareLimitConfirm(int cap) {
    return 'Share $cap';
  }

  @override
  String get sharePreparing => 'Preparing to share…';

  @override
  String get compressTitle => 'Compress';

  @override
  String get compressMode => 'Compression';

  @override
  String get compressModeAuto => 'Auto';

  @override
  String get compressModeAdvanced => 'Advanced';

  @override
  String get compressFormat => 'Format';

  @override
  String get compressQuality => 'Quality';

  @override
  String get compressEstimatedSize => 'Estimated size';

  @override
  String get compressEtaLabel => 'Est. time';

  @override
  String get compressKeepMeta => 'Keep photo info';

  @override
  String get compressKeepMetaDesc => 'Camera details and location (GPS)';

  @override
  String get compressKeepTime => 'Keep original time';

  @override
  String get compressKeepTimeDesc =>
      'Off: the copy is dated now and sorts to the top';

  @override
  String get compressBitDepth => 'Bit depth';

  @override
  String get compressBitDepthDesc =>
      'Colour precision per channel — HDR is kept either way';

  @override
  String get compressBitDepthMatch => 'Match';

  @override
  String compressBitDepthHigher(int n) {
    return 'Higher than the original ($n-bit) — no quality gain';
  }

  @override
  String get compressLowQ => 'Lower quality — smaller file';

  @override
  String get compressMidQ => 'Balanced';

  @override
  String get compressHighQ => 'Near-original — larger file';

  @override
  String compressAutoChose(String format) {
    return 'Auto picked $format — best balance for your device.';
  }

  @override
  String compressQueued(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count compression tasks queued',
      one: 'Compression task queued',
    );
    return '$_temp0';
  }

  @override
  String get surgicalBefore => 'Original';

  @override
  String get surgicalAfter => 'Replacement';

  @override
  String get surgicalSaved => 'Saved';

  @override
  String get surgicalConfirm => 'Confirm replace';

  @override
  String get surgicalPreserved => 'Preserved';

  @override
  String get surgicalPreservedFilename => 'Filename';

  @override
  String get surgicalPreservedCaptureDate => 'Capture date';

  @override
  String get surgicalPreservedGps => 'Location (GPS)';

  @override
  String get surgicalPreservedAllMeta => 'All image data';

  @override
  String get surgicalPreservedOrder => 'Library order';

  @override
  String get surgicalPreservedAlbumsTags => 'Albums, folder & tags';

  @override
  String get surgicalIosBadge => 'Delete & create';

  @override
  String get surgicalIosHint =>
      'May appear in \"Recently Added\" — timeline order preserved.';

  @override
  String get surgicalAndroidBadge => 'In place';

  @override
  String get surgicalAndroidHint =>
      'Stays in place — same album, folder, tags and order are kept, and the space is freed.';

  @override
  String get surgicalPreviewOnly =>
      'Preview ready — replacement turns on in the next update.';

  @override
  String get surgicalReplacing => 'Replacing…';

  @override
  String surgicalReplacedSaved(String size) {
    return 'Replaced · saved $size';
  }

  @override
  String get surgicalCancelled => 'Replacement cancelled — original untouched';

  @override
  String get surgicalVerifyFailed =>
      'Couldn\'t verify the new image — original kept';

  @override
  String surgicalReversible(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'Reversible from Trash for $days days',
      one: 'Reversible from Trash for 1 day',
    );
    return '$_temp0';
  }

  @override
  String get surgicalCompleted => 'Replacement complete';

  @override
  String get surgicalModeAuto => 'Auto';

  @override
  String get surgicalModeAdvanced => 'Advanced';

  @override
  String get surgicalKeepBackup => 'Keep original in trash';

  @override
  String get surgicalKeepBackupDesc => 'Restore any time before retention ends';

  @override
  String get surgicalSettingsAuto => 'Auto — best balance for your device';

  @override
  String get surgicalConfirmTitle => 'Replace original?';

  @override
  String get surgicalConfirmMessage =>
      'The original is moved to trash and reversible for the configured retention period.';

  @override
  String get compressOriginalLabel => 'Original';

  @override
  String get compressPreviewLabel => 'Preview';

  @override
  String get compressOpenComparison => 'Open comparison';

  @override
  String get compressComputing => 'Compressing…';

  @override
  String get compressAlphaFlattenWarning =>
      'JPEG can\'t keep transparency — your image will be saved in a transparency-safe format instead.';

  @override
  String stripMetadataQueued(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count metadata removals queued',
      one: 'Metadata removal queued',
    );
    return '$_temp0';
  }

  @override
  String get stripNothingFound => 'No removable metadata in this image';

  @override
  String get stripHeicUnsupported =>
      'This format can\'t be cleaned losslessly yet — use Compress (turn off \"Keep photo info\") to strip it without keeping quality artefacts.';

  @override
  String get videoOneAtATime => 'Open one video at a time for this tool';

  @override
  String get cropApplied => 'Crop applied';

  @override
  String get cropRotateCw => 'Rotate right';

  @override
  String get cropRotateCcw => 'Rotate left';

  @override
  String get cropFlipH => 'Flip';

  @override
  String get cropFlipV => 'Flip up';

  @override
  String get cropReset => 'Reset';

  @override
  String get cropRatioFree => 'Free';

  @override
  String get cropRatioOriginal => 'Original';

  @override
  String get removeAudioBadge => 'Audio off';

  @override
  String get removeAudioExplain =>
      'The video stream is copied untouched. Audio is removed with zero quality loss.';

  @override
  String get removeAudioActionLabel => 'Save without sound';

  @override
  String get removeAudioQueued => 'Saving without sound';

  @override
  String get trimActionLabel => 'Save trimmed clip';

  @override
  String get trimQueued => 'Saving trimmed clip';

  @override
  String get cropVideoQueued => 'Saving cropped video';

  @override
  String get trashTitle => 'Trash';

  @override
  String get trashEmptyAction => 'Empty';

  @override
  String get trashEmptyStateTitle => 'Trash is empty';

  @override
  String trashEmptyStateMessage(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other:
          'Items replaced surgically live here for $days days. Restore any time before they vanish.',
      one:
          'Items replaced surgically live here for 1 day. Restore any time before they vanish.',
    );
    return '$_temp0';
  }

  @override
  String trashRetentionBanner(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other:
          'Items in trash are gone after $days days. Restore brings them back.',
      one: 'Items in trash are gone after 1 day. Restore brings them back.',
    );
    return '$_temp0';
  }

  @override
  String get trashConfirmEmpty => 'Empty trash?';

  @override
  String get trashConfirmEmptyMsg =>
      'This permanently deletes all items in the trash. The current library is unaffected.';

  @override
  String get trashConfirmEmptyAll => 'Empty all';

  @override
  String get trashConfirmDelete => 'Delete permanently?';

  @override
  String trashConfirmDeleteMsg(String filename) {
    return '$filename will be erased forever.';
  }

  @override
  String trashRestored(String filename) {
    return 'Restored $filename';
  }

  @override
  String trashDaysLeft(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days left',
      one: '1 day left',
      zero: 'Expires today',
    );
    return '$_temp0';
  }

  @override
  String get trashRestoreTooltip => 'Restore';

  @override
  String get trashDeleteForeverTooltip => 'Delete forever';

  @override
  String get audioStrengthLabel => 'Separation strength';

  @override
  String get audioAutoBadge => 'Auto';

  @override
  String get audioResetToAuto => 'Reset to Auto';

  @override
  String get audioStrengthLight => 'Light — music slightly audible';

  @override
  String get audioStrengthBalanced => 'Balanced — recommended';

  @override
  String get audioStrengthAggressive => 'Aggressive — best isolation, slower';

  @override
  String get audioEstimatedTime => 'Estimated time';

  @override
  String get audioTip =>
      'Higher strength = longer time. Plug in for long clips and keep the screen on.';

  @override
  String get audioStartSeparation => 'Start separation';

  @override
  String get audioCompareResult => 'Compare result';

  @override
  String get audioOriginalLabel => 'Original';

  @override
  String get audioOriginalDesc => 'Music + voices';

  @override
  String get audioVocalsOnly => 'Voices only';

  @override
  String get audioVocalsOnlyDesc => 'Music removed';

  @override
  String get audioNewBadge => 'NEW';

  @override
  String get audioDiscardRedo => 'Discard & redo';

  @override
  String get audioCompareInstructions =>
      'Tap play on either track to compare. The voices-only version is what you save.';

  @override
  String get audioGeneratedOnDevice => 'Generated on this device.';

  @override
  String get animatedRange => 'Range';

  @override
  String get animatedLength => 'Length';

  @override
  String get animatedFormat => 'Format';

  @override
  String get animatedFrameRate => 'Frame rate';

  @override
  String get animatedFpsUnit => 'fps';

  @override
  String get animatedSize => 'Size';

  @override
  String get animatedEstimatedSize => 'Estimated size';

  @override
  String get animatedExport => 'Export';

  @override
  String get animatedExportQueued => 'Animated export queued';

  @override
  String get animatedPhotosExportQueued => 'Animated photo export queued';

  @override
  String get animatedReorderHint => 'Hold & drag to reorder';

  @override
  String animatedFramesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count frames',
      one: '1 frame',
    );
    return '$_temp0';
  }

  @override
  String get animatedLoop => 'Loop';

  @override
  String get animatedLoopDesc => 'Plays continuously when supported';

  @override
  String get animatedSelectAtLeast2 =>
      'Select at least 2 photos to create an animation.';

  @override
  String get animatedSlideshow => 'Slideshow pace';

  @override
  String get animatedSmooth => 'Smooth motion';

  @override
  String get animatedStandard => 'Standard';

  @override
  String get framesInterval => 'Interval';

  @override
  String get framesFps => 'Frame rate';

  @override
  String get framesSingle => 'Single';

  @override
  String get framesEvery => 'Every';

  @override
  String get framesPosition => 'Position';

  @override
  String get framesSecondsUnit => 's';

  @override
  String get framesSingleAtTimestamp => 'Single frame at this timestamp';

  @override
  String get framesPreview => 'Preview';

  @override
  String framesMore(int count) {
    return '+$count more';
  }

  @override
  String framesSaveCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Save $count frames',
      one: 'Save 1 frame',
    );
    return '$_temp0';
  }

  @override
  String framesSavingCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Saving $count frames…',
      one: 'Saving 1 frame…',
    );
    return '$_temp0';
  }

  @override
  String framesEstimatedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '≈ $count frames',
      one: '≈ 1 frame',
    );
    return '$_temp0';
  }

  @override
  String get videoEditorTitle => 'Edit video';

  @override
  String get videoEditorExport => 'Export';

  @override
  String get videoEditorExporting => 'Exporting…';

  @override
  String get videoEditorStart => 'Start';

  @override
  String get videoEditorEnd => 'End';

  @override
  String get videoEditorAspectRatio => 'Aspect ratio';

  @override
  String get videoEditorAspectFree => 'Free';

  @override
  String get videoEditorTrimLossless =>
      'Lossless trim — handles snap to keyframes. Instant + zero quality loss.';

  @override
  String get videoEditorTrimSmart =>
      'Smart cut — chosen edges need a brief one-pass re-encode for accuracy.';

  @override
  String get videoEditorCropWarning =>
      'Cropping requires a one-time re-encode.';

  @override
  String get videoEditorRemoveLossless =>
      'Removing sound is lossless — the video stream is copied untouched.';

  @override
  String get videoEditorCodec => 'Codec';

  @override
  String get videoEditorResolution => 'Resolution';

  @override
  String get videoEditorResolutionOriginal => 'Original';
}
