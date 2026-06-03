# 10 — DarkLib: النواة الأصلية الموحّدة (Rust core)

> فرع `bedrock`. إعادة بناء كل ما يخصّ الضغط والميتاداتا والأعمال الثقيلة في **نواة واحدة بلغة Rust**
> اسمها **DarkLib**، تُربط بـFlutter عبر `flutter_rust_bridge` (FFI). هذا الملف هو المرجع الحاكم
> لكل عمل على الفرع — اقرأه قبل أي كود هنا.
>
> **مبدأ حاكم:** اكتب المنطق منخفض المستوى **مرة واحدة** في Rust. لا تكرّره في Swift/Kotlin/Dart.
> طبقة Dart منسّق رفيع فقط. المسارات الخاصة بالمنصّة (HW) مسرّعات اختيارية خلف نفس الواجهة.

---

## 1. لماذا DarkLib

الحلول الحالية على `main` موزّعة: ضغط عبر `flutter_image_compress`، AVIF عبر `flutter_avif` (libaom برمجي
لا يلمس العتاد)، حذف ميتاداتا JPEG/PNG/WebP بدارت + قناة iOS فقط للـHEIC/AVIF (أندرويد بلا حذف للـHEIC/AVIF).
نتيجتها: منطق مكرّر، فجوات بين المنصّتين، ومشاكل ميتاداتا/اتجاه/HDR متكرّرة.

DarkLib يوحّد كل ذلك: محرّك واحد، سلوك واحد، تغطية كل الصيغ على كل المنصّات، واختبارات golden تفرض
الصحّة. المسارات العتادية (MediaCodec/ImageIO/VideoToolbox) تبقى **مسرّعات** خلف الواجهة لا جوهر المنطق.

---

## 2. البنية في المستودع (Stage 0 — مُنجَز)

| المسار | الدور |
|---|---|
| `native/darklib/` | crate الـRust (النواة). `crate-type = ["cdylib","staticlib"]`. المنطق كله هنا. |
| `native/darklib/src/api/` | السطح العام المكشوف لـDart (مدخل codegen = `crate::api`). |
| `rust_builder/` | إضافة Flutter (cargokit) تبني الـ.so/static-lib تلقائيًا في Gradle/CocoaPods. **مولّدة — لا تعدّلها يدويًا إلا للضرورة.** |
| `lib/src/rust/` | روابط Dart المولّدة. الصنف المدخل = **`DarkLib`** (`DarkLib.init()` قبل أول استدعاء). **مولّد — لا يُحرّر.** |
| `flutter_rust_bridge.yaml` | إعداد codegen (input/root/output + اسم الصنف). |

**سلسلة الأدوات (تُعاد على Linux وMac):**
```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source "$HOME/.cargo/env"
rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android \
                  aarch64-apple-ios aarch64-apple-ios-sim
rustup component add rustfmt clippy
cargo install cargo-ndk flutter_rust_bridge_codegen   # المثبّت: frb 2.12.0 / cargo-ndk 4.1.2
```
نسخة `flutter_rust_bridge` في Dart **يجب** أن تطابق codegen (مثبّتة `2.12.0`).

**إعادة التوليد** بعد أي تغيير في `crate::api`:
```bash
source "$HOME/.cargo/env" && flutter_rust_bridge_codegen generate
```

**التحقّق لكل مرحلة (بوّابات الإخضرار):**
```bash
cd native/darklib && cargo fmt --check && cargo clippy -- -D warnings && cargo test   # نواة Rust
flutter analyze && flutter test                                                       # طبقة Dart
flutter build apk --debug      # أندرويد: cargokit يبني darklib لكل ABI ويحزمه
flutter build ios --no-codesign  # iOS: static lib عبر podspec
```
> لا أُثبّت على أجهزة المستخدم إطلاقًا. أنا أُبقي كل شيء أخضر وأدفع وحدات متماسكة؛ المستخدم يُثبّت ويختبر.

---

## 3. الواجهات الموحّدة (المرجع المعماري)

