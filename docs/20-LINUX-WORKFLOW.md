# 20 — العمل من لينكس وتقسيمه مع الماك

آخر تحديث: 2026-10-02. من هذا التاريخ يستمر التطوير الرئيسي على جهاز لينكس بعتاد أقوى ومساحة أوسع. يبقى الماك لما لا يعمل إلا عليه: بناء iOS والتجربة على الآيفون. هذا الملف يحدد ما يعمله كل جهاز، والقيود التي لا تنطبق على لينكس، وتجهيزه، وأوامره اليومية، وطريقة التسليم بين الجهازين. المهام المطلوبة من الماك في [21-MAC-TASKS](21-MAC-TASKS.md).

> **حالة التحقق:** تجهيز لينكس أدناه كُتب من الماك ولم يُجرَّب على لينكس. الدليل الوحيد أن الأوامر تعمل على Ubuntu هو ملف CI الذي يعمل على `ubuntu-latest`، ولم تُبلَّغ نتائج كل مهامه بعد (BUILD-01). أول جلسة على لينكس تشغّل قسم «التحقق من البيئة» أدناه وتصحح هذا الملف بما تجده.

## 1. من يعمل ماذا

| العمل | لينكس | الماك |
|---|---|---|
| DarkLib: fmt وclippy والاختبارات وMSRV 1.88 | نعم | نعم |
| الجسر الحقيقي على المضيف (`libdarklib.so`، و`.dylib` على الماك) | نعم | نعم |
| توليد روابط FRB (`flutter_rust_bridge_codegen`) | نعم | نعم |
| Flutter: التحليل والاختبارات والتنسيق | نعم | نعم |
| بناء Android (debug وrelease، arm64) | نعم | نعم |
| اختبارات هاتف Android: الصحة (`tool/test_android_device.sh`) والأداء (`tool/test_performance.sh`) | نعم، والهاتف موصول به | نعم |
| بناء iOS، وXcode وPods وSPM | **لا** | **وحده** |
| محاكي iOS (`tool/test_ios_preservation.sh`) | **لا** | **وحده** |
| آيفون: التثبيت واختبار الأداء | **لا** | **وحده** |
| قارئا ImageIO وAVFoundation المستقلان (سكربتات `test_native/*.swift`) | **لا** | **وحده** |
| لقطات README (`tool/screenshots/generate.sh`، تستعمل محاكي iOS) | **لا** | **وحده** |
| تعديل كود Swift وPodfile ومشروع Xcode | يُحرَّر ولا يُبنى | يُبنى ويُتحقق |
| القراءة المستقلة للنواتج | ffmpeg وffprobe وPillow وexiftool و`test_native/check_jpeg_mpf.py`، وlibheif 1.23 عبر pillow-heif مع LittleCMS: `check_heif_inject.py` بعد `cargo test --test heif_inject`، و`check_heic_tiles.py <نتائج الهاتف> native/darklib/tests/fixtures` بعد `tool/test_android_device.sh`، و`check_jpeg_stream.py native/darklib/tests/fixtures <نتائج الهاتف>/jpeg-paths` لـJPEG التدفقي، و`check_metadata_model.py native/darklib/tests/fixtures <مجلد>` بعد `DARKLIB_METADATA_OUT=<مجلد> cargo test --test metadata_model` للصيغة الوسيطة للبيانات. ExifTool 13.59 في `~/tools/Image-ExifTool-13.59/` (سكربت Perl، نُزّل من exiftool.org وطابقت بصمته SHA-256 المنشورة، 2026-10-10)، أو `EXIFTOOL=<مسار>`. ولعرض معرض Samsung: `tool/android_gallery_colour.sh` بعد تشغيل المجموعة | كل ما سبق مع ImageIO |
| تحديث الوثائق والسجل | نعم | نعم |

**قاعدة الادعاء:** ما لا يستطيع لينكس تحقيقه لا يُعلن متحققًا. أي سلوك يمس iOS يبقى في السجل بعبارة «غير مختبر على iOS (M-NN)» حتى تنفذ مهمة الماك وتُكتب نتيجتها. نجاح الاختبارات على لينكس يثبت لينكس وAndroid، لا iOS.

## 2. القيود التي لا تنطبق على لينكس

هذه القيود وُضعت لضيق المساحة والقرص الخارجي وبطء الماك، ولا تلزم هناك:

