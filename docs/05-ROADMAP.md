# 05 — خارطة الطريق (Roadmap)

> كل مرحلة لها **معايير خروج (Exit Criteria)** يجب اجتيازها قبل الانتقال. لا تُعلن مرحلة مكتملة قبل اجتياز اختباراتها في `06-TESTING.md`.
> الترتيب مقصود: نبني الأساس والأخف أولًا، والأخطر/الأثقل أخيرًا.

---

## ملاحظة عن الحالة الحالية

**ما تم اليوم (شامل المرحلتين 0 و 1 + كل واجهات المراحل 2 → 6):**
- البنية الكاملة + Riverpod + GoRouter + StatefulShellRoute.
- الترجمة الكاملة (عربي/إنجليزي) + RTL/LTR + التبديل الفوري.
- تبديل الوضع (داكن/فاتح) مع انميشن "ستارة" مخصّص + لقطة بدقة الجهاز.
- تكامل `photo_manager` + تصفّح المكتبة + تصفية/فرز + ألبومات + multi-select كامل + بحث صلاحيات Limited.
- شاشة تفاصيل أصل كاملة: pinch-to-zoom مباشر بآلة حالة قفل بإصبعين + double-tap + سحب رأسي للإخراج برفلكس rubber-band + سحب صاعد لكشف الميتاداتا تدريجيًا + filmstrip + Hero مع المصغّرات.
- كل واجهات الأدوات: Compress (مع HaynComparisonViewer بزوم متزامن) — Surgical Arena (مفرد + Batch) — Crop (مع CropCanvas مخصّص بـ 8 handles + rule-of-thirds) — Trim Video — Crop Video — Remove Audio — Animate from Video/Photos — Extract Frames — Separate Music.
- زر مهام عائم قابل للسحب يلتصق بالحواف، بحالات نبض/خطأ/اكتمال، عدّاد بحد "99+".
- نظام مهام كامل (Tasks queue) مع إلغاء + إعادة محاولة + فلاتر.
- 30+ مكوّن مشترك (`HaynScaffold`, `HaynSegmentedPill`, `HaynPickerSheet`, `HaynComparisonViewer`, `HaynAdvancedSettingsCard`, `BatchSavingsEstimator`, ...).

**ما لم يُنجز بعد (محرّكات + كتابة فعلية):**
- محرّكات الترميز (AVIF/HEIC/WebP/JPEG) في isolates.
- تكامل `ffmpeg_kit_flutter_new` (الفيديو/الصوت).
- محرّك المعاملة الجراحية + الكتابة عبر MediaStore/PHContentEditingOutput.
- موديل HTDemucs (ONNX) لفصل الموسيقى.
- platform channels (MediaCodec / VideoToolbox) للفيديو المُسرَّع بالعتاد.

---

## المرحلة 0 — الأساس (Foundation) ✅
**الهدف:** هيكل مشروع نظيف وقابل للبناء عليه.
- إعداد Flutter + Riverpod + بنية المجلدات (`CLAUDE.md §5`).
- طبقة الترجمة (ar/en) + RTL/LTR + الثيم (داكن/فاتح) + design tokens.
- نوع `Result` + بنية الأخطاء.
- بنية الـ Isolates الأساسية + هيكل `MediaTask`/`TaskRunner` (بدون محرّكات بعد).
- `DeviceCapabilities` (هيكل + كشف أساسي).

**معايير الخروج:** ✅ التطبيق يبني ويعمل على Android، يبدّل اللغة والثيم فورًا، تخطيط RTL سليم، وهيكل المهام يشغّل مهمة وهمية مع تقدّم وإلغاء.

---

## المرحلة 1 — المتصفّح (Library Browser) ✅
**الهدف:** تصفّح ميديا الجهاز بسلاسة.
- صلاحيات (`permission_handler`) للمنصّتين + معالجة الرفض.
- قراءة الألبومات/الأصول (`photo_manager`).
- مصغّرات + كاش حجم/ثَمنيل + تمرير سلس + skeleton loaders.
- شاشة تفاصيل أصل + Hero transition + إيماءات الزوم.

**معايير الخروج:** ✅ تصفّح آلاف الأصول دون لاج (`RepaintBoundary` على كل بطاقة)، صلاحيات تعمل على Android، عرض HEIC من iPhone بنجاح.