```
ImageCodec        : decode(target_size) / encode(opts) / transcode()   // عمل البكسلات
MetadataCodec     : extract() -> Canonical
                    inject(Canonical) / strip(policy)                   // بدون re-encode
                    transplant(srcBytes)                                // نسخ حرفي
Canonical         : exif, xmp, icc, iptc, gps, orientation(موحّد), capability
FormatDescriptor  : يدعم أي ميتاداتا؟ يقبل lossless ops؟ HDR/bit-depth؟
```
كل صيغة (JPEG/PNG/WebP/AVIF-HEIF) ملف يحمل **منطقه الخاص** ويُحقّق الواجهة العامة عبر dispatch.
بلا إفراط في التجريد، وبلا كسر منطق قائم — الانتقال تدريجي خلف هذه الواجهة (§قيود التنفيذ).

---

## 4. الميتاداتا (احتفاظ / حذف / تحويل) — Stage 1–2

مساران **منفصلان** (خلط بينهما = فقد بيانات صامت):
- **`transplant`** نقل بايت-لِفِل حرفي للحفظ/النسخ ضمن نفس النوع — يتفادى إسقاط MakerNotes أو الصناديق الخاصة.
- **`Canonical`** نموذج قانوني للتحويل بين الصيغ والتعديل فقط. `parse → reserialize` يُسقِط بصمت، فلا يُمرَّر على حالات الحفظ الحرفي.

**بدون إعادة ترميز** — جراحة على مستوى الحاوية لكل صيغة:
- **JPEG:** علامات APPn (EXIF/XMP في APP1، ICC في APP2)، دون لمس بيانات الصورة المضغوطة.
- **PNG:** chunks (`eXIf`/`iTXt`/`iCCP`) — أنظف صيغة.
- **WebP:** حاوية RIFF بـchunks (EXIF/XMP/ICCP) + تنظيف بتّات VP8X.
- **AVIF/HEIF:** صناديق ISOBMFF (`meta`/`iinf`/`iref` + عناصر EXIF/XMP) — **أصعب جزء، كود منخفض المستوى خاص بنا** (لا crate جاهز يشيل EXIF من AVIF دون لمس حمولة AV1).

> ملاحظة: منطق JPEG/PNG/WebP موجود فعلًا بدارت في `lib/.../image_ops/data/metadata.dart`. DarkLib
> يعمّمه إلى Rust ويضيف AVIF/HEIF + أندرويد + `transplant`/`inject`، ثم تُهاجَر ميزة الحذف خلفه (Stage 2).

**`strip(policy)` دالة حذف واحدة** عبر dispatch، تعالج حالتين بدقّة:
- **ICC:** الحذف الأعمى يغيّر الألوان → أبقِه أو حوّل لـsRGB ضمن السياسة.
- **Orientation:** الحذف دون "خبزه" في البكسلات يقلب الصورة → اخبزه ثم احذفه. (مصدر حقيقة واحد — §5.)

**مصفوفة قدرات الصيغ:** الواجهة تعطّل المستحيل وتنبّه عند فقد متوقّع في التحويل.

---

## 5. استراتيجية AVIF / AV1 — Stage 3–5

### الفك (decode) — حل عام، مب خاص بسناب دراغون
السبب الجذري للثقل الحالي: الفك يمرّ عبر decoder برمجي داخل الباكدج لا يلمس العتاد.
- **أندرويد:** `MediaCodec` لـ`video/av01` مع `isHardwareAccelerated()`؛ فُكّ ISOBMFF (`av1C` → OBUs)، الإخراج لـ`SurfaceTexture` → external texture (zero-copy). عامل الصورة الثابتة كفيديو من إطار واحد.
- **iOS:** `CGImageSource` (Image I/O) — AVIF منذ iOS 16، عتاد تلقائي على A17 Pro/A18/M3+، يتولّى 4:4:4/ألفا/grid صح.
- **بوّابة قدرات قبل اختيار العتاد:** مفكّكات AV1 العتادية غالبًا 4:2:0 و8/10-bit، بلا ألفا (aux item منفصل)، والكبيرة grid. افحص `av1C` + الألفا؛ غير متوافق → **fallback إلى dav1d**.
- **نموذج الجدوى:** تهيئة جلسة MediaCodec فيها latency؛ العتاد يربح في (الكبيرة + الـbatch مع إبقاء الجلسة حيّة + المتحرّك). للـthumbnail الصغير المفرد قد يكون dav1d أسرع. الـdispatch على **(الحجم + batch + متحرّك؟)** لا مجرد وجود العتاد.