| القيد على الماك | سببه | على لينكس |
|---|---|---|
| تشغيل الفحوص الثقيلة خطوة خطوة، والتحقق من تركيب القرص قبل كل خطوة | القرص الخارجي NVMe ينقطع تحت الحمل | لا قرص خارجي؛ شغّل البوابات متتابعة أو متوازية |
| تجنب المحاكي والبناء إلا لسبب | البناء يستغرق وقتًا طويلًا ويثقل الجهاز | شغّل البوابات الكاملة بعد كل دفعة؛ لا حاجة لتبرير كل بناء |
| Gradle بلا daemon (`org.gradle.daemon=false`) | الخدمة تتعلق عند فصل القرص | اترك الإعداد الافتراضي؛ لا تنقل هذه السياسة إلى لينكس |
| لا clean شامل ولا تنزيل متكرر للكاشات | عرض النطاق والقرص | `flutter clean` و`cargo clean` مسموحان عند الحاجة |
| الكاشات والأدوات تحت `/Volumes/CUSU/Development` وروابط `~/.config/hayn-development.zsh` | المساحة الداخلية صغيرة | لا وجود لهذه المسارات؛ ثبّت الأدوات في المكان المعتاد على لينكس |
| بناء واحد في كل مرة لأن Xcode يشارك المخرجات | Xcode | لا ينطبق |
| CoreSimulator وEPERM | macOS | لا ينطبق |

**لا تزال تنطبق على أي جهاز:**
- **قواعد المنتج:** القواعد الثابتة التسع في [CLAUDE.md](../CLAUDE.md): أوفلاين، الأصل لا يُمس، لا إسقاط صامت للون أو الاتجاه، وبقيتها. وقرارات المستخدم في [16-HANDOFF](16-HANDOFF.md).
- **Git للمستخدم وحده:** لا `add` ولا `commit` ولا `reset` ولا فروع ولا `push`. الوثائق لا تسجل حالة Git.
- **اللغة:** التوثيق بالعربية، وتعليقات الكود بالإنجليزية، ونصوص التطبيق عبر ARB.
- **الهاتف:** القواعد في القسم 6.
- **التوثيق مع الإصلاح:** كل عيب في [14-ISSUES](14-ISSUES.md) بمعرّف وسبب ودليل ومعيار إغلاق. وما يحتاج جهازًا لا نملكه في [17-TODO](17-TODO.md).
- **لا ترقيات جانبية:** لا ترفع lockfiles ولا الاعتماديات ولا Flutter ولا FFmpeg (3.6.2) ضمن عمل آخر.

## 3. التجهيز

الإصدارات مأخوذة من الماك ومن `ci.yml`. لا تستبدلها بأحدث نسخة.

| الأداة | الإصدار | ملاحظات |
|---|---|---|
| Flutter / Dart | **3.47.2** / 3.13.2 | أرشيف Flutter الرسمي لهذه النسخة، أو في checkout موجود: `git fetch --tags && git checkout 3.47.2` داخل مجلد Flutter (جُرّب 2026-10-02). نسخة أقدم (3.44) تغيّر `pubspec.lock` خمس حزم. `flutter doctor -v` بعد التثبيت |
| Java | **Temurin 21** | تُجمَّع Java وKotlin بمستوى 17 |
| Android SDK | API 36، وBuild Tools **35.0.0**، وNDK **28.2.13676358**، وCMake **3.22.1**، وplatform-tools | `sdkmanager` ثم `flutter doctor --android-licenses`. قد ينزل Gradle منصات إضافية |
| Rust | **stable** للتطوير، و**1.88.0** لفحص MSRV | `rustup toolchain install 1.88.0`. هدف Android `aarch64-linux-android`؛ Cargokit يضيفه عند أول بناء إن غاب |
| مولّد الروابط | `flutter_rust_bridge_codegen` **2.12.0** | `cargo install flutter_rust_bridge_codegen --version 2.12.0 --locked` |
| `cargo-expand` | **1.0.126** | `cargo install cargo-expand --version 1.0.126 --locked`. يحتاج المولّد، وهو يحتاج مترجم nightly: على الماك مثبت `nightly` لهذا الغرض (`rustup toolchain install nightly`). nightly للأداة وحدها، لا للمنتج (native.md) |
| مترجم C | `build-essential` أو `clang` | حزمة `webp` تبني libwebp من C |
| Python 3 | مع `venv` | `python3 -m venv ~/hayn-venv && ~/hayn-venv/bin/pip install pillow pillow-heif`، ثم `PATH=$HOME/hayn-venv/bin:$PATH tool/test_performance.sh` (السكربت يستدعي `python3` للعينات؛ بدونها يفشل) |
| ffmpeg وffprobe | الأحدث المتاح (الماك: 9.0.1) | قارئ مستقل لبلاطات AVIF (`docs/14` IMG-02) |
| `adb` | من platform-tools | قواعد `udev` لسامسونج (المعرّف `04e8`)، والمستخدم في مجموعة `plugdev`، وقبول طلب RSA على الهاتف |
| `curl` و`sha256sum` | | سكربت الأداء ينزّل عينة ويتحقق من بصمتها |

