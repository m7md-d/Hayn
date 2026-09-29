# 14 — سجل العيوب والمتابعة

آخر تحديث: 2026-09-28. يشمل دفعة حماية التحويل (`910a281`) ودفعة المحاكي والمصغرات بعدها؛ نتائج الأخيرة وطريقة تشغيلها في [15-IOS-TESTING](15-IOS-TESTING.md). هذا السجل هو نقطة التسليم لمن يكمل العمل، ويفصل العيب المثبت عن المخاطرة وعن الميزة غير المنفذة. لا تنسخ ملفات من نسخ الفحص القديمة فوق المشروع. Git يديره المستخدم ولا يُسجَّل وضعه هنا؛ انظر التنبيه في [16-HANDOFF](16-HANDOFF.md).

**قرار المستخدم:** DarkLib باقية. الهدف تصحيحها وضبط حدودها؛ إزالة المكتبة أو العودة إلى main ليست مهمة مطروحة. الاستبدال الجراحي أزيل عمدًا ولا يعاد ضمن هذه الإصلاحات. العقد في [10-DARKLIB](10-DARKLIB.md)، وبحث الحاويات في [11-HDR-RESEARCH](11-HDR-RESEARCH.md)، والتاريخ والقياسات في [12-STABILIZATION](12-STABILIZATION.md)، والبيئة في [13-DEVELOPMENT](13-DEVELOPMENT.md).

## طريقة استخدام السجل

خطة التنفيذ المقترحة لكل بند وخطوة IMG-05 الأولى بالتفصيل في [دليل استلام العمل](16-HANDOFF.md). هذا السجل يبقى المرجع الحاكم للحالة والسبب والدليل ومعيار الإغلاق؛ المقترح لا يعني أن الإصلاح منفذ.

- الأرقام ثابتة حتى بعد الإصلاح. حدّث الحالة والدليل ومعيار الإغلاق في التغيير نفسه.
- «مثبت» = إعادة إنتاج أو تعارض واضح بين التنفيذ وعقده. «يحتاج قياسًا» لا يعني أن عطل جهاز أو OOM قد أُعيد فعليًا.
- «حماية جزئية» تعني منع حالة فقد معينة، ولا تعني أن المسار أصبح يحفظ الخاصية. لا تغلق مشكلة HDR أو اللون بمجرد نجاح build أو round-trip داخلي.
- المواضع أدناه أسماء ملفات ودوال، لا أرقام سطور قابلة للتغير. جميع الروابط من هذا المستودع؛ السجلات المحلية أدلة إضافية وليست شرطًا لفهم المشكلة.
- الأولوية P1 لسلامة المخرجات، P2 للموثوقية والبناء، P3 لعدم اتساق التوثيق أو ميزات خارج نطاق التثبيت. لا commit أو push أو تثبيت على هاتف دون طلب.

## دفعة حماية التحويل (910a281) — 2026-09-27

النطاق: `unknown` للشفافية؛ إذن صريح لتغيير الصيغة؛ فحص هوية صيغة الناتج وقناته الشفافة؛ رفض سقوط HDR المعروف داخل Rust؛ إيصال رفض الحفظ إلى Dart كرفض نهائي. **ليس تنفيذًا كاملًا لـSourceFacts/Plan/ConversionResult أو ضمانًا لجميع backends.**

قبل الإصلاح فشلت الحالات الخمس في `test/preservation_regression_test.dart` والحالات الخمس في `native/darklib/tests/preservation.rs` بالسلوك المتوقع من العيوب. عينتا HDR مستقلتان في `native/darklib/tests/fixtures/`. النتائج: **174 اختبار Flutter + 79 Rust (74 وحدة و5 انحدار) + 3 اختبارات جسر حقيقي** ناجحة؛ التحليل وfmt وclippy ناجحة. ImageIO المستقل قرأ عينة PQ بعمق 10 ووجد ISO gain map في العينة الثانية. بناء Android debug للمعماريتين وبناء iOS release بلا توقيع نجحا مجددًا بعد آخر تصحيح للجسر (21.7 ثانية و36.5 ثانية محليًا، بناء incremental لا benchmark أداء). لم يجر اختبار هاتف.

تفصيل مهم لإعادة الإنتاج: أول اختبار دوران لم يحقن EXIF بالفعل لأن inject يحافظ على عنصر Exif موجود؛ كان فشل إعداد اختبار لا دليل عطل. صُحح بتبديل خانة TIFF دون تحريك offsets، ثم أعيدت الحالات الخمس على نسخة `ddc06a8` المعزولة وفشلت كلها في توقع رفض التحويل. السجل المعتمد `preservation-red-rust-corrected.log`. كذلك أثبت الجسر الحقيقي أن أخطاء `Result<_, String>` ترمى كنص، وصُحح الالتقاط والـmock بدل الاعتماد على نوع Anyhow غير مطابق.

## سلامة الصورة وعقد التحويل

### IMG-01 · P1 · الشفافية المجهولة تتحول إلى false

- **الحالة:** حماية الفحص/اختيار المحرك مختبرة محليًا؛ فك alpha للشبكات ما زال IMG-02، والمصدر المجهول يصدر تحذيرًا ولا يعد حفظه مثبتًا.
- **المواضع:** [ImageProbe.hasAlpha](../lib/features/image_ops/data/image_probe.dart)، [NativeImageProbe](../lib/features/image_ops/data/native_image_info.dart)، `ImageProbeNative.probe` في [جسر iOS](../ios/Runner/AppDelegate.swift)، [سياسة الصيغة](../lib/features/image_ops/domain/image_format_policy.dart)، [ImageEncoder](../lib/features/image_ops/data/image_encoder.dart).
- **السبب والأثر:** اسم HEIC/AVIF اعتُبر دليلًا على غياب الشفافية، والحقول الغائبة من الجسر لها قيم افتراضية؛ يسمح هذا بـJPEG أو AVIF العتادي الذي يحول إلى I420 بلا alpha. فشل فك PNG كان يتحول إلى جواب مؤكد أيضًا.
- **معيار الإغلاق:** إبقاء unknown، عدم إجازة JPEG عند present/unknown، استبعاد backend الذي لا يحفظ alpha، والتحقق من الناتج؛ اختبارات مصدر شفاف ومعتم وفحص ناقص/فاشل. مجرد اختيار صيغة تدعم alpha لا يثبت أن المحرك حفظها.

### IMG-02 · P1 · فقد شفافية AVIF المبلط أو تجاهل فشل ألفا

