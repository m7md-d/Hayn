# 13 — بيئة التطوير والتخزين الخارجي

> حالة 2026-09-27: Android SDK والمحاكي وبيئة iOS تعمل، وFFmpeg مثبت على 3.6.2 والحد الأدنى iOS 15. المقاطع السابقة عن غياب منصة أو lock mismatch أدناه تسجل تاريخ التجهيز؛ [سجل المتابعة](14-ISSUES.md) يوضح ما بقي فعليًا.

إعداد جهاز التطوير بتاريخ 2026-09-26. هذا توثيق لإعداد محلي، وليس مسارات تُضمّن في التطبيق أو إعدادًا يجب نسخه حرفيًا لكل مطور.

## أماكن البيانات الكبيرة

الجذر الخارجي: `/Volumes/CUSU/Development`، على APFS. حافظ على اسم القرص ومكان تركيبه، وصله قبل فتح أدوات التطوير.

| المسار المعتاد المتوافق | مكان البيانات الفعلي |
|---|---|
| `/opt/homebrew/share/flutter`، ورابط `~/flutter` القديم | `Development/flutter` |
| `~/.pub-cache` | `Development/caches/pub` |
| `~/.gradle` | `Development/caches/gradle` |
| `~/.rustup` | `Development/rustup` |
| `~/Library/Caches/Homebrew` | `Development/caches/homebrew` |
| `~/Library/Android/sdk` | `Development/android-sdk` |
| Java المستخدم لـFlutter/Android | `Development/jdks/temurin-21` |
| `~/.cargo/registry` و`~/.cargo/git` | `Development/caches/cargo` |
| `~/.dartServer` (ذاكرة محلل Dart) | `Development/caches/dartServer` |
| `flutter_rust_bridge_codegen` 2.12.0 (مطابق للـruntime) و`cargo-expand` 1.0.126 الذي يحتاجه | `Development/tools/<الأداة>-<النسخة>/bin`؛ ليسا في PATH |
| مجلدات Xcode وCocoaPods وSwiftPM | انظر [iOS وXcode](#ios-وxcode) |

بقي `~/.cargo/bin` الصغير وملفات إعداد الطرفية داخليًا.

توليد روابط DarkLib بعد تغيير API في `native/darklib/src/api`، من جذر المشروع. إن لم يجد المولّد `cargo expand` في PATH ثبّته وحده داخل `~/.cargo/bin`، لذلك يُمرَّر مساره الخارجي:

```sh
source ~/.config/hayn-development.zsh
PATH="/Volumes/CUSU/Development/tools/cargo-expand-1.0.126/bin:$HOME/.cargo/bin:$PATH" \
  /Volumes/CUSU/Development/tools/flutter_rust_bridge_codegen-2.12.0/bin/flutter_rust_bridge_codegen generate
``` `Xcode.app` نفسه والمتصفحات لم تُنقل. مجلدا build وRust target داخل المشروع موجودان أصلًا على القرص الخارجي.

ملف الإعداد الصغير `~/.config/hayn-development.zsh` يُقرأ من `.zprofile` و`.zshrc`. يحدد Android وJava ومسارات الأدوات، ويحتفظ Pub وGradle بالمسارات المعتادة عبر الروابط. ضبط Flutter يشير إلى SDK ورابط JDK نفسه. Java السابق لا يزال مثبتًا؛ بيئة تطوير الطرفية تستخدم Java 21 الآن.

## الأدوات المثبتة

Flutter 3.47.2 / Dart 3.13.2 الموجودان نُقلا دون ترقية. Java هو Temurin 21 LTS. ثُبتت أدوات Android لسطر الأوامر وplatform-tools وAPI 36 وBuild Tools 35.0.0 وNDK 28.2.13676358 وCMake 3.22.1. قد تثبت Gradle منصات إضافية تطلبها plugins؛ يُسجل ذلك في سجل البناء الخارجي. لم تُثبت Android Studio أو emulator/system images.

اختيرت الحزم بناءً على Flutter المثبت وAGP 8.11.1 في المشروع، لا بتنزيل كل إصدارات SDK. مرجع [توافق AGP 8.11](https://developer.android.com/build/releases/agp-8-11-0-release-notes)، و[تنزيل Android الرسمي](https://developer.android.com/studio)، و[Adoptium](https://adoptium.net/).

## العمل اليومي

افتح طرفية جديدة وأعد تشغيل المحرر ليقرأ البيئة الجديدة. داخل المشروع:

```sh
flutter doctor -v
flutter pub get
flutter gen-l10n
flutter test
flutter build apk --debug --target-platform android-arm64
```

المشروع يدعم Android arm64 وx86_64 حاليًا، وليس armv7. أمر البناء أعلاه للتحقق السريع من arm64، وليس إثباتًا لبقية المنصات. تحديث Flutter أو Gradle عملية مستقلة؛ لا تغيّر النسخ لتجاوز تحذير ضمن عمل آخر.

المجلد الخارجي `Development/logs` يحوي سجلات التثبيت والفحص وmanifest النقل، و`Development/backups/environment-20260926` يحوي الإعدادات السابقة. نسخة دراسة main/bedrock في `Development/verification/Hayn-audit-20260925`؛ لا تحتاج نسخ build وtarget إلى Git.

## المحافظة على المساحة والمسارات

- لا تنشئ SDK أو Pub/Gradle/Rust caches بديلة داخليًا. الروابط تحافظ على توافق مشاريع وأدوات تستخدم المسارات القديمة.
- بعد تحديث Flutter عبر Homebrew، افحص المسار الفعلي بـ`flutter doctor -v`؛ مدير الحزم قد يعيد إنشاء مسار تثبيت، ولا نفترض أنه سيحافظ على ترتيب التخزين المخصص إلى الأبد.
- `flutter clean`/`cargo clean` يحذفان مخرجات قابلة لإعادة البناء في المشروع المحدد. لا تنظف كل caches دوريًا؛ ذلك يعيد التنزيل ويزيد وقت العمل.
- لا تفصل القرص أثناء build أو تشغيل IDE يستخدمه. عند غياب القرص تكون الأدوات المنقولة غير متاحة؛ هذا جزء مقصود من نقلها، وليس تثبيتًا داخليًا احتياطيًا.
- للاسترجاع: أوقف أدوات البناء، راجع `migration.json`، انسخ وجهة كل رابط إلى مكانه الأصلي بعد إزالة الرابط نفسه فقط، ثم استعد الإعدادات المحفوظة عند الحاجة. لا تحذف وجهة خارجية قبل التحقق من النسخة المسترجعة.

## نتيجة التحقق المحلي

نُقلت وحُذفت النسخ الداخلية المؤقتة لنحو **11.23 GiB** بعد مقارنة محتواها ونجاح الفحوص. SDK وذاكرات التنزيل والبناء الجديدة تحفظ خارجيًا. نجح بناء debug وrelease العادي و122 اختبار Flutter و74 اختبار Rust. فشل split-per-ABI بإعداد المشروع الحالي؛ تفاصيله وأحجام الحزم في [خطة الاستقرار](12-STABILIZATION.md).

نتائج الاختبارات لا تصلح عيوب HDR والإلغاء والسقوط المسجلة؛ هي تحقق من عمل الأدوات بعد النقل. ملفات الإعداد السابقة الصغيرة محفوظة للاسترجاع. ظهرت تحذيرات `pyenv` غير المثبتة في إعداد الطرفية السابق؛ لم نعدّل إعداد Python ضمن نقل Flutter. إعادة تشغيل المحرر والطرفية تكفي لقراءة المسارات الجديدة.


## تحقق لاحق بعد دفعة الاستقرار

نجحت 152 حالة Flutter والتحليل وAPK debug من `/Volumes/CUSU/Hayn` بعد الإصلاحات؛ نتائج هذه الدفعة منفصلة عن baseline نقل الأدوات أعلاه. التفاصيل في [خطة الاستقرار](12-STABILIZATION.md).

نقل المشروع قد يترك `.flutter-plugins-dependencies` و`.dart_tool` يشيران إلى المسار القديم حتى مع سلامة PATH والروابط. إذا فشل البناء لأن مجلد plugin المحلي لا يوجد، حدّث ملفات Flutter المولدة بواسطة `flutter pub get` من **مجلد المشروع الحالي**. في هذه الجولة استُخدم `--offline` من الكاش الخارجي، وحُفظ ملف القفل الأصلي؛ اختيار نسخة Flutter موحدة مع CI وتسوية حزم SDK المقفلة عمل مستقل، وليس ترقية اعتماديات ضمن إصلاح سلوكي.

اختبار مكتبة المضيف احتاج إعادة `cargo build --locked` لأن dylib القديمة لم تطابق FRB content hash؛ البناء الناجح لا يعني أن كل artifact قديم في target صالح مع الجسر الحالي.

بناء iOS لا يزال متعذرًا: Xcode يذكر أن وجهة iOS 26.2 غير مثبتة. ظهور رقم SDK وحده لا يثبت وجود منصة قابلة للبناء. أُلغيت ترقية حد iOS التي أجراها Flutter تلقائيًا أثناء المحاولة، ولم تُثبت منصة أو محاكيات إضافية. عند محاولة البناء لاحقًا يمكن توجيه CocoaPods خارجيًا باستخدام `CP_HOME_DIR` و`CP_CACHE_DIR`؛ استُخدمت قيم تحت `Development/caches/cocoapods` في هذه المحاولة، لكن CocoaPods لم يصل إلى مرحلة تنزيل الحزم. لم تُضف روابط أو متغيرات دائمة له في هذه الدفعة. (حُلّ لاحقًا — انظر القسم التالي.)

## iOS وXcode

أُعدّ بتاريخ 2026-09-26. `Xcode.app` (26.3، SDK iOS 26.2) باقٍ في `/Applications` عمدًا؛ المنقول هو ما ينزّله Xcode والأدوات تلقائيًا بعد ذلك.

### منصة iOS (المحاكي) — الاستثناء الداخلي الوحيد

Xcode 26 يرفض حتى وجهة **Any iOS Device** (البناء لجهاز فعلي) ما لم تُثبت منصة iOS المطابقة لـSDK: `iOS 26.2 is not installed`. المنصة هي محاكي iOS نفسه، ولا صلة لإصدارها بإصدار الهاتف المستهدف؛ الهاتف يعمل بأي iOS ≥ حد المشروع. لا توجد محاكيات iOS 18.7 أصلًا (آخر iOS 18 في فهرس Apple هو 18.6).

المثبت: **iOS 26.3.1 (23D8133)، variant `arm64`** — أصغر من universal بنحو 2 GiB، ويكفي Mac بمعالج Apple.

**لا يمكن تخزينها خارجيًا.** `simdiskimaged` مقيد بـsandbox على `/Library/Developer/CoreSimulator/...`، والنسخ دون مساحة إضافية (clone) لا يعمل بين قرصين. و`xcodebuild -downloadPlatform ... -exportPath` **يسجّل المنصة داخليًا أيضًا** (في `/System/Library/AssetsV2`) ثم يصدّر نسخة إلى المسار المحدد. التكلفة الداخلية الفعلية:

| البند | الحجم | المكان |
|---|---|---|
| صورة المحاكي | 7.8 GiB | `/System/Library/AssetsV2/com_apple_MobileAsset_iOSSimulatorRuntime` |
| dyld shared cache للمحاكي | 3.8 GiB | `/Library/Developer/CoreSimulator/Caches/dyld/<macOS build>/` — يُعاد توليده عند تحديث macOS |

نسخة أرشيفية من الصورة: `Development/apple/runtimes/iphonesimulator_26.3.1_23D8133.dmg`. لتحرير المساحة الداخلية مؤقتًا: `xcrun simctl runtime delete <id>`، ثم عند الحاجة `xcrun simctl runtime add <dmg>` دون تنزيل.

- **لا تضف الـdmg والمنصة نفسها مسجلة.** ينتج نسخة `Unusable - Duplicate` تأخذ 7.8 GiB أخرى في `/Library/Developer/CoreSimulator/Images/Inbox`. افحص بـ`xcrun simctl runtime list` واحذف المكرر بـ`xcrun simctl runtime delete <id>`.
- **كل تحديث لـXcode بـSDK جديد يطلب منصة جديدة** (~8 GiB + cache). عطّل التحديث التلقائي لـXcode في App Store وحدّث عن قصد، ثم احذف المنصة القديمة.
- منصات watchOS/tvOS/visionOS وMetal Toolchain من Settings ← Components تُخزن داخليًا بالآلية نفسها؛ المشروع لا يحتاجها.

### المسارات المنقولة

روابط بنفس أسلوب الجدول أعلاه؛ السجل في `Development/logs/ios-migration.json` والنسخ الاحتياطية الصغيرة في `Development/backups/ios-20260926`.

| المسار المعتاد | مكان البيانات الفعلي |
|---|---|
| `~/Library/Developer/Xcode/DerivedData` | `Development/apple/xcode/DerivedData` |
| `~/Library/Developer/Xcode/iOS DeviceSupport` و`watchOS DeviceSupport` | `Development/apple/xcode/…` |
| `~/Library/Developer/Xcode/Archives` | `Development/apple/xcode/Archives` |
| `~/Library/Developer/DVTDownloads` | `Development/apple/DVTDownloads` |
| `~/.cocoapods` و`~/Library/Caches/CocoaPods` | `Development/caches/cocoapods/{home,cache}` |
| `~/Library/Caches/org.swift.swiftpm` | `Development/caches/swiftpm` |

أهداف Rust `aarch64-apple-ios` و`aarch64-apple-ios-sim` مثبتة (rustup خارجي أصلًا). cargokit يثبت `x86_64-apple-ios` تلقائيًا إن طُلب.

**ما يكتب فيه `CoreSimulatorService` يبقى داخليًا:** `~/Library/Developer/CoreSimulator/{Devices,Caches}` و`~/Library/Developer/XCTestDevices` و`~/Library/Developer/Xcode/UserData/IB Support`. الخدمة تعمل في الخلفية دون إذن TCC للأقراص الخارجية فتفشل بـ`EPERM` (`Operation not permitted`) — لا تُنشأ أجهزة المحاكي، ويفشل `ibtool` في تجميع الـstoryboards (`Failed to find or create execution context … IBCocoaTouchFramework`). نُقلت ثم أُعيدت لهذا السبب؛ النسخ الخارجية المعزولة في `Development/backups/ios-20260926/reverted-external`. حجمها صغير ما لم يُشغَّل المحاكي.

### التحقق

`flutter build ios --debug --no-codesign --no-pub` نجح داخل المشروع (نسخة تحقق معزولة سبقته في `Development/verification/Hayn-ios-20260926`). ذهبت DerivedData (1.8 GiB) وذاكرة CocoaPods إلى الخارجي، ولم يُكتب داخليًا ملف كبير. `--no-pub` يمنع Flutter من تعديل `pubspec.lock` (ما زال لا يطابق حزم SDK المقفلة — انظر أعلاه).

**حد iOS الأدنى: 15.0** (اعتُمد بتاريخ 2026-09-26). Flutter 3.47 يفرضه عند أي بناء iOS؛ عُدّل `IPHONEOS_DEPLOYMENT_TARGET` ×3 في `project.pbxproj`، و`platform :ios` وحلقة `post_install` في `Podfile`. `Podfile.lock` تحدّث ليشمل `darklib`. ثلاث plugins لا تدعم Swift Package Manager وتُبنى عبر CocoaPods (تحذير لا خطأ): `darklib`، `flutter_avif_ios`، `flutter_image_compress_common`.

**المحاكي:** حتى `ffmpeg_kit_flutter_new_min` 3.1.0 لم يكن للمكتبة مقطع arm64 للمحاكي، فتعذر تشغيل التطبيق على محاكيات iOS 26+ في Apple Silicon. ثُبّتت على **3.6.2** (2026-09-26): xcframeworks بمقطع `ios-arm64_x86_64-simulator`، وبلا arm64e الذي يرفضه App Store، وFFmpeg 8.1.2. مع SPM المفعّل يدمجها Flutter عبر Swift Package Manager، فخرجت من `Podfile.lock`. أول بناء بعد الترقية فحص Pods القديمة قبل `pod install` فبنى x86_64 فقط؛ البناء الثاني بنى `x86_64 arm64`. بعدها يعمل التطبيق على المحاكي، ونجحت 158 حالة Flutter وبناء release للجهاز.

لقطات README تُولَّد من المحاكي بـ`tool/screenshots/generate.sh`؛ طريقتها وقيودها في `.claude/rules/presentation.md`. المحاكي المؤقت يُنشأ ويُحذف في كل تشغيل، وبياناته داخلية أثناءه فقط.

**الجهاز الفعلي:** `flutter build ios --release --no-pub` بتوقيع تلقائي نجح (3:02، ‏Runner.app ‏64 MB) وثُبّت على iPhone 13 Pro ‏(iOS 18.7.2) عبر `xcrun devicectl device install app`. الفريق `4KF43H9U64` حساب مجاني (Personal Team): ملف التوقيع صالح **7 أيام** ثم يلزم إعادة البناء والتثبيت، وأول تثبيت يتطلب الثقة بالمطوّر على الهاتف من الإعدادات ← عام ← إدارة الجهاز و VPN.


### اختبارات المحاكي الفعلية — 2026-09-28

[15-IOS-TESTING](15-IOS-TESTING.md) يشرح تشغيل مجموعة التحويل والحفظ والمصغرات، والفرق بين دليل المحاكي والهاتف. `tool/test_ios_preservation.sh` ينشئ جهازًا مؤقتًا باستخدام runtime المثبت، ويصدر ملفات الفحص الاصطناعية إلى `build/ios-preservation/` قبل حذف الجهاز. لا تضاف عينات HDR إلى assets التطبيق. بيانات CoreSimulator داخلية أثناء الجولة فقط؛ نواتج البناء والأدلة على القرص الخارجي.


## فصل القرص وخدمات Gradle — 2026-09-29

بعد فصل القرص رُصدت خدمة Gradle 8.14.3 تعمل بـJava من الخارجي وتستهلك 515–551% CPU، مع 886 مقبض ملف ملغى ومجلد عمل غير متاح. أوقفت الخدمة المحددة بعد عدم استجابتها للإيقاف العادي، وصار المعالج 87% خاملًا في القياس التالي. دليل فقد الملفات قوي؛ الحلقة الداخلية في JVM لم تحدد. راجع BUILD-06.

بموافقة المستخدم، لضبط البيئة مع كثرة فصل القرص، أضيف إلى `~/.gradle/gradle.properties` (الملف الفعلي على `Development/caches/gradle/gradle.properties`):

```properties
org.gradle.daemon=false
org.gradle.daemon.idletimeout=60000
```

بناء الطرفية يستخدم JVM مؤقتة عند الحاجة تنتهي بانتهاء البناء. Tooling API التي تستخدمها المحررات تحتاج daemon حتى مع الإعداد الأول؛ الإعداد الثاني ينهيها بعد نحو دقيقة خمول، وليس أثناء عمل جارٍ. العمليات أو المحررات ذات إعدادات صريحة أخرى قد تتجاوز الإعداد العام. لا نضيف `--no-daemon` إلى arguments الخاصة باستيراد Java في المحرر لأنه غير مدعوم في Tooling API.

أضيف كذلك `-Dorg.gradle.daemon=false` إلى GRADLE_OPTS في `~/.config/hayn-development.zsh` للطرفيات الجديدة، مع حفظ الخيارات السابقة وعدم تكرار الإضافة عند source مرتين. نسخة ملف البيئة السابق: `~/.config/hayn-backups/20260929-160754/hayn-development.zsh`. لم تتغير JAVA_HOME أو مسارات الكاشات أو إصدارات الأدوات أو إعدادات VS Code.

**التحقق:** `./gradlew help --offline` في Android الخاص بـHayn نجح في 22 ثانية؛ خرجت الخدمة بعد انتهاء العملية. تجربة Tooling API فعلية بمشروع صغير بلا اعتماديات نجحت في 3 ثوان، وسجلت `idleTimeout=60000` ثم انتهت تلقائيًا بعد نحو 68 ثانية خمول. تأكدنا من اختفاء العمليتين وعدم بقاء GradleDaemon أخرى. هذه فحوص دورة حياة خدمات البناء، وليست إعادة اختبار التطبيق أو APK/iOS.

الأدلة: `Development/logs/gradle-lifecycle-{cli,tooling}-20260929.log` و`gradle-lifecycle-{cli,tooling}-daemon-20260929.log`؛ مصدر تجربة Tooling API في `Development/verification/gradle-lifecycle-20260929`. ظهر في سجل shutdown للعمليتين استثناء `Cannot start managing file contention because this handler has been closed` أثناء إزالة سجل daemon؛ انتهت العمليتان ونجحت المهمتان رغمه، ولم يُفحص سببه الداخلي. لا تعتبره فشل بناء أو تخفِ وجوده إذا عاد وسبب أثرًا.

**قبل فصل القرص:** أنهِ البناء وأغلق المشروع في المحرر، وانتظر انتهاء خدماته، ثم أخرج القرص من Finder. مهلة الخمول تقلل بقاء الخدمات، ولا تجعل فصل القرص أثناء عملية تستخدمه آمنًا. الإعداد الجديد يضحي ببعض تسريع البناء المتكرر مقابل عدم الاحتفاظ بالخدمة لساعات.

للتراجع عن السياسة لاحقًا: احذف السطرين المضافين من ملف Gradle العام، واحذف كتلة Gradle المضافة في نهاية ملف البيئة (أو استعد النسخة بعد مراجعة أي تعديلات أحدث). الملف العام لم يكن موجودًا قبل هذه الدفعة؛ لا تحذفه كاملًا إذا أضيفت إليه إعدادات أخرى. لا تحذف الكاشات.

المراجع: [Gradle Daemon](https://docs.gradle.org/current/userguide/gradle_daemon.html)، [Tooling API](https://docs.gradle.org/current/userguide/tooling_api.html).
