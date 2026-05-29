# 02 — المعمارية (Architecture)

## نظرة عامة على الطبقات

```
┌──────────────────────────────────────────────┐
│  Presentation (Flutter widgets + Riverpod)     │  ← main isolate فقط
├──────────────────────────────────────────────┤
│  Application (use-cases, task orchestration)   │
├──────────────────────────────────────────────┤
│  Domain (entities, Result types, policies)     │
├──────────────────────────────────────────────┤
│  Data (repos, DB, file access, native channels)│
├──────────────────────────────────────────────┤
│  Engines (FFmpeg fork / native codecs / ONNX)  │  ← isolates + native
└──────────────────────────────────────────────┘
```

القاعدة الحاكمة: **الواجهة لا تعرف شيئًا عن FFmpeg أو ONNX**. تتعامل فقط مع use-cases تعيد `Stream<TaskProgress>` و`Result`.

## لماذا هذه الاختيارات

- **Riverpod**: حالة قابلة للاختبار، تتعامل جيدًا مع async/streams (تقدّم المهام).
- **Isolates**: Dart أحادي الخيط على الـ main isolate. أي عمل CPU (معالجة بكسلات، تنسيق، انتظار FFmpeg، تشغيل ONNX) يجب أن يكون في isolate حتى لا تتجمّد الواجهة. استخدم `Isolate.run` للمهام القصيرة و isolate طويل العمر مع `SendPort` للطوابير.
- **DB — drift (SQLite)**: اختير drift (لا isar — صيانته غير مستقرّة). يشغّل فهرس الميديا (القسم التالي)، ولاحقًا حالة المهام وسجلّ المعاملات الجراحية (journal). لا نخزّن الميديا نفسها في DB.

## فهرس الميديا (Media Index)

الفرز/الفلترة الصحيحة على مكتبة ضخمة تتطلّب معرفة **المكتبة كاملة**، و`photo_manager` يرقّم فقط (لا يفرز عالميًا). الحل: مرآة خفيفة لبيانات كل أصل في SQLite (drift).

- **الجدول `media_assets`**: `id`, `type`, `createdDate`, `modifiedDate`, `width`, `height`, `durationMs`, `sizeBytes` (nullable)، `title`, `mimeType` — مع فهارس على أعمدة الفرز (`created`/`size`/`type`). ≈250 بايت للأصل → بضعة ميجابايت لـ10 آلاف. لا تُخزَّن بايتات الميديا.
- **مسار مزدوج في `LibraryNotifier`**: التصفّح الافتراضي (الأحدث، بلا فلتر، أو ألبوم محدّد) يبقى على `photo_manager` السريع بلا تغيير؛ أما عند تفعيل فرز/فلترة على كل المكتبة فيُخدَم عبر استعلام DB مفهرس (`page`/`count`) ثم `AssetEntity.fromId` لإحضار الكيانات اللازمة للعرض (بحدّ تزامن).
- **الحجم بالبايت** عبر `MediaSizeChannel` (قناة native): Android من `MediaStore._size`، iOS من `PHAssetResource.fileSize` — **بلا فتح/تصدير الملف**. أي مُعرّف لا يحلّه النظام يسقط تلقائيًا إلى `asset.file` (محدود التزامن). فشل القناة لا يكسر شيئًا، فقط يبطّئ.
- **المزامنة** (`MediaIndexService`): مسح أوّلي على دفعات (upsert + حذف ما اختفى)، ثم تمرير حجم (native أولًا ثم fallback)، ويُحدَّث عند الإقلاع وعند `addChangeCallback` (debounce). إعادة المسح تحفظ الأحجام المحلولة.

> الاختبارات تغطّي منطق الاستعلام (`media_index_database_test`)، عقد القناة (`media_size_channel_test`)، المزامنة/الفروق (`media_index_service_test`)، وتحويل الفلتر→استعلام (`library_query_params_test`).

## طابور المهام (Task Queue)

كل عملية ثقيلة = `MediaTask` موحّد:

```dart
abstract class MediaTask {
  String get id;
  TaskType get type;            // compress, trim, gifify, separate, surgicalReplace...
  Stream<TaskProgress> run();   // تقدّم 0..1 + مرحلة وصفية
  Future<void> cancel();        // إلغاء نظيف يحرّر الموارد ويحذف المؤقتات
}
```