- **الحالة:** مثبت؛ غير مصلح.
- **المواضع:** `decode`/`decode_item` في [avif_dav1d.rs](../native/darklib/src/engine/codec/avif_dav1d.rs)، و`alpha_item_id` في [isobmff.rs](../native/darklib/src/engine/metadata/isobmff.rs).
- **السبب والأثر:** تجميع اللون من البلاطات ثم البحث عن مساعد alpha على المستوى الأساسي فقط؛ فشل فك ألفا أو اختلاف أبعادها يترك الصورة معتمة. عينة libavif `color_grid_alpha_nogrid.avif` أصبحت بلا بكسل شفاف في الفحص المستقل.
- **معيار الإغلاق:** احترام علاقات alpha لكل عنصر/بلاطة وترتيب التحويلات، رفض فشل ألفا، ومقارنة قناة ألفا بقارئ مستقل للشبكات والصورة المفردة. حماية Dart في IMG-01 لا تصلح decoder نفسه.

### IMG-03 · P1 · HDR مباشر يفقد الدقة ودالة النقل

- **الحالة (2026-09-28):** وفق سياسة المستخدم، الهدف نسخة SDR صحيحة لا حفظ PQ/HLG. يُفحص المصدر الأصلي قبل أي محرك. يُطلب tone mapping من ImageIO (`kCGImageSourceDecodeToSDR`، iOS 17+)، ثم يُتحقق من الناتج؛ إن بقي PQ/HLG أو لم يتوفر الطلب يُرفض قبل أي backend، بما فيه عتاد Android (`hdrToneMapUnavailable`). رفض Rust للأصل باقٍ ويعبر FFI. **على محاكي iOS 26.3 يتجاهل ImageIO الطلب ويعيد 10-bit PQ** (ويطبقه macOS 15)، فلم يُثبت مسار التحويل على iOS بعد، والمحاكي يرفض PQ مبكرًا. لم يُختبر على هاتف، ولا iOS 15/16، ولا HLG بعينة حقيقية.
- **المواضع:** `Decoded`/`transcode` في [codec/mod.rs](../native/darklib/src/engine/codec/mod.rs)، تحويل العينات في [avif_dav1d.rs](../native/darklib/src/engine/codec/avif_dav1d.rs)، [color.rs](../native/darklib/src/engine/color.rs).
- **السبب والأثر:** وسيط RGBA8 يخفض الدقة ولا يحمل transfer/range؛ `seine_hdr_rec2020.avif` بدأ Rec.2020/PQ `(9,16)` وخرج بتفسير sRGB عند ImageIO. رفع عمق ملف الناتج لا يستعيد المعلومات.
- **معيار الإغلاق:** نسخة SDR مطابقة لـtone mapping النظام أو رفض قبل أي محرك، على corpus مستقل PQ وHLG وICC بما يشمل غياب nclx أو تعقيد graph، وعلى المحاكي وAndroid. اختبار الآيفون الفعلي وiOS 15/16 مرفوض بقرار المستخدم (2026-09-29)؛ تحويل PQ على الهاتف يبقى قيدًا غير مثبت. الفحص يقرأ nclx للعنصر الأساسي وcICP في PNG؛ PQ موصوف بـICC وحده لا يُكشف بعد.

### IMG-04 · P1 · فشل gain map قد يمر كتحويل SDR ناجح

- **الحالة (2026-09-29):** لم يعد إسقاط الخريطة رفضًا، بقرار المستخدم. `transcode` يعيد `HdrOutcome`: AVIF→AVIF بالحجم الكامل بلا دوران يحفظ الخريطة (`GainMapKept`، مثبت بـImageIO في IMG-10)، وغيره يُرمَّز أساسه SDR (`GainMapDropped`)، وفشل الحفظ يعطي الأساس مع `GainMapKeepFailed`. Dart يسجل `hdrToSdr`/`hdrKeepFailed` ولا يحذّر المستخدم.
- **المواضع:** `transcode` في [codec/mod.rs](../native/darklib/src/engine/codec/mod.rs)، `read_tmap`/`has_gainmap` في [isobmff.rs](../native/darklib/src/engine/metadata/isobmff.rs)، [_call](../lib/core/darklib/darklib.dart)، [_tryEncode](../lib/features/image_ops/data/image_encoder.dart).
- **السبب والأثر:** `None` تعني غياب خريطة أو فشل معالجتها معًا، وبعدها ينفذ SDR. تغيير الهدف/التصغير يتجاوز مسار الخريطة. EXIF rotation كان يغير الأساس وحده، وirot/imir يسقطان إلى SDR. `keepMetadata=false` لا يعد إذنًا لحذف جزء HDR من الصورة.
- **معيار الإغلاق:** الفصل بين الغياب والإسقاط المقصود وفشل الحفظ، مختبر: graph ناقص، transform، resize، هدف مختلف، ونجاح المسار الأساسي (`native/darklib/tests/preservation.rs`، `test/hdr_plan_test.dart`). يبقى: أساس HDR غير موصوف بـnclx في صورة gain map لا يُكشف، فيُرمَّز كأنه SDR.

### IMG-05 · P1 · عقد الحفظ الشامل والتخطيط قبل الترميز غير مكتملين