**الملفات المرتبطة بالجهاز، لا تُنسخ من الماك:** `android/local.properties`، و`.dart_tool/`، و`.flutter-plugins-dependencies`، و`build/`، و`native/darklib/target/`. يعيد `flutter pub get` توليدها بالمسارات الصحيحة.

### التحقق من البيئة (أول جلسة)

شغّل هذه كلها وسجّل النتيجة في هذا الملف (سطر بالتاريخ والجهاز). أي فرق عمّا توقعه الماك يُصحَّح هنا:

```sh
flutter doctor -v
flutter pub get --enforce-lockfile
flutter gen-l10n
flutter analyze                         # نظيف
flutter test                            # 205 ناجحًا
cd native/darklib
cargo fmt --check
cargo clippy --all-targets --locked -- -D warnings
cargo test --locked                     # 123 ناجحًا
cargo +1.88.0 test --locked             # 123 على الحد الأدنى
cargo build --locked                    # target/debug/libdarklib.so
cd ../..
flutter test --no-pub test_native/darklib_host_test.dart \
  --dart-define=DARKLIB_TEST_LIBRARY=$PWD/native/darklib/target/debug/libdarklib.so   # 12 ناجحة
flutter build apk --release             # arm64 وحدها، نحو 50MB
```

الأرقام آخر ما ثبت على الماك (2026-09-30/10-02). إن اختلف عدد على لينكس فهذا عيب يُحقَّق فيه ولا يُتجاهل: اختبار يتوقف على النظام (مثل ما كشفه CI في `sheets_test.dart`، BUILD-01).

## 4. الأوامر اليومية

بعد كل تغيير، حسب ما لُمس (workflow.md):

```sh
# Dart: نسّق الملفات التي غيّرتها وحدها، وافحص أن الفرق محصور فيها
dart format <ملفاتك>
flutter analyze
flutter test

# Rust
cd native/darklib && cargo fmt --check && cargo clippy --all-targets --locked -- -D warnings && cargo test --locked

# تغيّرت واجهة crate::api أو اعتماديات native
source "$HOME/.cargo/env"
flutter_rust_bridge_codegen generate    # من جذر المستودع؛ لا تعدّل المولَّد يدويًا
```

`dart format` على ملف كامل أعاد تنسيق أجزاء لم نلمسها في جلسات سابقة؛ تحقق من الفرق بعده.

**FFI أو اعتماديات native أو Gradle:** ابنِ Android (`flutter build apk --release`) وأضف مهمة للماك (القسم 7). فحص المضيف وحده لا يكفي.

## 5. اختبارات هاتف Android من لينكس

الهاتف: Galaxy S25 Edge (Android 16، Snapdragon 8 Elite، بلا AV1 عتادي). ملف الأجهزة والنتائج السابقة في [18-PERFORMANCE](18-PERFORMANCE.md) و[12-STABILIZATION](12-STABILIZATION.md).

```sh
tool/test_android_device.sh [serial]  # الصحة كلها، ومنها القص الذي يحفظ في المعرض
tool/test_darklib_on_phone.sh [serial]  # اختبار DarkLib على معالج الهاتف: أقنعة rav1d (cpu_paths)
tool/test_performance.sh [serial]     # الأداء: ستة أقسام
```