- منفّذ مركزي (`TaskRunner`) يدير التزامن (مثلًا مهمة ثقيلة واحدة + عدّة خفيفة)، الأولوية، والإلغاء.
- **Android Foreground Service** أثناء المهام الطويلة (ترميز/فصل صوت) حتى لا يقتلها النظام، مع إشعار تقدّم.
- **iOS**: المهام تكمل في المقدّمة؛ استخدم background task assertions لمهلة قصيرة، وأبلغ المستخدم أن إبقاء التطبيق مفتوحًا أأمن.
- كل مهمة تكتب مخرجاتها في مجلّد مؤقّت، وتُنقل/تُسجّل فقط عند النجاح. الإلغاء/الفشل ينظّف المؤقّتات.

## محرّكات المعالجة (Engines)

### 1) FFmpeg (فورك حيّ) — للقص/الاستخراج/الدمج/الصور المتحركة
- استدعاء عبر `ffmpeg_kit_flutter_new`. كل أمر = session مع callbacks للـ logs والتقدّم (parse من `time=` في الـ stats).
- يُشغّل ضمن task، والـ FFmpeg نفسه native فلا يجمّد الواجهة، لكن تنسيق المدخلات/المخرجات يبقى خارج الـ main isolate.
- **لا تستخدمه لإعادة ترميز الفيديو الثقيل** (انظر المحرّك التالي).

### 2) المُشفّر الأصلي (Native codec) — لإعادة ترميز الفيديو
- **Android**: `MediaCodec` + `MediaMuxer` (تسريع عتاد، البراءات يتكفّل بها النظام لا الـ binary).
- **iOS**: `VideoToolbox` + `AVAssetWriter`.
- يُستدعى عبر **platform channel** مخصّص (`native/`), يعيد تقدّمًا وإلغاءً.
- المبرّر: أسرع، أوفر للبطارية والحرارة، ويتجنّب تجميع x264/x265 (براءات نشطة) داخل التطبيق.

### 3) صور الصيغ الحديثة
- **AVIF (ثابت/متحرك)**: `flutter_avif` (`encodeAvif`) — libavif/aom، royalty-free. بطيء على الكبير → خيار غير افتراضي على الأجهزة الضعيفة.
- **HEIC**: مُشفّر النظام — iOS عبر ImageIO؛ Android عبر `HeifWriter`/خط الترميز العتادي. يتفادى تحميل HEVC في الـ binary.
- **WebP/JPEG/PNG**: `flutter_image_compress` و/أو libwebp داخل فورك FFmpeg.

### 4) فصل المصادر الصوتية — ONNX Runtime
- موديل **HTDemucs** (مُصدَّر ONNX) عبر `onnxruntime`، في isolate طويل العمر.
- خط الأنابيب الكامل في `docs/features/F5-audio-separation.md`.
- الموديل **مضمّن في `assets/models/`** (لأن أوفلاين). يُحمّل بكسل (lazy) عند أول استخدام لتقليل زمن الإقلاع.

## كشف قدرات الجهاز (Capability Detection)

وحدة `DeviceCapabilities` تُفحص مرّة وتُخزَّن:

| القدرة | كيف نكشفها | يؤثر على |
|---|---|---|
| HEVC/HEIC hardware encode | استعلام `MediaCodecList` (Android) / توفّر HEVC في VideoToolbox (iOS) | شجرة صيغ الصور والفيديو |
| AVIF encode عملي | اختبار ترميز عيّنة صغيرة وقياس الزمن | إتاحة AVIF افتراضيًا أو كخيار فقط |
| عدد الأنوية/الرام | platform info | درجة قوة الفصل الصوتي الافتراضية + التزامن |
| مستوى الحرارة/البطارية | thermal/battery APIs | إيقاف/تهدئة الدفعات |

> القاعدة: **اكشف، لا تفترض.** القرار الافتراضي «تلقائي» يُبنى على هذه القدرات.

## التعامل مع الذاكرة والملفات الكبيرة
- تدفّق (streaming) لا تحميل كامل في الرام للملفات الكبيرة.
- مجلّد مؤقّت لكل مهمة + تنظيف عند الانتهاء/الفشل/الإلغاء.
- مصغّرات تُولّد مرّة وتُخزَّن (DB + ملفات cache) لتصفّح سلس.

## عرض الصيغ الحديثة (Display pipeline)
- **iOS 16+/Android 12+**: فكّ AVIF/HEIC مدعوم نظاميًا غالبًا.
- **Android أقدم / حالات HEIC داخل Flutter**: فكّ لـ bitmap عبر native ثم اعرض، أو استخدم `flutter_avif` للـ AVIF. لا تعتمد على عرض Flutter المباشر لـ HEIC.