- **الحالة (2026-09-28):** منفذ جزئيًا ومختبر محليًا. `SourceInspector` يفحص الأصل مرة واحدة (ألفا، PQ/HLG، gain map) من Rust `inspect_image` وImageIO، ويسلّم `SourceFacts` لاختيار الصيغة والمحرك في الضغط والقص والمعاينة. PQ/HLG لا يصل لأي محرك إلا نسخةً SDR من ImageIO؛ عتاد AVIF لا يعمل إلا على مصدر معروف أنه ليس PQ/HLG ولا شفاف؛ وجسر HEIC→PNG يطلب نسخة SDR. نتيجة الخريطة تُسجل داخليًا. غير منفذ بعد: بقية الحقائق (الأبعاد، الاتجاه، ICC، العمق)، فحص decode كامل للناتج، خطأ typed بدل نص `preservation_required:`، وفحص HDR منصي على Android (يعتمد الآن على قراءة الحاوية في Rust).
- **المواضع:** [ImageEncoder](../lib/features/image_ops/data/image_encoder.dart)، [DarkLibCore](../lib/core/darklib/darklib.dart)، [NativeImageEncoder](../lib/features/image_ops/data/native_image_encoder.dart)، `ImageEncoderNative`/`bakeUpright` في [AppDelegate.swift](../ios/Runner/AppDelegate.swift)، [عقد التصميم](10-DARKLIB.md).
- **السبب والأثر:** الصيغة النظرية وقدرة `keepMetadata` لا تثبت الحفظ. HEIC→PNG→RGBA8→AVIF قد يفقد HDR/اللون. hardware قد ينجح قبل فحص Rust؛ transplant قد يعيد target كما هو ويعد نجاحًا. حقول ConversionLoss النظرية ليست متصلة بجميع المسارات. `EncodedImage` يحمل المحرك والصيغة والتشخيص، وليس تقرير حفظ كاملًا.
- **دليل إعادة الإنتاج (2026-09-28):** اختبار مؤقت بقنوات ومحاكاة DarkLib على طبقة `ImageEncoder`، سجله `/Volumes/CUSU/Development/logs/img05-gap-reproduction-20260928.log`. ثلاثة مسارات نجحت ولم يُستشر فحص HDR في أي منها: (أ) مصدر HEIC يعلن ImageIO أنه HDR، والهدف WebP: خطأ Rust العادي في فك HEIC ليس رفض حفظ، فيمر الجسر `bakeUpright`→PNG→Rust وينجح. (ب) عينة PQ `seine_hdr_rec2020.avif` إلى AVIF: عتاد Android ينجح ولا تُستدعى Rust، بينما ترفض Rust المصدر نفسه وحدها. (ج) مصدر HDR إلى HEIC مع `keepMetadata=false`: ImageIO ينجح، وSwift لا ينسخ gain map إلا عند `keepMetadata` (`ImageEncoderNative.encode`). محاكاة القنوات تثبت ترتيب القرار في Dart، لا سلوك الناتج الأصلي؛ فقد (ج) مستنتج من كود Swift.
- **الإصلاح والتحقق (2026-09-28):** الأحمر: الاختبار المؤقت أعلاه على الكود قبل الإصلاح. الأخضر: 9 حالات في `test/hdr_plan_test.dart`، و7 انحدار Rust على عينتي libavif، و5 اختبارات جسر حقيقي على المضيف، ومجموعة المحاكي (15-IOS-TESTING). القص يستخدم النسخة SDR نفسها، لكنه بلا اختبار وحدة لأنه يحتاج محاكاة photo_manager.
- **المطلوب التالي:** SourceFacts موثوقة مع unknown، سياسة preserveRequired وفقد مسموح محدد، تخطيط قدرات كل backend، تحقق قبل الحفظ وتقرير نتيجة. لا تستخدم علمًا عامًا باسم «حفظ» بينما تفحص alpha وحدها.

### IMG-06 · P1 · MPF في JPEG Ultra HDR يصبح غير صالح بعد التنظيف

- **الحالة:** مثبت؛ غير مصلح.
- **المواضع:** `strip_bytes` في [metadata/jpeg.rs](../native/darklib/src/engine/metadata/jpeg.rs)، [تنظيف Dart](../lib/features/image_ops/data/metadata.dart).
- **السبب والأثر:** بقاء APP2/MPF مع حذف/اختصار EXIF/XMP يترك offsets والأحجام القديمة. في `seine_sdr_gainmap_srgb.jpg`: 142972→74701 بايت؛ المؤشر الثاني لم يعد يصل إلى FF D8. بقاء حمولة الخريطة لا يثبت إمكانية العثور عليها.
- **معيار الإغلاق:** إعادة بناء offsets والأحجام والتحقق بقارئ MPF مستقل وHDR، أو رفض هذه العملية إلى حين دعمها. اختبر الخصوصية أيضًا؛ لا ترجع الأصل على أنه منظف.

### IMG-07 · P1 · التنظيف يحذف اتجاه العرض

- **الحالة (2026-09-29):** أُصلح ومختبر محليًا وبقارئ مستقل لـJPEG وPNG وWebP. حذف EXIF يترك مكانه EXIF مصغرًا فيه Orientation وحده (`exif::orientation_only`) حين يكون الاتجاه غير 1، وفي WebP يبقى علم EXIF في VP8X. أزيل منظف Dart الاحتياطي (`MetadataStripper.strip*`) لأنه نسخة ثانية من السلوك نفسه بالخلل نفسه؛ بقي `canStrip` للواجهة، وفشل DarkLib يُعدّ الآن «غير مدعوم» بدل حفظ صورة مقلوبة.
- **الدليل:** الأحمر `img07-red-20260929.log`: فشلت الصيغ الثلاث من الاتجاه 2. الأخضر: `native/darklib/tests/strip_orientation.rs` يقارن الصورة المعروضة (بعد تطبيق الاتجاه) قبل التنظيف وبعده للاتجاهات 1–8 على صورة 6×4 غير متناظرة، ويتحقق من زوال GPS. القارئ المستقل `test_native/inspect_strip_orientation.swift` (ImageIO على الماك) قرأ الاتجاه والأبعاد المعروضة وغياب GPS في 24 ملفًا (`img07-independent-20260929.log`).
- **المتبقي:** AVIF/HEIC يعتمدان `irot`/`imir` التي لا يمسها التنظيف، لكن لا اختبار بعينة فيها هذه الخصائص. منظف iOS الأصلي الاحتياطي لـHEIC/AVIF غير مختبر للاتجاه. عرض المعرض على Android في T-13 (docs/17).
- **المواضع:** [metadata/jpeg.rs](../native/darklib/src/engine/metadata/jpeg.rs)، [png.rs](../native/darklib/src/engine/metadata/png.rs)، [webp.rs](../native/darklib/src/engine/metadata/webp.rs)، `orientation_only` في [exif.rs](../native/darklib/src/engine/metadata/exif.rs)، [strip_metadata_task.dart](../lib/features/image_ops/data/strip_metadata_task.dart).
- **السبب والأثر:** حذف APP1/EXIF كاملًا دون حفظ orientation أو baking؛ JPEG بأبعاد تخزين 40×24 واتجاه 6 عُرض بعد التنظيف 40×24 بدل 24×40، خلاف السياسة المعلنة.
- **معيار الإغلاق:** اتجاهات 1–8 وصورة غير مربعة؛ EXIF مصغر آمن أو تحويل بكسلات معلن، مع حذف البيانات الخاصة فعلًا. وسّع الاختبار لبقية الحاويات بدل افتراض اشتراكها في السلوك الصحيح.

### IMG-08 · P1 · خيار الخصوصية يحذف ICC دون تحويل لون

- **الحالة:** مثبت؛ غير مصلح.
- **المواضع:** [DarkLibCore.transcode](../lib/core/darklib/darklib.dart)، [codec/mod.rs](../native/darklib/src/engine/codec/mod.rs)، [metadata/inject.rs](../native/darklib/src/engine/metadata/inject.rs).
- **السبب والأثر:** `keepMetadata=false` يختار إعادة ترميز بلا ICC؛ PNG P3→WebP lossless يحفظ أرقام البكسلات ويغير معناها اللوني. stripIcc العشوائي له الخطر نفسه.
- **معيار الإغلاق:** فصل بيانات الكاميرا/الموقع عن ICC/CICP والاتجاه؛ إبقاء اللون أو تحويله صحيحًا. قارن بقارئ يدير اللون، لا بمطابقة RGBA وحدها.