- **البناء profile لا debug.** debug يبني Rust بلا تحسين، وتحويل gain map واحد يتجاوز 12 دقيقة.
- **الشاشة مفتوحة وغير مقفلة** طوال التشغيل.
- **نتائج الأداء:** تُحفظ في `build/performance/android-<الوقت>/` وتُنسخ إلى 18-PERFORMANCE بجانب نتائج الآيفون. الحد المتجاوز عيب جديد في 14-ISSUES.
- **عينات الأداء على لينكس:** لا `swift` هناك، فيولّد السكربت HEIC وPNG بـ`test_native/make_perf_fixtures.py` (libheif وPillow). ملف HEIC يختلف بايتيًا عن نسخة Apple على الماك، فلا تقارن أزمنة HEIC بين مولّدين. يُسجل المولّد في `fixtures-generator.txt` بجانب التقرير.
- **المعالج أسرع بكثير من الماك:** الأرقام التي تهمنا من الهاتف لا من المضيف. أزمنة المضيف لا تدخل 18-PERFORMANCE.

## 6. الهاتف: ما لا يتغير

- **التصريح:** المستخدم طلب الاختبار على Android من لينكس (2026-10-02)، وأذن سابقًا بالتثبيت على Galaxy S25 Edge (2026-09-29). هذا التصريح لهذا الهاتف. أي هاتف آخر يتطلب سؤاله.
- **التطبيق يُزال أحيانًا:** اختبار الصحة يستعمل `flutter drive` بلا `--keep-app-running`، فيزيل التطبيق بعد الجولة وتُمسح بيانات Hayn على الهاتف. اختبار الأداء يبقيه ويثبّت release بعده.
- **صور المستخدم لا تُقرأ ولا تُصوَّر.** اختبار الأداء يقيس الزمن والهندسة فقط.
- **ما يضيفه الاختبار إلى المعرض** (`Pictures/` بأسماء `hayn-test-crop-*`، و`Pictures/HaynTest/`) لا يحذفه الوكيل. يُبلَّغ المستخدم بمكانه وهو يحذفه.
- **لا تثبيت لنسخة نشر ولا تغيير توقيع** دون طلب.
- **العينات الناقصة:** يجلبها الوكيل بنفسه مع المصدر والرخصة وSHA-256 في `native/darklib/tests/fixtures/README.md`.

## 7. التسليم بين الجهازين

عند **نهاية كل جلسة على لينكس:**

1. حدّث الوثائق بنفس الدفعة: [14-ISSUES](14-ISSUES.md) (الحالة والدليل ومعيار الإغلاق)، و[12-STABILIZATION](12-STABILIZATION.md) (قسم بالتاريخ)، و[16-HANDOFF](16-HANDOFF.md) (الحالة الحالية)، و[17-TODO](17-TODO.md) (ما تأجل لغياب مورد).
2. **أضف مهام الماك** إلى [21-MAC-TASKS](21-MAC-TASKS.md) وفق جدول «ما الذي يستدعي مهمة» فيه. لا تكتب ما قد يُنسى داخل التقرير وحده.
3. في التقرير للمستخدم: ما نُفذ وما نجح وما فشل أو لم يُشغَّل، وأرقام المهام التي أضفتها للماك، وما ينتظر قرارًا منه.

عند **بدء كل جلسة على الماك:** اقرأ 21-MAC-TASKS أولًا، ونفّذ المفتوح منها، واكتب النتيجة والأدلة في الملف، وانقل ما يغلق عيبًا إلى 14-ISSUES.

**السجلات:** على الماك تحت `/Volumes/CUSU/Development/logs/`. على لينكس خارج المستودع، في `~/hayn-logs/` (تُنشأ عند الحاجة)، باسم البند والتاريخ، ولا تدخل Git. الأدلة الصغيرة المختارة تُلخص في الوثائق. المسارات المذكورة في 12 و16 للسجلات القديمة تخص الماك.

## 8. ما يمكن أن يبدأ به وكيل لينكس

الترتيب والتفاصيل في [16-HANDOFF](16-HANDOFF.md#العمل-على-جهازين-من-2026-10-02). ملخصه: التحقق من البيئة أعلاه، ثم T-16 (الصحة والأداء على Android، وأولها IMG-15)، ثم بنود السجل المفتوحة، ثم بحث الفيديو ([19-VIDEO-PLAN](19-VIDEO-PLAN.md)).
