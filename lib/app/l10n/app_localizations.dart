import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en'),
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'Hayn'**
  String get appName;

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get commonDone;

  /// No description provided for @commonContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get commonContinue;

  /// No description provided for @commonRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry;

  /// No description provided for @commonClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// No description provided for @commonDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDelete;

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @commonExport.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get commonExport;

  /// No description provided for @commonStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get commonStart;

  /// No description provided for @tabLibrary.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get tabLibrary;

  /// No description provided for @tabTools.
  ///
  /// In en, this message translates to:
  /// **'Tools'**
  String get tabTools;

  /// No description provided for @tabTasks.
  ///
  /// In en, this message translates to:
  /// **'Tasks'**
  String get tabTasks;

  /// No description provided for @tabSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get tabSettings;

  /// No description provided for @libraryTitle.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get libraryTitle;

  /// No description provided for @filterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get filterAll;

  /// No description provided for @filterPhotos.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get filterPhotos;

  /// No description provided for @filterVideos.
  ///
  /// In en, this message translates to:
  /// **'Videos'**
  String get filterVideos;

  /// No description provided for @libraryRecents.
  ///
  /// In en, this message translates to:
  /// **'Recents'**
  String get libraryRecents;

  /// No description provided for @libraryAlbumsTitle.
  ///
  /// In en, this message translates to:
  /// **'Albums'**
  String get libraryAlbumsTitle;

  /// No description provided for @librarySearchAlbums.
  ///
  /// In en, this message translates to:
  /// **'Search albums'**
  String get librarySearchAlbums;

  /// No description provided for @librarySelectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get librarySelectAll;

  /// No description provided for @librarySelectMode.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get librarySelectMode;

  /// No description provided for @librarySelectionClearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get librarySelectionClearAll;

  /// No description provided for @libraryPermissionTitle.
  ///
  /// In en, this message translates to:
  /// **'No photo access'**
  String get libraryPermissionTitle;

  /// No description provided for @libraryPermissionMessage.
  ///
  /// In en, this message translates to:
  /// **'Grant access to browse and process your photos and videos.'**
  String get libraryPermissionMessage;

  /// No description provided for @libraryPermissionButton.
  ///
  /// In en, this message translates to:
  /// **'Grant access'**
  String get libraryPermissionButton;

  /// No description provided for @libraryEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No media found'**
  String get libraryEmptyTitle;

  /// No description provided for @libraryEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Your library appears to be empty.'**
  String get libraryEmptyMessage;

  /// No description provided for @librarySelectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count,plural, =1{1 selected} other{{count} selected}}'**
  String librarySelectedCount(int count);

  /// No description provided for @librarySortAndFilter.
  ///
  /// In en, this message translates to:
  /// **'Sort & filter'**
  String get librarySortAndFilter;

  /// No description provided for @librarySortBy.
  ///
  /// In en, this message translates to:
  /// **'Sort by'**
  String get librarySortBy;

  /// No description provided for @librarySortNewest.
  ///
  /// In en, this message translates to:
  /// **'Newest first'**
  String get librarySortNewest;

  /// No description provided for @librarySortOldest.
  ///
  /// In en, this message translates to:
  /// **'Oldest first'**
  String get librarySortOldest;

  /// No description provided for @librarySortLargest.
  ///
  /// In en, this message translates to:
  /// **'Largest first'**
  String get librarySortLargest;

  /// No description provided for @librarySortSmallest.
  ///
  /// In en, this message translates to:
  /// **'Smallest first'**
  String get librarySortSmallest;

  /// No description provided for @libraryFilterBySize.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get libraryFilterBySize;

  /// No description provided for @libraryFilterAnySize.
  ///
  /// In en, this message translates to:
  /// **'Any size'**
  String get libraryFilterAnySize;

  /// No description provided for @libraryFilterSmall.
  ///
  /// In en, this message translates to:
  /// **'Under 1 MB'**
  String get libraryFilterSmall;

  /// No description provided for @libraryFilterMedium.
  ///
  /// In en, this message translates to:
  /// **'1 – 10 MB'**
  String get libraryFilterMedium;

  /// No description provided for @libraryFilterLarge.
  ///
  /// In en, this message translates to:
  /// **'Over 10 MB'**
  String get libraryFilterLarge;

  /// No description provided for @libraryFilterByFormat.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get libraryFilterByFormat;

  /// No description provided for @libraryFilterAnyFormat.
  ///
  /// In en, this message translates to:
  /// **'Any format'**
  String get libraryFilterAnyFormat;

  /// No description provided for @libraryApplyFilters.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get libraryApplyFilters;

  /// No description provided for @libraryClearFilters.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get libraryClearFilters;

  /// No description provided for @selectionCompress.
  ///
  /// In en, this message translates to:
  /// **'Compress'**
  String get selectionCompress;

  /// No description provided for @selectionConvert.
  ///
  /// In en, this message translates to:
  /// **'Convert'**
  String get selectionConvert;

  /// No description provided for @selectionInfo.
  ///
  /// In en, this message translates to:
  /// **'Info'**
  String get selectionInfo;

  /// No description provided for @selectionStripMetadata.
  ///
  /// In en, this message translates to:
  /// **'Clean data'**
  String get selectionStripMetadata;

  /// No description provided for @selectionSurgical.
  ///
  /// In en, this message translates to:
  /// **'Surgical'**
  String get selectionSurgical;

  /// No description provided for @selectionMore.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get selectionMore;

  /// No description provided for @selectionDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get selectionDelete;

  /// No description provided for @selectionCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get selectionCancel;

  /// No description provided for @toolsTitle.
  ///
  /// In en, this message translates to:
  /// **'Tools'**
  String get toolsTitle;

  /// No description provided for @toolsSearch.
  ///
  /// In en, this message translates to:
  /// **'Search tools'**
  String get toolsSearch;

  /// No description provided for @toolsComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get toolsComingSoon;

  /// No description provided for @toolsCompressGroup.
  ///
  /// In en, this message translates to:
  /// **'Compress & convert'**
  String get toolsCompressGroup;

  /// No description provided for @toolsEditGroup.
  ///
  /// In en, this message translates to:
  /// **'Edit & cut'**
  String get toolsEditGroup;

  /// No description provided for @toolsAudioGroup.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get toolsAudioGroup;

  /// No description provided for @toolsAnimatedGroup.
  ///
  /// In en, this message translates to:
  /// **'Animated & frames'**
  String get toolsAnimatedGroup;

  /// No description provided for @toolsPrivacyGroup.
  ///
  /// In en, this message translates to:
  /// **'Privacy & cleanup'**
  String get toolsPrivacyGroup;

  /// No description provided for @toolCompressMedia.
  ///
  /// In en, this message translates to:
  /// **'Compress media'**
  String get toolCompressMedia;

  /// No description provided for @toolCompressMediaDesc.
  ///
  /// In en, this message translates to:
  /// **'Image, video, audio — any format'**
  String get toolCompressMediaDesc;

  /// No description provided for @toolCompress.
  ///
  /// In en, this message translates to:
  /// **'Compress'**
  String get toolCompress;

  /// No description provided for @toolCompressDesc.
  ///
  /// In en, this message translates to:
  /// **'Reduce file size'**
  String get toolCompressDesc;

  /// No description provided for @toolCrop.
  ///
  /// In en, this message translates to:
  /// **'Crop'**
  String get toolCrop;

  /// No description provided for @toolCropDesc.
  ///
  /// In en, this message translates to:
  /// **'Crop & rotate'**
  String get toolCropDesc;

  /// No description provided for @toolStripMetadata.
  ///
  /// In en, this message translates to:
  /// **'Clean image data'**
  String get toolStripMetadata;

  /// No description provided for @toolStripDesc.
  ///
  /// In en, this message translates to:
  /// **'Remove camera info & location'**
  String get toolStripDesc;

  /// No description provided for @toolSurgicalReplace.
  ///
  /// In en, this message translates to:
  /// **'Surgical replace'**
  String get toolSurgicalReplace;

  /// No description provided for @toolSurgicalDesc.
  ///
  /// In en, this message translates to:
  /// **'Replace originals safely'**
  String get toolSurgicalDesc;

  /// No description provided for @toolTrim.
  ///
  /// In en, this message translates to:
  /// **'Trim'**
  String get toolTrim;

  /// No description provided for @toolTrimDesc.
  ///
  /// In en, this message translates to:
  /// **'Lossless or smart cut'**
  String get toolTrimDesc;

  /// No description provided for @toolCropVideo.
  ///
  /// In en, this message translates to:
  /// **'Crop'**
  String get toolCropVideo;

  /// No description provided for @toolCropVideoDesc.
  ///
  /// In en, this message translates to:
  /// **'Trim edges'**
  String get toolCropVideoDesc;

  /// No description provided for @toolCompressVideo.
  ///
  /// In en, this message translates to:
  /// **'Compress'**
  String get toolCompressVideo;

  /// No description provided for @toolCompressVideoDesc.
  ///
  /// In en, this message translates to:
  /// **'Reduce video size'**
  String get toolCompressVideoDesc;

  /// No description provided for @toolRemoveAudio.
  ///
  /// In en, this message translates to:
  /// **'Remove sound'**
  String get toolRemoveAudio;

  /// No description provided for @toolRemoveAudioDesc.
  ///
  /// In en, this message translates to:
  /// **'Mute video without quality loss'**
  String get toolRemoveAudioDesc;

  /// No description provided for @toolSeparateMusic.
  ///
  /// In en, this message translates to:
  /// **'Remove music'**
  String get toolSeparateMusic;

  /// No description provided for @toolSeparateDesc.
  ///
  /// In en, this message translates to:
  /// **'Remove music, keep voices'**
  String get toolSeparateDesc;

  /// No description provided for @toolAnimateFromVideo.
  ///
  /// In en, this message translates to:
  /// **'Video → animated'**
  String get toolAnimateFromVideo;

  /// No description provided for @toolAnimateFromVideoDesc.
  ///
  /// In en, this message translates to:
  /// **'Loop a clip as GIF / WebP'**
  String get toolAnimateFromVideoDesc;

  /// No description provided for @toolAnimateFromPhotos.
  ///
  /// In en, this message translates to:
  /// **'Photos → animated'**
  String get toolAnimateFromPhotos;

  /// No description provided for @toolAnimateFromPhotosDesc.
  ///
  /// In en, this message translates to:
  /// **'Stitch frames into a loop'**
  String get toolAnimateFromPhotosDesc;

  /// No description provided for @toolExtractFrames.
  ///
  /// In en, this message translates to:
  /// **'Extract frames'**
  String get toolExtractFrames;

  /// No description provided for @toolExtractFramesDesc.
  ///
  /// In en, this message translates to:
  /// **'Save still frames from video'**
  String get toolExtractFramesDesc;

  /// No description provided for @tasksTitle.
  ///
  /// In en, this message translates to:
  /// **'Tasks'**
  String get tasksTitle;

  /// No description provided for @tasksEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No active tasks'**
  String get tasksEmptyTitle;

  /// No description provided for @tasksEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Start a task from the Library or Tools.'**
  String get tasksEmptyMessage;

  /// No description provided for @tasksFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get tasksFilterAll;

  /// No description provided for @tasksFilterRunning.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get tasksFilterRunning;

  /// No description provided for @tasksFilterDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get tasksFilterDone;

  /// No description provided for @tasksFilterFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get tasksFilterFailed;

  /// No description provided for @tasksClearCompleted.
  ///
  /// In en, this message translates to:
  /// **'Clear finished'**
  String get tasksClearCompleted;

  /// No description provided for @taskCancelButton.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get taskCancelButton;

  /// No description provided for @taskRetryButton.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get taskRetryButton;

  /// No description provided for @taskViewOutputButton.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get taskViewOutputButton;

  /// No description provided for @taskItemsCount.
  ///
  /// In en, this message translates to:
  /// **'{count,plural, =1{1 image} other{{count} images}}'**
  String taskItemsCount(int count);

  /// No description provided for @taskOpenError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the result'**
  String get taskOpenError;

  /// No description provided for @taskRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get taskRemove;

  /// No description provided for @taskDoneLabel.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get taskDoneLabel;

  /// No description provided for @taskStatusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get taskStatusPending;

  /// No description provided for @taskStatusRunning.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get taskStatusRunning;

  /// No description provided for @taskStatusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get taskStatusCompleted;

  /// No description provided for @taskStatusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get taskStatusCancelled;

  /// No description provided for @taskStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get taskStatusFailed;

  /// No description provided for @taskRemaining.
  ///
  /// In en, this message translates to:
  /// **'remaining'**
  String get taskRemaining;

  /// No description provided for @taskProgressLabel.
  ///
  /// In en, this message translates to:
  /// **'{phase} — {percent}%'**
  String taskProgressLabel(String phase, int percent);

  /// No description provided for @taskSavedBytes.
  ///
  /// In en, this message translates to:
  /// **'Saved {bytes}'**
  String taskSavedBytes(String bytes);

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsSectionAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsSectionAppearance;

  /// No description provided for @settingsSectionLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language & region'**
  String get settingsSectionLanguage;

  /// No description provided for @settingsSectionDefaults.
  ///
  /// In en, this message translates to:
  /// **'Defaults'**
  String get settingsSectionDefaults;

  /// No description provided for @settingsSectionSafety.
  ///
  /// In en, this message translates to:
  /// **'Safety'**
  String get settingsSectionSafety;

  /// No description provided for @settingsSectionAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsSectionAbout;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @settingsLanguageSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsLanguageSystem;

  /// No description provided for @settingsTheme.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsTheme;

  /// No description provided for @settingsThemeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsThemeSystem;

  /// No description provided for @settingsThemeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsThemeLight;

  /// No description provided for @settingsThemeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsThemeDark;

  /// No description provided for @settingsLangArabic.
  ///
  /// In en, this message translates to:
  /// **'Arabic'**
  String get settingsLangArabic;

  /// No description provided for @settingsLangEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get settingsLangEnglish;

  /// No description provided for @settingsNumerals.
  ///
  /// In en, this message translates to:
  /// **'Numerals'**
  String get settingsNumerals;

  /// No description provided for @settingsNumeralsLatin.
  ///
  /// In en, this message translates to:
  /// **'Latin (123)'**
  String get settingsNumeralsLatin;

  /// No description provided for @settingsNumeralsArabic.
  ///
  /// In en, this message translates to:
  /// **'Arabic-Indic (١٢٣)'**
  String get settingsNumeralsArabic;

  /// No description provided for @settingsDefaultFormat.
  ///
  /// In en, this message translates to:
  /// **'Default format'**
  String get settingsDefaultFormat;

  /// No description provided for @settingsDefaultQuality.
  ///
  /// In en, this message translates to:
  /// **'Default quality'**
  String get settingsDefaultQuality;

  /// No description provided for @settingsTrashRetention.
  ///
  /// In en, this message translates to:
  /// **'Trash retention'**
  String get settingsTrashRetention;

  /// No description provided for @settingsTrashDays.
  ///
  /// In en, this message translates to:
  /// **'{days,plural, =1{1 day} other{{days} days}}'**
  String settingsTrashDays(int days);

  /// No description provided for @settingsTrashCell.
  ///
  /// In en, this message translates to:
  /// **'Trash'**
  String get settingsTrashCell;

  /// No description provided for @settingsTrashCellDesc.
  ///
  /// In en, this message translates to:
  /// **'Recently replaced items'**
  String get settingsTrashCellDesc;

  /// No description provided for @settingsAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsAbout;

  /// No description provided for @settingsPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Works without internet — no network, no tracking.'**
  String get settingsPrivacy;

  /// No description provided for @settingsPrivacyTitle.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get settingsPrivacyTitle;

  /// No description provided for @settingsLicenses.
  ///
  /// In en, this message translates to:
  /// **'Open-source licenses'**
  String get settingsLicenses;

  /// No description provided for @settingsVersion.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get settingsVersion;

  /// No description provided for @qualityLightning.
  ///
  /// In en, this message translates to:
  /// **'Lightning'**
  String get qualityLightning;

  /// No description provided for @qualityLightningDesc.
  ///
  /// In en, this message translates to:
  /// **'Fastest, lowest quality'**
  String get qualityLightningDesc;

  /// No description provided for @qualityBalanced.
  ///
  /// In en, this message translates to:
  /// **'Balanced'**
  String get qualityBalanced;

  /// No description provided for @qualityBalancedDesc.
  ///
  /// In en, this message translates to:
  /// **'Recommended'**
  String get qualityBalancedDesc;

  /// No description provided for @qualityHighest.
  ///
  /// In en, this message translates to:
  /// **'Highest'**
  String get qualityHighest;

  /// No description provided for @qualityHighestDesc.
  ///
  /// In en, this message translates to:
  /// **'Slowest, best quality'**
  String get qualityHighestDesc;

  /// No description provided for @formatAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get formatAuto;

  /// No description provided for @formatAutoDesc.
  ///
  /// In en, this message translates to:
  /// **'Best for your device'**
  String get formatAutoDesc;

  /// No description provided for @formatAutoResolved.
  ///
  /// In en, this message translates to:
  /// **'Auto · {format}'**
  String formatAutoResolved(String format);

  /// No description provided for @formatAvifDesc.
  ///
  /// In en, this message translates to:
  /// **'Smallest, modern, royalty-free'**
  String get formatAvifDesc;

  /// No description provided for @formatAvifSoftwareWarning.
  ///
  /// In en, this message translates to:
  /// **'A bit heavier on this device'**
  String get formatAvifSoftwareWarning;

  /// No description provided for @formatHeicDesc.
  ///
  /// In en, this message translates to:
  /// **'Same quality, half the size'**
  String get formatHeicDesc;

  /// No description provided for @formatWebpDesc.
  ///
  /// In en, this message translates to:
  /// **'Smaller than JPEG, broadly supported'**
  String get formatWebpDesc;

  /// No description provided for @formatJpegDesc.
  ///
  /// In en, this message translates to:
  /// **'Works on every device'**
  String get formatJpegDesc;

  /// No description provided for @formatPngDesc.
  ///
  /// In en, this message translates to:
  /// **'Lossless — keeps transparency, larger files'**
  String get formatPngDesc;

  /// No description provided for @aboutTitle.
  ///
  /// In en, this message translates to:
  /// **'About Hayn'**
  String get aboutTitle;

  /// No description provided for @aboutTagline.
  ///
  /// In en, this message translates to:
  /// **'A media studio that runs entirely on your device.'**
  String get aboutTagline;

  /// No description provided for @aboutPhilosophy.
  ///
  /// In en, this message translates to:
  /// **'Hayn was built on a simple belief: the tools that touch your photos and videos should stay on your phone — not on someone\'s server. Every operation runs offline, no telemetry leaves the device, and the source is open so you can verify it yourself.'**
  String get aboutPhilosophy;

  /// No description provided for @aboutSourceCode.
  ///
  /// In en, this message translates to:
  /// **'Source code'**
  String get aboutSourceCode;

  /// No description provided for @aboutSourceCodeDesc.
  ///
  /// In en, this message translates to:
  /// **'Read, fork, and self-build'**
  String get aboutSourceCodeDesc;

  /// No description provided for @aboutLicenseLine.
  ///
  /// In en, this message translates to:
  /// **'Licensed under GPL-3.0'**
  String get aboutLicenseLine;

  /// No description provided for @onboardingWelcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome to Hayn'**
  String get onboardingWelcomeTitle;

  /// No description provided for @onboardingWelcomeMessage.
  ///
  /// In en, this message translates to:
  /// **'A media studio that runs entirely on your device.'**
  String get onboardingWelcomeMessage;

  /// No description provided for @onboardingPrivacyTitle.
  ///
  /// In en, this message translates to:
  /// **'No internet needed'**
  String get onboardingPrivacyTitle;

  /// No description provided for @onboardingPrivacyMessage.
  ///
  /// In en, this message translates to:
  /// **'No network, no tracking. Everything happens on your phone.'**
  String get onboardingPrivacyMessage;

  /// No description provided for @onboardingPermissionTitle.
  ///
  /// In en, this message translates to:
  /// **'Access your photos'**
  String get onboardingPermissionTitle;

  /// No description provided for @onboardingPermissionMessage.
  ///
  /// In en, this message translates to:
  /// **'We need access so you can browse and edit your media. Nothing is uploaded.'**
  String get onboardingPermissionMessage;

  /// No description provided for @onboardingPermissionGrant.
  ///
  /// In en, this message translates to:
  /// **'Grant access'**
  String get onboardingPermissionGrant;

  /// No description provided for @onboardingSkip.
  ///
  /// In en, this message translates to:
  /// **'Maybe later'**
  String get onboardingSkip;

  /// No description provided for @onboardingContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get onboardingContinue;

  /// No description provided for @onboardingGetStarted.
  ///
  /// In en, this message translates to:
  /// **'Get started'**
  String get onboardingGetStarted;

  /// No description provided for @errorUnknown.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong.'**
  String get errorUnknown;

  /// No description provided for @errorFileAccess.
  ///
  /// In en, this message translates to:
  /// **'Could not access file.'**
  String get errorFileAccess;

  /// No description provided for @errorPermission.
  ///
  /// In en, this message translates to:
  /// **'Permission denied.'**
  String get errorPermission;

  /// No description provided for @errorEncoding.
  ///
  /// In en, this message translates to:
  /// **'Encoding failed.'**
  String get errorEncoding;

  /// No description provided for @errorCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled.'**
  String get errorCancelled;

  /// No description provided for @metaDimensions.
  ///
  /// In en, this message translates to:
  /// **'Dimensions'**
  String get metaDimensions;

  /// No description provided for @metaSize.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get metaSize;

  /// No description provided for @metaDuration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get metaDuration;

  /// No description provided for @metaLocation.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get metaLocation;

  /// No description provided for @metaFormat.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get metaFormat;

  /// No description provided for @metaMegapixels.
  ///
  /// In en, this message translates to:
  /// **'Resolution'**
  String get metaMegapixels;

  /// No description provided for @metaTechnical.
  ///
  /// In en, this message translates to:
  /// **'Technical details'**
  String get metaTechnical;

  /// No description provided for @metaCamera.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get metaCamera;

  /// No description provided for @metaLens.
  ///
  /// In en, this message translates to:
  /// **'Lens'**
  String get metaLens;

  /// No description provided for @metaExposure.
  ///
  /// In en, this message translates to:
  /// **'Exposure'**
  String get metaExposure;

  /// No description provided for @metaIso.
  ///
  /// In en, this message translates to:
  /// **'ISO'**
  String get metaIso;

  /// No description provided for @assetDetailDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get assetDetailDone;

  /// No description provided for @assetDetailComingSoon.
  ///
  /// In en, this message translates to:
  /// **'{name} — coming in next phase'**
  String assetDetailComingSoon(String name);

  /// No description provided for @compressTitle.
  ///
  /// In en, this message translates to:
  /// **'Compress'**
  String get compressTitle;

  /// No description provided for @compressMode.
  ///
  /// In en, this message translates to:
  /// **'Compression'**
  String get compressMode;

  /// No description provided for @compressModeAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get compressModeAuto;

  /// No description provided for @compressModeAdvanced.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get compressModeAdvanced;

  /// No description provided for @compressFormat.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get compressFormat;

  /// No description provided for @compressQuality.
  ///
  /// In en, this message translates to:
  /// **'Quality'**
  String get compressQuality;

  /// No description provided for @compressEstimatedSize.
  ///
  /// In en, this message translates to:
  /// **'Estimated size'**
  String get compressEstimatedSize;

  /// No description provided for @compressKeepMeta.
  ///
  /// In en, this message translates to:
  /// **'Keep photo info'**
  String get compressKeepMeta;

  /// No description provided for @compressKeepMetaDesc.
  ///
  /// In en, this message translates to:
  /// **'Camera details and location (GPS)'**
  String get compressKeepMetaDesc;

  /// No description provided for @compressKeepTime.
  ///
  /// In en, this message translates to:
  /// **'Keep original time'**
  String get compressKeepTime;

  /// No description provided for @compressKeepTimeDesc.
  ///
  /// In en, this message translates to:
  /// **'Off: the copy is dated now and sorts to the top'**
  String get compressKeepTimeDesc;

  /// No description provided for @compressLowQ.
  ///
  /// In en, this message translates to:
  /// **'Lower quality — smaller file'**
  String get compressLowQ;

  /// No description provided for @compressMidQ.
  ///
  /// In en, this message translates to:
  /// **'Balanced'**
  String get compressMidQ;

  /// No description provided for @compressHighQ.
  ///
  /// In en, this message translates to:
  /// **'Near-original — larger file'**
  String get compressHighQ;

  /// No description provided for @compressAutoChose.
  ///
  /// In en, this message translates to:
  /// **'Auto picked {format} — best balance for your device.'**
  String compressAutoChose(String format);

  /// No description provided for @compressQueued.
  ///
  /// In en, this message translates to:
  /// **'{count,plural, =1{Compression task queued} other{{count} compression tasks queued}}'**
  String compressQueued(int count);

  /// No description provided for @surgicalBefore.
  ///
  /// In en, this message translates to:
  /// **'Original'**
  String get surgicalBefore;

  /// No description provided for @surgicalAfter.
  ///
  /// In en, this message translates to:
  /// **'Replacement'**
  String get surgicalAfter;

  /// No description provided for @surgicalSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get surgicalSaved;

  /// No description provided for @surgicalConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm replace'**
  String get surgicalConfirm;

  /// No description provided for @surgicalPreserved.
  ///
  /// In en, this message translates to:
  /// **'Preserved'**
  String get surgicalPreserved;

  /// No description provided for @surgicalPreservedFilename.
  ///
  /// In en, this message translates to:
  /// **'Filename'**
  String get surgicalPreservedFilename;

  /// No description provided for @surgicalPreservedCaptureDate.
  ///
  /// In en, this message translates to:
  /// **'Capture date'**
  String get surgicalPreservedCaptureDate;

  /// No description provided for @surgicalPreservedGps.
  ///
  /// In en, this message translates to:
  /// **'Location (GPS)'**
  String get surgicalPreservedGps;

  /// No description provided for @surgicalPreservedAllMeta.
  ///
  /// In en, this message translates to:
  /// **'All image data'**
  String get surgicalPreservedAllMeta;

  /// No description provided for @surgicalPreservedOrder.
  ///
  /// In en, this message translates to:
  /// **'Library order'**
  String get surgicalPreservedOrder;

  /// No description provided for @surgicalIosBadge.
  ///
  /// In en, this message translates to:
  /// **'Delete & create'**
  String get surgicalIosBadge;

  /// No description provided for @surgicalIosHint.
  ///
  /// In en, this message translates to:
  /// **'May appear in \"Recently Added\" — timeline order preserved.'**
  String get surgicalIosHint;

  /// No description provided for @surgicalReversible.
  ///
  /// In en, this message translates to:
  /// **'{days,plural, =1{Reversible from Trash for 1 day} other{Reversible from Trash for {days} days}}'**
  String surgicalReversible(int days);

  /// No description provided for @surgicalCompleted.
  ///
  /// In en, this message translates to:
  /// **'Replacement complete'**
  String get surgicalCompleted;

  /// No description provided for @surgicalModeAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get surgicalModeAuto;

  /// No description provided for @surgicalModeAdvanced.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get surgicalModeAdvanced;

  /// No description provided for @surgicalKeepBackup.
  ///
  /// In en, this message translates to:
  /// **'Keep original in trash'**
  String get surgicalKeepBackup;

  /// No description provided for @surgicalKeepBackupDesc.
  ///
  /// In en, this message translates to:
  /// **'Restore any time before retention ends'**
  String get surgicalKeepBackupDesc;

  /// No description provided for @surgicalSettingsAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto — best balance for your device'**
  String get surgicalSettingsAuto;

  /// No description provided for @surgicalConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Replace original?'**
  String get surgicalConfirmTitle;

  /// No description provided for @surgicalConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'The original is moved to trash and reversible for the configured retention period.'**
  String get surgicalConfirmMessage;

  /// No description provided for @compressOriginalLabel.
  ///
  /// In en, this message translates to:
  /// **'Original'**
  String get compressOriginalLabel;

  /// No description provided for @compressPreviewLabel.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get compressPreviewLabel;

  /// No description provided for @compressOpenComparison.
  ///
  /// In en, this message translates to:
  /// **'Open comparison'**
  String get compressOpenComparison;

  /// No description provided for @compressComputing.
  ///
  /// In en, this message translates to:
  /// **'Compressing…'**
  String get compressComputing;

  /// No description provided for @compressAlphaFlattenWarning.
  ///
  /// In en, this message translates to:
  /// **'JPEG can\'t keep transparency — your image will be saved in a transparency-safe format instead.'**
  String get compressAlphaFlattenWarning;

  /// No description provided for @stripMetadataQueued.
  ///
  /// In en, this message translates to:
  /// **'{count,plural, =1{Metadata removal queued} other{{count} metadata removals queued}}'**
  String stripMetadataQueued(num count);

  /// No description provided for @stripNothingFound.
  ///
  /// In en, this message translates to:
  /// **'No removable metadata in this image'**
  String get stripNothingFound;

  /// No description provided for @stripHeicUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This format can\'t be cleaned losslessly yet — use Compress (turn off \"Keep photo info\") to strip it without keeping quality artefacts.'**
  String get stripHeicUnsupported;

  /// No description provided for @videoOneAtATime.
  ///
  /// In en, this message translates to:
  /// **'Open one video at a time for this tool'**
  String get videoOneAtATime;

  /// No description provided for @cropApplied.
  ///
  /// In en, this message translates to:
  /// **'Crop applied'**
  String get cropApplied;

  /// No description provided for @cropRotateCw.
  ///
  /// In en, this message translates to:
  /// **'Rotate right'**
  String get cropRotateCw;

  /// No description provided for @cropRotateCcw.
  ///
  /// In en, this message translates to:
  /// **'Rotate left'**
  String get cropRotateCcw;

  /// No description provided for @cropFlipH.
  ///
  /// In en, this message translates to:
  /// **'Flip'**
  String get cropFlipH;

  /// No description provided for @cropFlipV.
  ///
  /// In en, this message translates to:
  /// **'Flip up'**
  String get cropFlipV;

  /// No description provided for @cropReset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get cropReset;

  /// No description provided for @cropRatioFree.
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get cropRatioFree;

  /// No description provided for @cropRatioOriginal.
  ///
  /// In en, this message translates to:
  /// **'Original'**
  String get cropRatioOriginal;

  /// No description provided for @removeAudioBadge.
  ///
  /// In en, this message translates to:
  /// **'Audio off'**
  String get removeAudioBadge;

  /// No description provided for @removeAudioExplain.
  ///
  /// In en, this message translates to:
  /// **'The video stream is copied untouched. Audio is removed with zero quality loss.'**
  String get removeAudioExplain;

  /// No description provided for @removeAudioActionLabel.
  ///
  /// In en, this message translates to:
  /// **'Save without sound'**
  String get removeAudioActionLabel;

  /// No description provided for @removeAudioQueued.
  ///
  /// In en, this message translates to:
  /// **'Saving without sound'**
  String get removeAudioQueued;

  /// No description provided for @trimActionLabel.
  ///
  /// In en, this message translates to:
  /// **'Save trimmed clip'**
  String get trimActionLabel;

  /// No description provided for @trimQueued.
  ///
  /// In en, this message translates to:
  /// **'Saving trimmed clip'**
  String get trimQueued;

  /// No description provided for @cropVideoQueued.
  ///
  /// In en, this message translates to:
  /// **'Saving cropped video'**
  String get cropVideoQueued;

  /// No description provided for @trashTitle.
  ///
  /// In en, this message translates to:
  /// **'Trash'**
  String get trashTitle;

  /// No description provided for @trashEmptyAction.
  ///
  /// In en, this message translates to:
  /// **'Empty'**
  String get trashEmptyAction;

  /// No description provided for @trashEmptyStateTitle.
  ///
  /// In en, this message translates to:
  /// **'Trash is empty'**
  String get trashEmptyStateTitle;

  /// No description provided for @trashEmptyStateMessage.
  ///
  /// In en, this message translates to:
  /// **'{days,plural, =1{Items replaced surgically live here for 1 day. Restore any time before they vanish.} other{Items replaced surgically live here for {days} days. Restore any time before they vanish.}}'**
  String trashEmptyStateMessage(int days);

  /// No description provided for @trashRetentionBanner.
  ///
  /// In en, this message translates to:
  /// **'{days,plural, =1{Items in trash are gone after 1 day. Restore brings them back.} other{Items in trash are gone after {days} days. Restore brings them back.}}'**
  String trashRetentionBanner(int days);

  /// No description provided for @trashConfirmEmpty.
  ///
  /// In en, this message translates to:
  /// **'Empty trash?'**
  String get trashConfirmEmpty;

  /// No description provided for @trashConfirmEmptyMsg.
  ///
  /// In en, this message translates to:
  /// **'This permanently deletes all items in the trash. The current library is unaffected.'**
  String get trashConfirmEmptyMsg;

  /// No description provided for @trashConfirmEmptyAll.
  ///
  /// In en, this message translates to:
  /// **'Empty all'**
  String get trashConfirmEmptyAll;

  /// No description provided for @trashConfirmDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete permanently?'**
  String get trashConfirmDelete;

  /// No description provided for @trashConfirmDeleteMsg.
  ///
  /// In en, this message translates to:
  /// **'{filename} will be erased forever.'**
  String trashConfirmDeleteMsg(String filename);

  /// No description provided for @trashRestored.
  ///
  /// In en, this message translates to:
  /// **'Restored {filename}'**
  String trashRestored(String filename);

  /// No description provided for @trashDaysLeft.
  ///
  /// In en, this message translates to:
  /// **'{days,plural, =0{Expires today} =1{1 day left} other{{days} days left}}'**
  String trashDaysLeft(int days);

  /// No description provided for @trashRestoreTooltip.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get trashRestoreTooltip;

  /// No description provided for @trashDeleteForeverTooltip.
  ///
  /// In en, this message translates to:
  /// **'Delete forever'**
  String get trashDeleteForeverTooltip;

  /// No description provided for @audioStrengthLabel.
  ///
  /// In en, this message translates to:
  /// **'Separation strength'**
  String get audioStrengthLabel;

  /// No description provided for @audioAutoBadge.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get audioAutoBadge;

  /// No description provided for @audioResetToAuto.
  ///
  /// In en, this message translates to:
  /// **'Reset to Auto'**
  String get audioResetToAuto;

  /// No description provided for @audioStrengthLight.
  ///
  /// In en, this message translates to:
  /// **'Light — music slightly audible'**
  String get audioStrengthLight;

  /// No description provided for @audioStrengthBalanced.
  ///
  /// In en, this message translates to:
  /// **'Balanced — recommended'**
  String get audioStrengthBalanced;

  /// No description provided for @audioStrengthAggressive.
  ///
  /// In en, this message translates to:
  /// **'Aggressive — best isolation, slower'**
  String get audioStrengthAggressive;

  /// No description provided for @audioEstimatedTime.
  ///
  /// In en, this message translates to:
  /// **'Estimated time'**
  String get audioEstimatedTime;

  /// No description provided for @audioTip.
  ///
  /// In en, this message translates to:
  /// **'Higher strength = longer time. Plug in for long clips and keep the screen on.'**
  String get audioTip;

  /// No description provided for @audioStartSeparation.
  ///
  /// In en, this message translates to:
  /// **'Start separation'**
  String get audioStartSeparation;

  /// No description provided for @audioCompareResult.
  ///
  /// In en, this message translates to:
  /// **'Compare result'**
  String get audioCompareResult;

  /// No description provided for @audioOriginalLabel.
  ///
  /// In en, this message translates to:
  /// **'Original'**
  String get audioOriginalLabel;

  /// No description provided for @audioOriginalDesc.
  ///
  /// In en, this message translates to:
  /// **'Music + voices'**
  String get audioOriginalDesc;

  /// No description provided for @audioVocalsOnly.
  ///
  /// In en, this message translates to:
  /// **'Voices only'**
  String get audioVocalsOnly;

  /// No description provided for @audioVocalsOnlyDesc.
  ///
  /// In en, this message translates to:
  /// **'Music removed'**
  String get audioVocalsOnlyDesc;

  /// No description provided for @audioNewBadge.
  ///
  /// In en, this message translates to:
  /// **'NEW'**
  String get audioNewBadge;

  /// No description provided for @audioDiscardRedo.
  ///
  /// In en, this message translates to:
  /// **'Discard & redo'**
  String get audioDiscardRedo;

  /// No description provided for @audioCompareInstructions.
  ///
  /// In en, this message translates to:
  /// **'Tap play on either track to compare. The voices-only version is what you save.'**
  String get audioCompareInstructions;

  /// No description provided for @audioGeneratedOnDevice.
  ///
  /// In en, this message translates to:
  /// **'Generated on this device.'**
  String get audioGeneratedOnDevice;

  /// No description provided for @animatedRange.
  ///
  /// In en, this message translates to:
  /// **'Range'**
  String get animatedRange;

  /// No description provided for @animatedLength.
  ///
  /// In en, this message translates to:
  /// **'Length'**
  String get animatedLength;

  /// No description provided for @animatedFormat.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get animatedFormat;

  /// No description provided for @animatedFrameRate.
  ///
  /// In en, this message translates to:
  /// **'Frame rate'**
  String get animatedFrameRate;

  /// No description provided for @animatedFpsUnit.
  ///
  /// In en, this message translates to:
  /// **'fps'**
  String get animatedFpsUnit;

  /// No description provided for @animatedSize.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get animatedSize;

  /// No description provided for @animatedEstimatedSize.
  ///
  /// In en, this message translates to:
  /// **'Estimated size'**
  String get animatedEstimatedSize;

  /// No description provided for @animatedExport.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get animatedExport;

  /// No description provided for @animatedExportQueued.
  ///
  /// In en, this message translates to:
  /// **'Animated export queued'**
  String get animatedExportQueued;

  /// No description provided for @animatedPhotosExportQueued.
  ///
  /// In en, this message translates to:
  /// **'Animated photo export queued'**
  String get animatedPhotosExportQueued;

  /// No description provided for @animatedReorderHint.
  ///
  /// In en, this message translates to:
  /// **'Hold & drag to reorder'**
  String get animatedReorderHint;

  /// No description provided for @animatedFramesCount.
  ///
  /// In en, this message translates to:
  /// **'{count,plural, =1{1 frame} other{{count} frames}}'**
  String animatedFramesCount(int count);

  /// No description provided for @animatedLoop.
  ///
  /// In en, this message translates to:
  /// **'Loop'**
  String get animatedLoop;

  /// No description provided for @animatedLoopDesc.
  ///
  /// In en, this message translates to:
  /// **'Plays continuously when supported'**
  String get animatedLoopDesc;

  /// No description provided for @animatedSelectAtLeast2.
  ///
  /// In en, this message translates to:
  /// **'Select at least 2 photos to create an animation.'**
  String get animatedSelectAtLeast2;

  /// No description provided for @animatedSlideshow.
  ///
  /// In en, this message translates to:
  /// **'Slideshow pace'**
  String get animatedSlideshow;

  /// No description provided for @animatedSmooth.
  ///
  /// In en, this message translates to:
  /// **'Smooth motion'**
  String get animatedSmooth;

  /// No description provided for @animatedStandard.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get animatedStandard;

  /// No description provided for @framesInterval.
  ///
  /// In en, this message translates to:
  /// **'Interval'**
  String get framesInterval;

  /// No description provided for @framesFps.
  ///
  /// In en, this message translates to:
  /// **'Frame rate'**
  String get framesFps;

  /// No description provided for @framesSingle.
  ///
  /// In en, this message translates to:
  /// **'Single'**
  String get framesSingle;

  /// No description provided for @framesEvery.
  ///
  /// In en, this message translates to:
  /// **'Every'**
  String get framesEvery;

  /// No description provided for @framesPosition.
  ///
  /// In en, this message translates to:
  /// **'Position'**
  String get framesPosition;

  /// No description provided for @framesSecondsUnit.
  ///
  /// In en, this message translates to:
  /// **'s'**
  String get framesSecondsUnit;

  /// No description provided for @framesSingleAtTimestamp.
  ///
  /// In en, this message translates to:
  /// **'Single frame at this timestamp'**
  String get framesSingleAtTimestamp;

  /// No description provided for @framesPreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get framesPreview;

  /// No description provided for @framesMore.
  ///
  /// In en, this message translates to:
  /// **'+{count} more'**
  String framesMore(int count);

  /// No description provided for @framesSaveCount.
  ///
  /// In en, this message translates to:
  /// **'{count,plural, =1{Save 1 frame} other{Save {count} frames}}'**
  String framesSaveCount(int count);

  /// No description provided for @framesSavingCount.
  ///
  /// In en, this message translates to:
  /// **'{count,plural, =1{Saving 1 frame…} other{Saving {count} frames…}}'**
  String framesSavingCount(int count);

  /// No description provided for @framesEstimatedCount.
  ///
  /// In en, this message translates to:
  /// **'{count,plural, =1{≈ 1 frame} other{≈ {count} frames}}'**
  String framesEstimatedCount(int count);

  /// No description provided for @videoEditorTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit video'**
  String get videoEditorTitle;

  /// No description provided for @videoEditorExport.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get videoEditorExport;

  /// No description provided for @videoEditorExporting.
  ///
  /// In en, this message translates to:
  /// **'Exporting…'**
  String get videoEditorExporting;

  /// No description provided for @videoEditorStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get videoEditorStart;

  /// No description provided for @videoEditorEnd.
  ///
  /// In en, this message translates to:
  /// **'End'**
  String get videoEditorEnd;

  /// No description provided for @videoEditorAspectRatio.
  ///
  /// In en, this message translates to:
  /// **'Aspect ratio'**
  String get videoEditorAspectRatio;

  /// No description provided for @videoEditorAspectFree.
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get videoEditorAspectFree;

  /// No description provided for @videoEditorTrimLossless.
  ///
  /// In en, this message translates to:
  /// **'Lossless trim — handles snap to keyframes. Instant + zero quality loss.'**
  String get videoEditorTrimLossless;

  /// No description provided for @videoEditorTrimSmart.
  ///
  /// In en, this message translates to:
  /// **'Smart cut — chosen edges need a brief one-pass re-encode for accuracy.'**
  String get videoEditorTrimSmart;

  /// No description provided for @videoEditorCropWarning.
  ///
  /// In en, this message translates to:
  /// **'Cropping requires a one-time re-encode.'**
  String get videoEditorCropWarning;

  /// No description provided for @videoEditorRemoveLossless.
  ///
  /// In en, this message translates to:
  /// **'Removing sound is lossless — the video stream is copied untouched.'**
  String get videoEditorRemoveLossless;

  /// No description provided for @videoEditorCodec.
  ///
  /// In en, this message translates to:
  /// **'Codec'**
  String get videoEditorCodec;

  /// No description provided for @videoEditorResolution.
  ///
  /// In en, this message translates to:
  /// **'Resolution'**
  String get videoEditorResolution;

  /// No description provided for @videoEditorResolutionOriginal.
  ///
  /// In en, this message translates to:
  /// **'Original'**
  String get videoEditorResolutionOriginal;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