### IMG-09 · P2 · pixi لا يطابق عمق AV1 الفعلي

- **الحالة (2026-09-29):** أُصلح للكاتبين. `pixi_for_av1c` يشتق عدد القنوات والعمق من علمي `high_bitdepth`/`twelve_bit` و`monochrome` في `av1C` لكل عنصر (الأساس والخريطة والشبكة). اختبار `pixi_matches_av1c_in_hdr_and_grid_writers`، وImageIO يقرأ الناتج. دليل 2026-09-28 قبل الإصلاح: `av1C` يعلن 10 بت و`pixi` = 8. المتبقي: شبكة حقيقية فوق 16 ميغابكسل بقارئ مستقل (تحتاج موارد وزمنًا، لا جهازًا).
- **المواضع:** `build_grid_avif` و`build_hdr_avif` في [isobmff.rs](../native/darklib/src/engine/metadata/isobmff.rs)، `encode_avif_single`/`encode_avif_grid` في [codec/mod.rs](../native/darklib/src/engine/codec/mod.rs).
- **السبب والأثر:** pixi يعلن 8 بت بينما ravif قد يشحن AV1/av1C بعمق 10. قبول decoder الداخلي أو ImageIO للملف لا يزيل تناقض الحاوية.
- **معيار الإغلاق:** اشتقاق العمق من الإعداد/الحمولة الفعلية، تطابق av1C وpixi والتيار لكل عنصر، وقارئ مستقل. يشمل المسار الصور فوق 16×1024×1024 بكسل؛ لا يقتصر على 200MP.

### IMG-10 · P1 · صلاحية gain map بعد تغيير الأساس لم تثبت

- **الحالة (2026-09-29):** أُصلح لـISO gain map في AVIF→AVIF ومثبت بقارئ مستقل. الكاتب يضيف علامة `tmap`، ويحمل خصائص عنصر `tmap` من الأصل (`pixi`/`colr` للبديل HDR)، ويشتق `pixi` من `av1C`، ويعطي مجموعة `altr` معرّفًا لا يتصادم مع معرفات العناصر. السبب الجذري لتجاهل ImageIO كان المعرّف: `group_id` = 1 هو معرّف الأساس نفسه، والمعرّفات مشتركة في ISOBMFF. أعيد تفعيل الحفظ في `transcode`.
- **دليل 2026-09-29:** ImageIO على الماك يرى ISO gain map في ناتجنا بـHeadroom 2.462 كالأصل وصورة واحدة. `test_native/compare_hdr_rendition.swift` يفك الأصل والناتج بـ`kCGImageSourceDecodeToHDR` في Display P3 خطي: القمة 2.435 مقابل 2.422 (HDR مطبق)، ومتوسط الفرق 1.98% مع البيانات و1.94% بدونها، وهو فرق إعادة الترميز lossy عند جودة 80. السجل `img10-independent-20260929.log`. المتبقي: Apple gain map القديم في HEIC خارج Rust (ImageIO)، وgain map بأساس HDR، وعينات أكثر (T-12).
- **دليل 2026-09-28:** حوّلنا عينة `seine_sdr_gainmap_srgb.avif` إلى AVIF بمسار الحفظ. ImageIO على الماك (macOS 15) ومحاكي iOS 26.3 يرى في الأصل ISO gain map (Headroom 2.46)، ولا يرى أي خريطة في ناتجنا (Headroom 1)، ويعدّ فيه صورتين. مقارنة الصناديق: ناتجنا بلا علامة `tmap` في `ftyp`، وعنصر `tmap` فيه `ispe` وحده بلا `pixi` و`colr`، والخريطة بلا `pixi`، و`pixi` لا يطابق `av1C` (IMG-09). الملفات في `build/ios-preservation/20260928-194848/`. قراءة `read_tmap` في Rust للناتج لم تكن إلا تحققًا ذاتيًا.
- **المواضع:** `read_tmap`/`build_hdr_avif`/`pixi_for_av1c` في [isobmff.rs](../native/darklib/src/engine/metadata/isobmff.rs)، `transcode_hdr_avif` في [codec/mod.rs](../native/darklib/src/engine/codec/mod.rs)، نقل auxiliary في [AppDelegate.swift](../ios/Runner/AppDelegate.swift).
- **السبب:** إعادة ترميز/تغيير اللون أو الهندسة للأساس ثم نقل الخريطة ومعاملاتها لا يثبت أنهما متوافقان. اختبار Rust القديم يحمل نصًا اصطناعيًا كمعاملات tmap؛ يفحص نقل بايتات وليس دلالة الإضاءة. قراءة graph وprimary والبدائل وترتيب dimg تحتاج تحققًا أدق؛ لا يكفي إيجاد أول tmap.
- **معيار الإغلاق:** Apple gain map وISO gain map منفصلان؛ ImageIO يرى الخريطة وheadroom الصحيح في ناتجنا؛ مقارنة إعادة البناء في فضاء خطي وعند headroom معلوم؛ الحالات غير المثبتة تعطي الأساس SDR. عندها يعاد تفعيل الحفظ في `transcode`. لا تحذف grid: هي تركيب مكاني وليست gain map.

### IMG-11 · P2 · تغيير الصيغة تلقائيًا وقبول ناتج بلا فحص

- **الحالة:** قيد الصيغة وفحص هويتها مختبران محليًا؛ تحقق الملف الكامل ضمن IMG-05.
- **المواضع:** `encode`/`fallbackChain` في [ImageEncoder](../lib/features/image_ops/data/image_encoder.dart)، [ImageCompressTask](../lib/features/image_ops/data/image_compress_task.dart)، [compress_screen.dart](../lib/features/image_ops/presentation/compress_screen.dart).
- **السبب والأثر:** المستخدم يطلب JPEG أو AVIF، وبعد فشل المحرك تقبل صيغة أخرى. تسمية الناتج تتبع format المطلوب من backend دون فحص البايتات. السجل السابق حذّر من fallback لكنه لم يشترط الإذن.
- **معيار الإغلاق:** الصيغة المحددة لا تتغير؛ Auto يجيز اختيار صيغة أخرى مع تشخيص، ورفض هوية ناتج خاطئة. فحص signature ليس تحققًا كاملًا من صلاحية decode أو اللون/HDR؛ يرتبط بـIMG-05.

### IMG-12 · P2 · تاريخ EXIF والعمق المطلوب غير موحدين بين المحركات