---

## المرحلة 2 — عمليات الصور (Image Ops) [F1] 🟡 واجهة فقط
**الهدف:** أول قيمة فعلية + ترسيخ خط أنابيب الصور.

**تم:**
- ✅ واجهة Compress كاملة (Auto / Advanced) + معاينة قبل/بعد بالزوم.
- ✅ واجهة Crop كاملة بقماش مخصّص (CropCanvas) + AspectRatioChips + RotateFlipBar.
- ✅ Strip Metadata في multi-select toolbar.
- ✅ `BatchSavingsEstimator` بمنطقَي "حساب فعلي ≤5" و"تقدير من عيّنة >5".
- ✅ مقدّر الحجم في `CompressEstimateCard` (heuristic موحّد).

**باقي:**
- محرّكات الترميز الفعلية في isolates.
- تكامل `flutter_image_compress` (native) للضغط الأساسي.
- `flutter_avif` (libavif/aom) لـ AVIF.
- ضغط الـ thumbnails + persist للنتائج في تخزين مؤقت.

**معايير الخروج:** كل مسارات شجرة الصيغ (في `03-FORMATS.md`) تعمل، الشفافية محفوظة (لا PNG→JPEG)، الميتاداتا تُحفظ افتراضيًا وتُحذف عند الطلب، والإخراج أصغر فعليًا بجودة مقبولة. تطابق التقديرات الـ heuristic مع النتائج الفعلية ضمن ±20%.

---

## المرحلة 3 — محرّك FFmpeg + حذف الصوت + الصور المتحركة [F4 جزئيًا] 🟡 واجهة فقط
**الهدف:** دمج الفورك الحيّ وإثبات المسارات النظيفة.

**تم:**
- ✅ واجهة Remove Audio مخصّصة (lossless reassurance).
- ✅ واجهة Animate from Video كاملة + tile زمني.
- ✅ واجهة Animate from Photos (شبكة قابلة للترتيب).
- ✅ واجهة Extract Frames (وضع interval/fps/single + معاينة).

**باقي:**
- دمج `ffmpeg_kit_flutter_new` (LGPL) + غلاف tasks.
- حذف الصوت (`-c copy -an`) — نظيف 100%.
- استخراج فريمات.
- GIF (palettegen/paletteuse) + WebP متحرك + AVIF متحرك (`flutter_avif`).

**معايير الخروج:** حذف الصوت بلا أي إعادة ترميز (تحقّق ببت-للبت للفيديو)، GIF بلا banding واضح، الصيغ الثلاث للمتحرك تعمل، والتحكّم بالسرعة دقيق.

---

## المرحلة 4 — تحرير الفيديو [F3] 🟡 واجهة فقط
**الهدف:** قص نظيف + إعادة ترميز نظيف عند اللزوم.

**تم:**
- ✅ واجهة Trim Video مخصّصة + `VideoTimeline` بحلقات start/end + keyframe ticks + قراءات Start/Trimmed/End.
- ✅ واجهة Crop Video (يعيد استخدام `CropCanvas` مع thumbnail عالي الجودة).
- ✅ واجهة Video Editor الموحّدة (للمستخدم المتقدّم).
- ✅ banner ذكي يتبدل بين "lossless" و "smart cut" حسب موضع المقابض.

**باقي:**
- قص lossless عند keyframes (FFmpeg `-c copy`).
- smart cut (إعادة ترميز أطراف GOP فقط).
- قص حواف/تحجيم بالمُشفّر الأصلي (platform channel: MediaCodec/VideoToolbox).
- ضغط + تحكّم بالصيغة/الحاوية.

**معايير الخروج:** القص الدقيق يطابق الإطار المطلوب دون تضخّم حجم غير مبرّر، إعادة الترميز مرّة واحدة بجودة قريبة من المصدر، الناتج يُشارك ويُفتح في تطبيقات أخرى بلا كسر (لا اعتماد على crop metadata).

---

## المرحلة 5 — الميزة الجراحية [F2] ⚠️ 🟡 واجهة فقط
**الهدف:** الاستبدال الآمن. **ابدأ بـ Android (أسهل) ثم iOS.**