### الإنكود (encode) — برمجي على كل الأجهزة
لا HW AV1 encode عملي على الجوال. اجعله **خيار "أقصى ضغط" واعٍ في الخلفية**، مب المسار اللحظي.
- backend: **SVT-AV1** (4:2:0/8–10bit) عبر libavif. للحالات 4:4:4 أو 12-bit → **rav1e/aom** (لا تُسقِط الميزة بصمت — قيد SVT-AV1).
- tiling لتوزيع الأنوية + presets عدوانية + threading كامل، 4:2:0+8-bit افتراضًا، بناء NEON/SIMD إلزامي. GPU للـpre/post (resize/colorconvert) فقط.

### الصحّة (لكل العمليات)
- **الاتجاه حقل موحّد first-class:** مصدر حقيقة واحد (EXIF orientation مقابل `irot`/`imir` مقابل TIFF)، لا يُطبَّق مرتين — هذا حلّ مشكلة انقلاب الصورة.
- **إدارة ألوان + HDR صحّة لا رفاهية، وHDR مفصول عن عمق البت:**
  - **gain-map HDR:** صور آيفون: صورة أساس (غالبًا 8-bit) + **gain map** + ميتاداتا رابطة (Apple/ISO 21496-1؛ Ultra HDR لـJPEG؛ AVIF يدعمها). الـgain map (وdepth map والألفا) **أصول مساعدة من الدرجة الأولى تسافر مع الأساس** — مب ميتاداتا قابلة للإسقاط.
  - **PQ/HLG (10/12-bit):** HDR→SDR يتطلّب tone-mapping؛ احفظ ICC وحوّل transfer function صحيحًا.
  - تحويل لصيغة لا تمثّل HDR → سياسة صريحة (اخبز / أبقِ SDR مع تنبيه / أسقط بإعلام)، لا إسقاط صامت.

محرّك AVIF = **libavif** (الحاوية كاملة: grid/alpha/gain maps/الألوان)، يُربط مرة واحدة في Rust (`libavif-sys`/bindgen). backends: SVT-AV1 (encode) + dav1d (decode).

---

## 6. الفيديو (قرار محسوم، تنفيذ لاحق)

- **AV1 encode برمجيًا على الجوال ممنوع** (انتحار أداء).
- **الافتراضي = HEVC عتادي** عبر النظام (VideoToolbox/MediaCodec) — ضغط ممتاز بصفر CPU تقريبًا.
- **AV1 encode فقط عند اكتشاف encoder عتادي** (`video/av01` + `isHardwareAccelerated`)، وإلا HEVC.
- **الترخيص:** HEVC عبر **كود النظام فقط** — لا تضمّن مرمّز HEVC خاصًا (x265/libde265) لتفادي إتاوات البراءات.

---

## 7. الصور الكبيرة (200MP+) — Stage 6

- **ممنوع منعًا باتًا تصغير أبعاد الإخراج.** الملف المحفوظ يبقى بكامل الدقة الأصلية دائمًا.
  > هذا **يُلغي** حلّ `encodeCapFor` (تصغير الحافة الطويلة) المؤقّت على `main`؛ في DarkLib الحل هو التبليط.
- **التبليط/التدفّق (tiling/streaming):** لا تُحضِر الصورة الكاملة كـbitmap واحد. عالِج بلاطة بلاطة بميزانية ذاكرة صريحة.
- للعرض فقط: `decode-to-target-size` / هرمي (البكسلات الأصلية محفوظة؛ تصغير العرض ليس غشًّا، تصغير الإخراج المحفوظ هو الغش).
- JPEG: عمليات lossless على حدود MCU (tile/crop/stitch) دون re-encode.

---

## 8. الخلفية ودورة الحياة + المعاينات + الاستقرار

- **الأساس: checkpoint + resume.** كل مهمة طويلة محفوظة على granularity البلاطة/الملف، التقدّم على القرص، queue دائم يُستأنف losslessly. لا تبنِ المعمارية على افتراض استمرار الخلفية.
- **مسرّعات best-effort:** أندرويد Foreground Service نوع `mediaProcessing` (≤6س/24، عالِج `onTimeout` بـ`stopSelf`). iOS `beginBackgroundTask` نافذة محدودة + الجلسات العتادية تُسحب عند الخلفية → عامِل الإكمال كأفضل-جهد لا ضمان.
- **خط معاينات منفصل:** thumbnails مضمّنة (EXIF/AVIF thumbnail item) + كاش LRU. **لا تفكّ الصورة الكاملة لخلية grid أبدًا.** إلغاء مربوط بدورة حياة الـwidget. (طوفان لوقات `Codec2Buffer`/`Kumiho` عرَض لغياب الإلغاء — يُحَل هنا.)
- **الاستقرار:** التطبيق محلي 100% (لا اعتبار لمستخدم خبيث/fuzzing). ملف تالف أو حافّة (إخراج كاميرا غريب، تنزيل مقطوع، ISOBMFF مشوّه) **لا يطيّح التطبيق** — افشل بلطف وأبلِغ. + حدود ذاكرة لـ200MP+.