- **الحالة:** فجوة مثبتة بتتبع المعاملات؛ تحتاج عينات إخراج.
- **المواضع:** [ImageEncoder._tryEncode](../lib/features/image_ops/data/image_encoder.dart)، [ImageCompressTask](../lib/features/image_ops/data/image_compress_task.dart)، [GallerySaver](../lib/features/image_ops/data/gallery_saver.dart)، [Rust codec API](../native/darklib/src/api/codec.rs).
- **السبب والأثر:** `keepOriginalTime` لا يصل إلى Rust كما يصل إلى ImageIO؛ قد يختلف وقت الأصل في المعرض عن EXIF في الملف المشترك. `bitDepth` لا يصل إلى AVIF software؛ «match source» في الواجهة لا يثبت حفظ HDR/العمق.
- **دليل المحاكي:** JPEG الاصطناعي 776→890 بايت بعد Photos؛ الاختلاف محصور في EXIF (حقول دقة العرض وإصدار EXIF وتوصيف المكونات والمشهد). بقية المقاطع بما فيها scan متطابقة، وبكسلات ImageIO متطابقة. لذلك فرق الحجم هنا ليس إعادة ترميز أو فقد جودة. هذه العينة بلا وقت/GPS؛ لا تثبت سياسة حفظهما. التفاصيل في [15-IOS-TESTING](15-IOS-TESTING.md).
- **معيار الإغلاق:** سياسة واضحة لكل حقل، نتيجة فيها العمق الفعلي، وفحص EXIF/وقت الأصل على iOS وAndroid. لا تفسر bit depth وحده بأنه HDR.

## الموارد والتشغيل والأجهزة

### RUN-01 · P1 · ذاكرة بلا ميزانية وفقد أبعاد ضمني

- **الحالة:** ترتيب الحجز والتصغير مثبت في الكود؛ OOM/ذروة الجهاز لم تقاس.
- **المواضع:** `decode`/`finish`/`encode_avif_grid` في [codec/mod.rs](../native/darklib/src/engine/codec/mod.rs)، canvas في [avif_dav1d.rs](../native/darklib/src/engine/codec/avif_dav1d.rs)، `encodeCapFor` في [ImageEncoder](../lib/features/image_ops/data/image_encoder.dart)، `MAX_EDGE` في [AvifHwEncoder.kt](../android/app/src/main/kotlin/app/naqaa/hayn/AvifHwEncoder.kt).
- **السبب والأثر:** فك كامل ثم تصغير؛ التبليط يحتفظ بالمصدر الكامل. 200MP RGBA8 نحو 800MB قبل النسخ. سقف 8192 يصغّر المحفوظ ضمنيًا ولا يمنع تخصيص decoder الأول.
- **معيار الإغلاق:** ميزانية قبل الحجز وحدود أبعاد/عناصر/overflow؛ معاينة تفك مصغرًا فعليًا؛ رفض صريح عند شرط حفظ الأبعاد. لا ترفع السقف وحده ولا تصف التبليط بأنه ذاكرة محدودة من المصدر.

### RUN-02 · P2 · تزامن العمل الثقيل وإلغاء الصور غير محدودين

- **الحالة:** ترتيب إلغاء TaskRunner أُصلح، إيقاف native والتزامن ما زالا غير مكتملين.
- **المواضع:** [TaskRunner.enqueue](../lib/core/isolates/task_runner.dart)، [compress_screen.dart](../lib/features/image_ops/presentation/compress_screen.dart)، [ImageCompressTask](../lib/features/image_ops/data/image_compress_task.dart)، [ImageCropTask](../lib/features/image_ops/data/image_crop_task.dart)، [Rust codec API](../native/darklib/src/api/codec.rs).
- **السبب والأثر:** المهام تبدأ مباشرة، ومعاينة أحدث تتجاهل نتيجة القديمة دون وقف عملها؛ علم الإلغاء يفحص بين الخطوات ولا يقطع الترميز الجاري.
- **معيار الإغلاق:** بوابة مشتركة للمهام والمعاينات، حد ذاكرة/تزامن، وإلغاء native قابل للاختبار أو تصريح واضح بنقاط الإلغاء. قياس ذروة العمل المتداخل على جهاز.

### RUN-03 · P2 · الإكمال الأصلي لجلسة FFmpeg شرط للتنظيف

- **الحالة:** الإصلاح السابق ينتظر completion بعد طلب cancel؛ سلوك غياب callback يحتاج اختبار منصة.
- **المواضع:** `FfmpegRunner` في [ffmpeg_runner.dart](../lib/features/video_ops/data/ffmpeg_runner.dart)، [اختبار العمر](../test/ffmpeg_lifecycle_test.dart).
- **المطلوب:** اختبار إلغاء حقيقي وفشل بدء/نهاية العملية مع FFmpeg 3.6.2. لا تضف timeout يحذف الملفات فيما native لا يزال يكتب إليها.

### RUN-04 · P2 · الاستئناف والخلفية ليسا منفذين

- **الحالة:** فجوة نطاق، لا عطل codec جديد.
- **المواضع:** [TaskRunner](../lib/core/isolates/task_runner.dart)، [MediaTask](../lib/core/isolates/media_task.dart).
- **السبب:** حالة الطابور في الذاكرة؛ لا checkpoint/resume مكتمل بعد قتل التطبيق ولا ضمان خلفية. يلزم تحديد وعد المنتج قبل بناء طابور دائم أو خدمات منصة.

### RUN-05 · P2 · فشل الصورة المصغرة يتسرب إلى الواجهة

- **الحالة:** أُصلح تسرب الاستثناء؛ 6 اختبارات انحدار ناجحة، وفتح المكتبة على المحاكي بعد الإصلاح نجح ضمن المجموعة النهائية ذات 11 حالة في 2026-09-28. عدم توفر المصغرة نفسها يبقى احتمالًا مصنفًا، ولا يعني فساد الأصل.
- **المواضع:** [ThumbnailCache.load](../lib/features/library/presentation/providers/thumbnail_cache.dart)، [_IdThumbnailState._resolve](../lib/features/library/presentation/widgets/id_thumbnail.dart).
- **السبب والأثر:** Photos قد يقبل ملفًا ثم يرفض توليد صورة مصغرة له. `thumbnailDataWithSize` ترمي Future بخطأ `Failed to convert … to 0 format`، ولا يلتقطها cache؛ الاستدعاء من initState غير منتظر فيتسرب PlatformException خارج حدود الواجهة. ظهر بعد حفظ صيغ الاختبار وفتح المكتبة. لم يثبت بعد أي صيغة سببت الطلب الأصلي؛ لا تعمم فشل كل AVIF أو WebP.
- **الدليل:** `preservation-ios-simulator-second.log`، stack عند `ThumbnailCache.load` ثم `ConcurrencyLimiter.run` ثم `IdThumbnail._resolve`. ليس فقدًا مثبتًا في الملف الأصلي؛ اختبار AVIF للحفظ/الاسترجاع نجح بعد تصحيح فاحص ألفا.
- **الإصلاح والتحقق:** قبل الإصلاح فشلت 3 حالات (رفض متأخر وnull وبايتات فارغة) ونجح الإلغاء؛ بعده نجحت 6 حالات، بما فيها إعادة المحاولة وواجهة العنصر. سجل التحذير `gallery.thumbnail.exception/unavailable/emptyOutput` لا يحتفظ بمعرف الأصل أو بياناته.
- **معيار الإغلاق:** فشل native المتأخر لا يترك استثناء واجهة غير معالج؛ placeholder الموجود مع تشخيص مصنف في release، دون حفظ فشل في الكاش ودون منع إعادة المحاولة. اختبارات نجاح/رفض/ناتج فارغ/إلغاء، ثم إعادة المحاكي. دعم توليد كل المصغرات على النظام قضية قدرات مستقلة؛ لا تفك الأصل كاملًا تلقائيًا كحل مكلف.