**تم:**
- ✅ Surgical Arena مفرد (Auto/Advanced + Comparison Viewer بالزوم + Stats + Preserved metadata + iOS path hint + Confirm destructive).
- ✅ Surgical Batch Screen (شبكة مصغّرات + إحصائيات إجمالية + Auto/Advanced + تأكيد جماعي).
- ✅ `BatchSavingsEstimator` (دقيق ≤5 / تقدير من عيّنة >5).
- ✅ Trash provider + retention setting + استعادة + حذف نهائي.

**باقي:**
- معاملة آمنة كاملة (شفّر → تحقّق → انسخ ميتاداتا → استبدل → سلة محذوفات/تراجع).
- Android: الكتابة عبر MediaStore content URI + الحفاظ على الـ ID/التواريخ.
- iOS: مسارا PHContentEditingOutput / حذف+إنشاء مع توضيح أثر «المضافة حديثًا».
- وضع دفعي مع حدود حرارة/بطارية + foreground service.
- journal/log للعمليات للاستعادة من crash.

**معايير الخروج:** صفر فقدان في اختبارات الإجهاد (بما فيها قطع أثناء العملية)، ترتيب الألبوم محفوظ، التواريخ/الميتاداتا منقولة، والتراجع يستعيد الأصل. **لا تنشر هذه الميزة قبل اجتياز كامل لاختبارات `06-TESTING.md`.**

---

## المرحلة 6 — فصل الموسيقى/الآلات [F5] ⚠️ 🟡 واجهة فقط
**الهدف:** إزالة الموسيقى وإبقاء الكلام، أوفلاين، بأقل تشويه.

**تم:**
- ✅ Separate Audio Screen كاملة (waveform + شريط القوة + Auto badge + ETA + tip banner + privacy footer).
- ✅ Separate Audio Result Screen (مقارنة قبل/بعد).

**باقي:**
- تضمين موديل HTDemucs (ONNX) + تشغيله في isolate.
- خط الأنابيب: استخراج PCM → فصل بنوافذ متداخلة (overlap-add) → دمج بنسخ الفيديو.
- تكامل `onnxruntime` package.

**معايير الخروج:** لا طقطقة عند حدود المقاطع، الكلام واضح بعد إزالة الموسيقى، الفيديو منسوخ بلا إعادة ترميز، والعملية في الخلفية مع تقدّم/إلغاء وforeground service.

---

## المرحلة 7 — الصقل (Polish)
- إعدادات كاملة (✅)، صفحة about (✅)، تحسين أداء/حرارة، مراجعة a11y وRTL وثيم على كل شاشة (✅ واجهات)، تلميع حركة وهابتكس (✅ مطبّق).
- صفحة تبرّع (مؤجّلة لما بعد المحرّكات).
- مراجعة a11y نهائية (مقاسات اللمس، contrast، VoiceOver/TalkBack).
- اختبارات الـ end-to-end على ملفات حقيقية متنوّعة (HEIC iPhone، HDR، PNG شفافية، Live Photo، VFR).

**معايير الخروج:** مراجعة شاملة لكل المعايير في `06-TESTING.md` + لا تجمّد + لا تسريبات ذاكرة في الدفعات الطويلة.

---

## أولويات المراحل القادمة (تنفيذ المحرّكات)

عند البدء بتنفيذ المحرّكات، الأولوية:

1. **محرّك الصور** (Phase 2): الأكثر استخدامًا، أقل خطورة. AVIF أولًا (إنجاز سريع عبر `flutter_avif`)، ثم HEIC/WebP/JPEG عبر `flutter_image_compress`.
2. **FFmpeg integration** (Phase 3): لـ remove audio + extract frames (سريع وآمن).
3. **حذف الصوت** (Phase 3): lossless، أبسط مسار للتحقّق من خط الأنابيب.
4. **الميتاداتا** (Phase 2): قراءة EXIF + كتابة سليمة بعد الضغط.
5. **الجراحية على Android** (Phase 5): البنية جاهزة، يحتاج تنفيذ MediaStore + verify pipeline.
6. **تحرير الفيديو** (Phase 4): trim lossless ثم smart cut.
7. **فصل الموسيقى** (Phase 6): أثقل ميزة، تأجيلها مقبول لإصدار لاحق.

عند ضيق الوقت: ركّز على المراحل 2-3-5 (Compress + Remove Audio + Surgical على Android). كل ما عداها يمكن تأجيله كإصدار v0.2.