---

## 9. الأهداف ومعايير القبول

1. AVIF بكامل ميزاته بلا مشاكل ميتاداتا ولا انقلاب.
2. حذف/احتفاظ ببيانات أي صيغة → أي صيغة.
3. إزالة بيانات أي صيغة **بدون re-encode** (Rust/C عند اللزوم).
4. عدم كسر أي منطق حالي؛ الانتقال عبر واجهة موحّدة باستثمار ذكي للـOOP.
5. فصل كامل للمسؤوليات وتنظيم يسهّل الصيانة بلا جحيم اعتماديات.
6. لا نتيجة أسوأ من الحالي على iOS/أندرويد، وسهولة إضافة منصّات.

**القياس (يفرض الأهداف، لا إحساس):**
- **Test corpus + golden files في CI** لكل (صيغة × عملية): `strip` → لا يبقى شيء، `preserve` → تطابق تام، `lossless` → البكسلات لم تتغيّر.
- **Observability:** لوقات بمستويات (تفلتر ضوضاء Codec2/Kumiho) + قياس لكل عملية (زمن الفك، المسار HW/SW، ذروة الذاكرة).

**الترخيص:** اعتماديات النواة **royalty-free فقط** (libavif, dav1d, SVT-AV1/rav1e/aom, libwebp, libjpeg-turbo, libpng) — يدعم النشر تحت GPL ويتجنّب تلوّث البراءات.

---

## 10. قيود التنفيذ

- لا تكسر منطقًا قائمًا، ولا تعديلات عشوائية. الانتقال تدريجي خلف الواجهة الموحّدة (دالة إزالة وصفية لمرة واحدة).
- التزم بأعراف المشروع في الهيكلة والتسمية والتنظيم.
- بلا إفراط في الطبقات؛ كل ملف صيغة يرث الواجهة العامة ويحمل منطقه الخاص فقط.
- أي اعتمادية في النواة: royalty-free + متوافقة GPL.

---

## 11. خارطة المراحل (كل مرحلة = خضراء + مدفوعة + قابلة لاختبار الجهاز)

| # | المرحلة | الحالة |
|---|---|---|
| **0** | سلسلة الأدوات + scaffold الـcrate + تكامل FRB + roundtrip أخضر (cargo test + analyze + apk) + هذا الملف | **مُنجَز** |
| **1** | نواة الميتاداتا في Rust (بلا codecs): `Canonical` + `FormatDescriptor`؛ جراحة الحاوية JPEG/PNG/WebP/AVIF-HEIF — extract/strip(policy)/transplant؛ حالتا ICC + الاتجاه؛ اختبارات golden | قادمة |
| **2** | مهاجرة ميزة "حذف الميتاداتا" الحيّة خلف الواجهة (تغطّي الآن أندرويد + AVIF/HEIF)؛ إبقاء المسار القديم fallback حتى الإثبات | — |
| **3** | طبقة الـcodecs (cross-compile C ثقيل): libavif (SVT-AV1 encode + dav1d decode) + libwebp + libjpeg-turbo + libpng؛ ImageCodec decode/encode/transcode | — |
| **4** | صحّة AVIF: الاتجاه حقل موحّد؛ إدارة ألوان/ICC؛ HDR gain-map (+depth/alpha) أصول مساعدة؛ بوّابة قدرات | — |
| **5** | مسرّعات الفك العتادية خلف واجهة الفك: MediaCodec `video/av01` (أندرويد) + ImageIO (iOS)، بوّابة قدرات، dispatch على (حجم/batch/متحرّك) | — |
| **6** | مهاجرة الضغط/التحويل إلى DarkLib؛ observability + golden CI؛ تبليط الصور الكبيرة (دون تصغير الإخراج) | — |

> مبدأ حاكم (من CLAUDE.md): البطء المقبول + النظافة المضمونة + السلامة > السرعة + المخاطرة.