### DEV-01 · P2 · مجال جودة AVIF العتادي واتجاهه مفترضان

- **الحالة:** تعارض مع عقد API مثبت؛ أثره وحجمه على الهواتف غير مقاسين.
- **الموضع:** `encodeAv1` في [AvifHwEncoder.kt](../android/app/src/main/kotlin/app/naqaa/hayn/AvifHwEncoder.kt).
- **السبب:** تحويل جودة 0–100 إلى KEY_QUALITY متناقص 63–10، دون `getQualityRange()`، كأنه quantizer. [Android](https://developer.android.com/reference/android/media/MediaCodecInfo.EncoderCapabilities#getQualityRange()) يعرّف المجال بحسب التنفيذ، والأعلى عمومًا أجود.
- **معيار الإغلاق:** المجال الفعلي وتحقق CQ/VBR وفشل المحرك، ثم قياس جهاز يدعم AV1 العتادي. لا تنسب اختلاف أحجام الجهازين كله لهذه النقطة ولا تعد بتساوي أحجام «جودة 80».

### DEV-02 · P2 · القدرات المقدرة ليست فحصًا للمحرك الفعلي

- **الحالة:** فجوة مؤكدة؛ ضبط قياسات الأداء والحجم لم يكتمل.
- **المواضع:** [FormatCapabilities](../lib/core/capabilities/format_capabilities.dart)، ملفات `lib/core/capabilities/`، [NativeAvifEncoder](../lib/features/image_ops/data/native_avif_encoder.dart).
- **السبب:** أجزاء من القدرات تعتمد المنصة أو قيمًا مؤقتة؛ سجل backend الحالي لا يشمل الاسم الأصلي/الإصدار/subsampling/rate-control. AVIF له hardware وravif وflutter_avif؛ المسار يغير الحجم والسرعة. assembly معطل وفك AVIF محدود الخيوط؛ أثر ذلك غير مقاس.
- **معيار الإغلاق:** نفس bytes/hash للمصدر، المحرك وإصداره وإعداداته، الأبعاد/العمق/alpha/اللون، الزمن/الذاكرة/الحجم، وجودة بصرية متقاربة. أي مقارنة backend مستقبلية تجربة محدودة داخل DarkLib؛ لا قرار بإزالة المكتبة.

## البناء والتغليف

### BUILD-01 · P2 · CI لا يطابق البيئة ولا يختبر الجسر الحقيقي

- **الحالة:** مفتوح.
- **المواضع:** [ci.yml](../.github/workflows/ci.yml)، [اختبار المضيف](../test_native/darklib_host_test.dart).
- **السبب:** CI يثبت Flutter 3.44.0 مقابل 3.47.2 محليًا، pub get بلا enforce-lockfile وCargo بلا locked؛ اختبارات Flutter العادية تسمح بغياب native. لا بناء Android/iOS في CI.
- **معيار الإغلاق:** تثبيت إصدارات منسجمة دون ترقية جانبية؛ بناء وتحميل DarkLib في اختبار منفصل لا يتخطى الفشل؛ تحقق تغليف المنصتين والـABIs المدعومة. أعداد unit لا تثبت التكامل.

### BUILD-02 · P2 · MSRV المعلن غير صحيح مع القفل

- **الحالة:** مفتوح، مثبت: Rust 1.79 معلن و`image 0.25.10` يتطلب 1.88.
- **المواضع:** [Cargo.toml](../native/darklib/Cargo.toml)، [Cargo.lock](../native/darklib/Cargo.lock)، [BUILD.md](../native/darklib/docs/BUILD.md)، [SUPPORT.md](../native/darklib/docs/SUPPORT.md).
- **معيار الإغلاق:** اعتماد حد مختبر مع القفل أو قفل متوافق؛ تحقق MSRV فعلًا وتحديث جميع الوثائق. لا تسمِّ 1.79 مدعومًا لمجرد وجوده في manifest.

### BUILD-03 · P2 · فصل APK يتعارض مع abiFilters وتجميع غير لازم

- **الحالة:** تعارض split-per-abi أُعيد سابقًا ولم يتغير الملف؛ سجل Android الأخير `preservation-ios-android-retry.log` يؤكد تجميع i686 وتكرار x64 رغم طلب arm64/x64 فقط.
- **المواضع:** [app/build.gradle.kts](../android/app/build.gradle.kts)، [cargokit/plugin.gradle](../rust_builder/cargokit/gradle/plugin.gradle).
- **السبب:** filters ثابتة arm64/x64 مع إعداد splits، وdebug يضيف x86/x64 بلا إزالة التكرار. دعم Rust لمعماريات معينة لا يثبت محتويات APK من مكتبات plugins الأخرى.
- **معيار الإغلاق:** اختبار universal وsplit للمقاصد المدعومة، فحص libs المعبأة فعلًا، وإزالة ABI غير مشحون/التكرار. لا تستخدم nightly لحل ABI غير مطلوب.

### BUILD-04 · P2 · قياس release قديم والتوقيع للنشر غير مجهز

- **الحالة:** يحتاج إعادة قياس بعد FFmpeg 3.6.2؛ ليس مانع debug.
- **المواضع:** [pubspec.yaml](../pubspec.yaml)، [app/build.gradle.kts](../android/app/build.gradle.kts)، [قياسات الاستقرار](12-STABILIZATION.md).
- **التفصيل:** baseline APK 98.88MiB يسبق تحديث FFmpeg؛ لا يعاد عرضه كحجم حالي. release Android يستخدم debug signing حاليًا؛ يلزم إعداد نشر منفصل عند طلب النشر. تحذيرات ثلاث plugins عن SPM/CocoaPods ليست فشل البناء الحالي.
- **معيار الإغلاق:** قياس package/installed لكل ABI وإصدار، فصلها عن build/cache؛ لا نشر أو تغيير مفاتيح بلا طلب.

### BUILD-05 · P2 · تحذيرات توافق أدوات البناء المستقبلية

- **الحالة:** ظهرت في بناء الدفعة الناجح، وليست مانعًا حاليًا.
- **المواضع:** [gradle-wrapper.properties](../android/gradle/wrapper/gradle-wrapper.properties)، [settings.gradle.kts](../android/settings.gradle.kts)، [pubspec.yaml](../pubspec.yaml)، وlogs `preservation-android-build.log`/`preservation-ios-build.log`.
- **التفصيل:** Flutter يحذر من دعم قادم يتجاوز Gradle 8.14.3 وAGP 8.11.1 وKotlin 2.2.20؛ تحذير SDK XML 3/4 أيضًا. ثلاث plugins لا تدعم SPM بعد. لم نرفع اعتماديات أو نتجاوز فحص التوافق ضمن تصحيح الصور.
- **معيار الإغلاق:** دفعة ترقية مستقلة بإصدارات متوافقة وبناء الهاتفين، لا تغيير أرقام تلقائيًا لمجرد إزالة التحذير.

### BUILD-06 · P2 · خدمة Gradle قديمة لا تستجيب

- **الحالة:** تعافى البناء في 2026-09-27 بعد إنهاء daemon غير المستجيب وإعادة المحاولة بجلسة مؤقتة؛ السبب الجذري لتعليق JVM غير مثبت.
- **الموضع:** daemon محلي Gradle 8.14.3، وسجلات `/Volumes/CUSU/Development/logs/preservation-android-wait.txt` و`preservation-old-gradle.txt`.
- **الدليل والسبب المباشر:** بقي عميل البناء ينتظر `DaemonClient.executeBuild → SocketConnection.receive` أكثر من 12 دقيقة. الاتصال الوحيد بالخدمة كان عميل هذه الجولة، وسجل daemon القديم توقف عند مرحلة idle قبل ساعات، وطلب jcmd للخدمة لم يستجب خلال 10.5 ثانية. السبب الجذري لتعطل JVM غير محدد؛ لا تنسبه إلى المكتبة أو نقل التخزين بلا قياس.
- **الإجراء والدليل:** لم يستجب SIGTERM، وأنهي PID المحدد قسرًا، ثم أوقفت محاولة البناء المنتظرة (exit 143). نجحت إعادة Android debug للهدفين arm64/x64 في 334.3 ثانية باستخدام `GRADLE_OPTS=-Dorg.gradle.daemon=false` لتلك المحاولة فقط؛ `preservation-ios-android-retry.log`. نجاح البناء يثبت التعافي فقط. لا تحذف الكاشات أو تعطل daemon على مستوى الجهاز كحل افتراضي.

- **دليل لاحق وإعداد وقائي (2026-09-29):** فصل القرص ترك خدمة أخرى تستهلك 515–551% CPU، بـ886 مقبض ملف ملغى؛ أنهيناها وتراجع الضغط. هذا دليل على فقد ملفات العملية، ولا يثبت بأثر رجعي سبب التعليق الأول. بموافقة المستخدم فُعّل `org.gradle.daemon=false` في إعداد المستخدم والطرفية، ومهلة خمول 60000ms لخدمات Tooling API. نجح اختبار Hayn help وخروج خدمته، وتجربة Tooling API وخروجها تلقائيًا بعد نحو 68 ثانية خمول. التفاصيل والتراجع والسجلات في [بيئة التطوير](13-DEVELOPMENT.md). رُصد استثناء تنظيف سجل daemon عند shutdown رغم نجاح المهمتين وانتهاء العمليتين؛ السبب الداخلي غير محقق.

## التوثيق والمنتج

### DOC-01 · P3 · التاريخ القديم يمكن أن يُقرأ كحالة حالية

- **الحالة:** أضيف هذا السجل وملخص حالي إلى docs/10 وdocs/12 وdocs/13، مع حفظ المقاطع التاريخية وتسميتها. تستمر مراجعة الادعاءات القديمة عند لمس المسار.
- **المواضع:** [12-STABILIZATION](12-STABILIZATION.md)، [13-DEVELOPMENT](13-DEVELOPMENT.md)، [BUILD.md](../native/darklib/docs/BUILD.md)، والخطط `docs/01` إلى `docs/09`.
- **التفصيل:** مقاطع تقول إن إصلاحات الدفعة الأولى غير ملتزم بها أو iOS متعذر؛ لاحقًا التزمت في `d514063` وجهز المحاكي واعتمد iOS 15. README حُدّث في `ddc06a8`؛ لا تكرر حكم README القديم. الخطط القديمة ليست دليل اكتمال. منذ 2026-09-28 لا تسجّل الوثائق حالة Git أصلًا؛ Git يديره المستخدم، والقاعدة في [workflow.md](../.claude/rules/workflow.md).
- **معيار الإغلاق:** حالة حالية بارزة مع تاريخ كل baseline؛ روابط هذا السجل من Claude؛ كل إصلاح يحدّث سجله والاختبار/القيد بدل دفنها في محادثة.

### PROD-01 · P3 · شاشات لا تزال خططًا أو موصولة جزئيًا

- **الحالة:** نقص معروف خارج دفعة المكتبة؛ يلزم إعادة فحص كل flow قبل إصدار.
- **المواضع:** [قص الفيديو](../lib/features/video_ops/presentation/trim_video_screen.dart)، [تحرير الفيديو](../lib/features/video_ops/presentation/video_editor_screen.dart)، [crop_video_screen](../lib/features/video_ops/presentation/crop_video_screen.dart)، [التحريك من صور](../lib/features/animated/presentation/animate_from_photos_screen.dart)، [فصل الصوت](../lib/features/audio/presentation/separate_audio_screen.dart).
- **المطلوب:** لا تعرض نجاحًا لعملية غير منفذة، واتساق أدوات Coming Soon مع المداخل المنفذة. لا توسع DarkLib إلى محركات فيديو/صوت لإغلاق هذا البند؛ حدودها موثقة.

### PROD-02 · P3 · نص تحذير الشفافية لا يطابق السلوك

- **الحالة (2026-09-29):** أُصلح بقرار المستخدم. JPEG لصورة شفافة أو مجهولة الشفافية يُنفذ: `AlphaFlatten` يدمجها على الأبيض قبل أي محرك (DarkLib أو ImageIO أو الإضافة لقراءة ما لا يقرؤه package:image)، ثم تُنقل البيانات الوصفية من الأصل عند طلبها، ويسجل `alphaFlattened`. أزيل تحذير الشفافية و`requiresAlphaFlatten`، وحل محلهما نص خفيف على الصيغة من `ImageFormatPolicy.losses` يظهر فقط حين تحمل الأصلية ما ستفقده الصيغة. اختبارات: `test/alpha_flatten_test.dart` (دمج جزئي، 16 بت، palette)، وحالتان في `preservation_regression_test.dart`، و`losses` في `image_format_policy_test.dart`، واختبار المحاكي يقيس بكسل JPEG الناتج على iOS. لم يُختبر على Android، ولا HEIC شفاف على Android.
- **المواضع:** `compressAlphaFlattenWarning` في [app_en.arb](../lib/app/l10n/app_en.arb) و[app_ar.arb](../lib/app/l10n/app_ar.arb)، `_flattensAlpha` في [compress_screen.dart](../lib/features/image_ops/presentation/compress_screen.dart)، بداية [ImageEncoder.encode](../lib/features/image_ops/data/image_encoder.dart).
- **السبب والأثر:** النص يقول إن الصورة الشفافة ستُحفظ بصيغة تحفظ الشفافية بدل JPEG. منذ `910a281` الصيغة المحددة لا تتغير، وJPEG مع شفافية موجودة أو مجهولة يفشل. فالنص يعد بما لا يحدث، وهو أيضًا تحذير تقني من النوع الذي منعته قاعدة النصوص (flutter.md، 2026-09-28).
- **معيار الإغلاق:** تحقق؛ يبقى تحقق Android. نقل التاريخ مع `keepOriginalTime=false` عبر `transplant_metadata` لا يحذف تاريخ EXIF (IMG-12).
- **أُغلق معه:** `compressBitDepthDesc` كان يقول «HDR is kept either way»؛ صار «Colour precision per channel» / «دقة الألوان لكل قناة».

## أمور أُصلحت أو استُبعدت — لا تُفتح من جديد بلا دليل

| الملاحظة | الحالة والدليل | المتبقي المنفصل |
|---|---|---|
| Future مرفوض يغادر try دون await | أُصلح في `d514063`؛ `test/stability_regression_test.dart` | سياسات الإذن في IMG-11 |
| إغلاق stream يُعلن النجاح دون ناتج، وفشل الفيديو/الدفعة يختفي | TaskEvent وIncompleteBatch ونتيجة نهائية واحدة في `d514063`؛ اختبارات task/batch/lifecycle | RUN-02/03/04 |
| cancel ينتظر subscription قبل إيقاف المنتج | أُصلح في `d514063` مع اختبار يمنع الرجوع | إلغاء native أثناء الترميز غير منفذ |
| تشخيص fallback debug فقط أو غير موجود | سجل 100 حدث في release وtrace للعملية وbackend في النتيجة؛ `d514063` | لا يثبت HDR/اللون، IMG-05 |
| غياب Android SDK / iOS runtime وتعذر البناء | عولج؛ doctor بلا ملاحظات وبناء المحاكي وiOS release وAndroid مسجل بعد FFmpeg 3.6.2 | آخر إعادة بناء بعد تصحيح الجسر نجحت للمنصتين |
| نقل أدوات التطوير يستهلك الداخلي | معظم الأدوات والكاشات على `/Volumes/CUSU/Development`؛ التفاصيل في docs/13 | runtime/CoreSimulator تبقى داخلية: خدمة النظام رفضت النقل بصلاحياتها؛ لا تعيد نقلها بلا حل مثبت |
| اشتباه عدم تزامن التبويب أثناء انتقال سريع | اختبار إعادة الإنتاج في المراجعة مرّ؛ **ليس عيبًا مثبتًا** | لا تذكره كخلل ولا تصلحه افتراضيًا |
| الاستبدال الجراحي | أزيل عمدًا بسبب قيود ومشاكل سابقة | ليس بندًا مطلوبًا لإعادة التنفيذ |

## الأدلة وكيف يكمل المراجع التالي

baseline المراجعة التاريخي: **158 Flutter + 74 Rust**، والتحليل وdoctor ناجحان عند `ddc06a8`؛ سجلاته `/Volumes/CUSU/Development/logs/review-20260927-*`. تلتها دفعة `910a281` بنتائج **174 Flutter + 79 Rust + 3 host-native**. سجلات الأحمر المعتمدة لهذه الدفعة: `preservation-red-flutter.log` و`preservation-red-rust-corrected.log` في المجلد نفسه (5 حالات فشلت في كل مجموعة).

دفعة المحاكي والمصغرات (2026-09-28): **180 Flutter + 11 على محاكي iOS**. آخر تحقق محلي بعد IMG-05 الجزء الأول (2026-09-28): **189 Flutter و79+7 Rust و5 host-native و11 على المحاكي**، والتحليل وfmt/clippy والقارئ المستقل وبناء Android debug وiOS release دون توقيع ناجحة. تفاصيل الجولات في [15-IOS-TESTING](15-IOS-TESTING.md) والنتائج في آخر [12-STABILIZATION](12-STABILIZATION.md).

الفحص الأول محفوظ خارجيًا في `/Volumes/CUSU/Development/verification/Hayn-audit-20260925/`: `results/` للسجلات والعينات، و`bedrock/native/darklib/tests/audit_regressions.rs` لحالات اللون/MPF/grid/الاتجاه القديمة. هذه نسخة قديمة للفحص فقط، لا شجرة عمل تُنسخ على المشروع. التقرير التاريخي الكامل موجود محليًا في مشروع Codex بعنوان `Hayn-review-2026-09-25.md`؛ جميع المشاكل القابلة للمتابعة منه ملخصة هنا فلا يعتمد التسليم على توفره.

1. اقرأ Git وCLAUDE ثم هذه الوثيقة وdocs/10 وdocs/11.
2. تحقق من النتائج الموثقة للدفعة ومن أي تغيير أحدث قبل فتح IMG-02/06/07/08/09. لا تعد الأخضر على mocks إثباتًا لـnative.
3. Dart: format + analyze + جميع `flutter test --no-pub`. Rust: fmt + clippy all-targets locked + test locked. اختبار `test_native` يحمّل مكتبة مبنية حقيقية.
4. لأن Swift/Rust تأثرا، أعد بناء Android للـABIs المدعومة وiOS بلا توقيع. لا تثبت على الهاتف ضمن التحقق دون طلب.
5. حدّث هذا السجل وdocs/12 بنتائج الفحوص وحدودها، ثم خذ أقرب عيب P1 قابل للإثبات في دفعة محدودة. نجاح الحماية الحالية لا يغلق عقد الحفظ الشامل.
