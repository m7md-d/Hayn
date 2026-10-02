# عينات انحدار الحفظ

عينات عامة، ليست من مكتبة المستخدم، وليست ضمن assets ولا تُشحن داخل التطبيق. الاختبارات تعمل أوفلاين بالملفات المودعة، والبصمات تثبت هويتها إذا تغير المصدر البعيد.

## من corpus libavif

نُزلت دون تعديل من [corpus libavif الرسمي](https://github.com/AOMediaCodec/libavif/tree/main/tests/data): الأولان في 2026-09-27، والبقية في 2026-09-30. رخصة كل ملف «same as libavif» بحسب [وصف العينات](https://github.com/AOMediaCodec/libavif/blob/main/tests/data/README.md)؛ نسخة الرخصة الكاملة في [LICENSE.libavif](LICENSE.libavif). مسار التنزيل: `https://raw.githubusercontent.com/AOMediaCodec/libavif/main/tests/data/<filename>`.

الخصائص أدناه كما قرأها ImageIO على الماك، لا كما يوحي الاسم.

| الملف | ما فيه | البند |
|---|---|---|
| `seine_hdr_rec2020.avif` | HDR مباشر Rec.2100 PQ، 10 بت | IMG-03/05 |
| `seine_sdr_gainmap_srgb.avif` | أساس SDR وخريطة ISO | IMG-10 |
| `seine_hdr_gainmap_srgb.avif` | أساس HDR (BT.709 PQ) وخريطة ISO | IMG-10، T-12 |
| `colors_wcg_hdr_rec2020.avif` | PQ بألوان خارج sRGB | IMG-03 |
| `seine_sdr_gainmap_srgb.jpg` | JPEG بخريطة ISO وMPF | IMG-06، T-09 |
| `apple_gainmap_new.jpg`، `apple_gainmap_old.jpg` | JPEG بخريطة Apple، وICC Display P3 وحده | IMG-04، IMG-08 |
| `color_grid_alpha_nogrid.avif` | لون بشبكة وألفا بلا شبكة | IMG-02 |
| `color_grid_alpha_grid_gainmap_nogrid.avif` | لون وألفا بشبكة، وخريطة ISO بلا شبكة، 10 بت | IMG-02، IMG-10 |
| `sofa_grid1x5_420.avif` | شبكة 1×5 | IMG-02 |
| `abc_color_irot_alpha_irot.avif` | ألفا واتجاه `irot` (ImageIO يقرأ 8) | IMG-07 |
| `paris_icc_exif_xmp.avif`، `paris_icc_exif_xmp.png` | ICC ‏sRGB مع EXIF وXMP | IMG-08 |

## من مرمّز Apple

`test_native/make_platform_fixtures.swift` يكتبها بـImageIO على الماك، من صور libavif أعلاه (والرخصة رخصة المصدر) أو من محتوى اصطناعي، فالكاتب مستقل عن DarkLib. التوليد ثابت: إعادة التشغيل تعطي البصمات نفسها (macOS 15، 2026-09-30).

| الملف | ما فيه | المصدر | البند |
|---|---|---|---|
| `apple_heic_10bit_p3.heic` | HEIC ‏SDR بعمق 10، Display P3 | أساس `seine_sdr_gainmap_srgb.avif` | IMG-13 |
| `apple_heic_hlg.heic` | HEIC ‏HLG بعمق 10 (Rec.2100) | `seine_hdr_rec2020.avif` محولًا بـCoreGraphics | IMG-03/05/14 |
| `apple_heic_alpha.heic` | HEIC بألفا، 64×48: اللون (80,120,160) بألفا 64 ومربع أسود معتم في الوسط، فيميّز ألفا مقروءة من ألفا متجاهلة | اصطناعي، بلا رخصة | IMG-15، PROD-02 |
| `apple_heic_alpha_grid.heic` | الألفا نفسها بحجم 1280×960 (×20)، فيقسّمها ImageIO شبكة. ومعها مربع شفاف تمامًا (x 1090–1190، y 100–200 من الأسفل) بعيد عن حدود البلاطات، فيظهر خطأ موضع البلاطة ثقبًا منقولًا. والمربع الأسود (x 480–800، y 320–640) يعبر حدود 512 عمدًا | اصطناعي، بلا رخصة | IMG-15 (M-04) |
| `apple_png_p3_icc.png` | PNG بـICC ‏Display P3، ومعه `cICP` كتبه ImageIO | أساس `apple_gainmap_new.jpg` | IMG-08 |

## ألفا HEIC مفكوكة بـFFmpeg

`apple_heic_alpha.gray`: طبقة الألفا في `apple_heic_alpha.heic` مفكوكة بمفكك HEVC في FFmpeg 7.1.3 على لينكس، مفكك مستقل عن DarkLib (2026-10-02). 64×48 بايتًا رماديًا بالمدى الكامل، صف بعد صف: 64 حيث الصورة شبه شفافة و255 في المربع المعتم. الأمر: استخرج تيار Annex-B من `hvcC` والعنصر 2، ثم `ffmpeg -f hevc -i alpha.hevc -frames:v 1 -f rawvideo -pix_fmt gray alpha.gray`. وفك FFmpeg المشحون مع التطبيق على S25 Edge أعطى القيم نفسها. يستعمله `tests/heif_alpha.rs` (IMG-15).

## بنية `apple_heic_alpha_grid.heic`

فُحصت بقارئ صناديق مستقل (macOS 15.6، 2026-10-02، ImageIO من نظام الماك). ما كتبه ImageIO:

- **الأساسي:** العنصر 7 من النوع `grid`، فيه ستة عناصر `hvc1` (العناصر 1 إلى 6) بعلاقة `dimg`: ثلاثة أعمدة وصفان، كل بلاطة 512×512 (`ispe`)، والأبعاد الكلية 1280×960. وصف الشبكة في `idat`: الإصدار 0، والصفوف−1 = 1، والأعمدة−1 = 2.
- **الألفا:** العنصر 14 من النوع `grid` أيضًا، وعلاقة `auxl` منه إلى العنصر 7، وخاصية `auxC` بالمعرّف `urn:mpeg:hevc:2015:auxid:1`. بلاطاته ستة عناصر `hvc1` (8 إلى 13) بعلاقة `dimg`، بالأبعاد نفسها. فالألفا **شبكة بحدودها نفسها لا ألفا لكل بلاطة**.
- **خصائص:** `irot` بزاوية 0 على الأساسي والألفا، و`colr` و`clli` على بلاطات الأساسي. الملف في `mdat` بعد `meta`، وحجمه 3820 بايتًا.
- **قراءة ImageIO للقيم:** اللون (79,119,159) بألفا 64 في أي موضع، ومربع أسود بألفا 255 يعبر حدود البلاطات، وثقب بألفا 0 في موضعه بدقة بكسل (الحد من الداخل ألفا 0، ومن الخارج 64). `sips -g hasAlpha` يعطي yes.
- **الحد:** لم يُبحث عن أصغر حجم يقسّمه ImageIO، فالسجل هو ما يكتبه ImageIO عند 1280×960 وبلاطة 512 بجودة 0.95.

## من HeifWriter على Android

`android_heifwriter_grid.heic`: ناتج `HeifWriter` (عبر `flutter_image_compress`) على Galaxy S25 Edge، بمرمّز `c2.qti.heic.encoder`، من PNG ‏16×12 بلون (80,120,160) (اختبار الهاتف «heic: primary Android encode decodes back»، 2026-10-02). كاتب مستقل عن DarkLib، وشكله ما يكتبه `MediaMuxer`: `mdat` قبل `meta` بحجم 64 بت، وشبكة 1×1 من بلاطة 512 وواصفها في `idat` (طريقة البناء 1)، وبلا `colr` ولا EXIF. يستعمله `tests/heif_inject.rs` (RUN-01، الخطوة 5)، ويتحقق `test_native/check_heif_inject.py` من الناتج بـlibheif.

## من libheif

`libheif_p3_icc.heic` و`libheif_p3_nclx.heic`: صورة 64×48 بأربعة أرباع (أحمر وأخضر وأزرق وأصفر من أعلى اليسار، بقيم P3 ‏(220,40,40) و(40,200,60) و(40,60,220) و(230,210,40)). كتبها libheif 1.23.4 عبر pillow-heif بجودة 100 (2026-10-02)، والأول بملف Display P3 من Apple (من `apple_png_p3_icc.png`)، والثاني بـ`nclx` (12/13/6، مدى كامل) بلا ICC. ألوانها في sRGB كما يحولها LittleCMS بملف Apple عند مراكز الأرباع: (240,0,23) و(0,204,12) و(34,61,228) و(235,209,0). يستعملها اختبار الهاتف لـIMG-21 (العرض والقص)، واختبار الجسر الحقيقي.

## WebP من libwebp عبر Pillow

`test_native/make_webp_fixtures.py` يكتبها بـPillow 12.3.0 (libwebp 1.6.0)، كاتب مستقل عن DarkLib. المحتوى اصطناعي بلا رخصة: تدرج 64×48، والشفافة نصفها الأيسر بألفا 64. التوليد ثابت (أعيد فأعطى البايتات نفسها، 2026-09-30). ImageIO يرى الألفا في الشفافتين وحدهما.

| الملف | القطع | البند |
|---|---|---|
| `pillow_webp_lossy_opaque.webp` | `VP8 ` وحدها | IMG-16 |
| `pillow_webp_lossy_alpha.webp` | `VP8X`، `ALPH`، `VP8 ` | IMG-16 |
| `pillow_webp_lossless_opaque.webp` | `VP8L`، بت ألفا 0 | IMG-16 |
| `pillow_webp_lossless_alpha.webp` | `VP8L`، بت ألفا 1 | IMG-16 |

P3 بـICC وحده بلا وسم لون آخر موجود في `apple_gainmap_*.jpg`؛ JPEG لا يحمل cICP.

## البصمات

| الملف | بايت | SHA-256 |
|---|---:|---|
| `abc_color_irot_alpha_irot.avif` | 10597 | `b371cc88244a873131e4d10ff9363d71ce4f41cf333bd4a491b38d970d9abd3b` |
| `color_grid_alpha_grid_gainmap_nogrid.avif` | 2870 | `c424c43fe4bab3b8ef37b86c0bab3851b850b94e5d46b9fae979586dae45de0a` |
| `color_grid_alpha_nogrid.avif` | 2373 | `bae56368b348b1d847e2bfb662522599f0c63dfe62fb68826c9e42a300ff405d` |
| `colors_wcg_hdr_rec2020.avif` | 20613 | `848d4e3ad357e73c9d7183146ab65ef2e5e4e482183d3617fcb7e31804a54110` |
| `paris_icc_exif_xmp.avif` | 21132 | `961bc38b61e60b7651fa20efa24269ae2f35e4958822a81c908c9bbf9b3f66e1` |
| `seine_hdr_gainmap_srgb.avif` | 122961 | `9bf9c6a7606951de07e4079cd63c2cfe379d95139cd99ab9142d8a6ee22d28c7` |
| `seine_hdr_rec2020.avif` | 87071 | `fd002bd4d51152b1cac533046ebfbc710aca7aaa519c0e7dc59d668aa12313ac` |
| `seine_sdr_gainmap_srgb.avif` | 129773 | `e0ebdb2f1f44c7d901e6b5f817eb2520eace344624cab0d57aaa929d05d6d971` |
| `sofa_grid1x5_420.avif` | 25409 | `c9e04ff9d90d7093454750fa33b7543ee5479e0cfb151e2c3d2ce6a16c1651c1` |
| `apple_gainmap_new.jpg` | 50824 | `492a94bd0636bcf15b3f560c68142a7783936c1597e78b0d0461d8be7fddc078` |
| `apple_gainmap_old.jpg` | 50742 | `2e4310a0dd37a98678e057e25d936bbc4f936bb6fe17380c0ce99e58ecaa603b` |
| `seine_sdr_gainmap_srgb.jpg` | 142972 | `1aaf0a1afa91a485c13e4ad696a3da1fe1ddd2675417e3812a23a9d13f765262` |
| `paris_icc_exif_xmp.png` | 153217 | `308bb51c3338ed9519cdaaa79186b934a21d1748d94120ed0348eb4f193d0988` |
| `apple_png_p3_icc.png` | 165136 | `d74a964e751c39ba180f9096fe772047ec5ecd351cf6edc0d89afa6679e19db7` |
| `apple_heic_10bit_p3.heic` | 77952 | `1b73a555c824ff7a8cc99d7ca14d9d3f53fbb4b3587f755c59a177ae8bda15b4` |
| `apple_heic_alpha.heic` | 830 | `2eaff577ba577254db2b4110c4f86e3dab46e4af777090229138f1beb0bb18ca` |
| `apple_heic_alpha_grid.heic` | 3820 | `137371a1dd16e016e8d6ddb2783b38ce5038ed1cbb0bd422e2077a78ae50a541` |
| `apple_heic_alpha.gray` | 3072 | `2b8c6694d3d953e5a08f0ffa3c092fde12b7b6417678580f2cdf59bd26beb535` |
| `apple_heic_hlg.heic` | 73083 | `d699edef45fa92d93331b3de94b8285372c89681a58a1a857d254175cbebafd6` |
| `libheif_p3_icc.heic` | 1201 | `4459f6e15e55ee2c409c16ae993e0e93321d69c739d25b8ab8b78661a25749f3` |
| `libheif_p3_nclx.heic` | 672 | `da44fa93a6b9d8b9643a459a89b4ec1cf5a34328f66b02edce9a465006bdcb8e` |
| `android_heifwriter_grid.heic` | 552 | `3df650c04f088cecdbedfb853c4f8a450158c222a9566a1845e7c690fa8fa9d1` |
| `pillow_webp_lossless_alpha.webp` | 72 | `ea86ca4d8c1020b91f0ad3db4784a2cfdc617d51e16f6de6638c6c9d7b5b99ca` |
| `pillow_webp_lossless_opaque.webp` | 60 | `08deddec4ba383d688bcf571e20faada915e99f7e4b4bd1b4abd4281375b62f9` |
| `pillow_webp_lossy_alpha.webp` | 314 | `d223a2fdcd9976431443eba88252fc5134e564262fff2b8872e9c4a5e2e809eb` |
| `pillow_webp_lossy_opaque.webp` | 266 | `beafd7b54b8f03cf37dbc5b1800f2d2a9482a6df6041e8001a64d933bebf21c4` |

## الاستخدام الحالي

`preservation.rs` يستخدم الأولين، وينشئ منهما مشتقين في الذاكرة فقط: تعطيل اسم علاقة dimg، وتغيير أول خانة IFD0 في EXIF إلى Orientation=6 دون تحريك offsets. كلاهما اختبار رفض، لا صورة مرجعية للعرض. القارئ المستقل في `test_native/inspect_preservation.swift`. اختبار الهاتف (`integration_test/android_device_test.dart`) يستخدم عينات HEIC الثلاث و`seine_sdr_gainmap_srgb.jpg` (Ultra HDR: XMP `hdrgm` وMPF). `tests/jpeg_mpf_strip.rs` ينظف عينات JPEG الثلاث ذات MPF، و`test_native/check_jpeg_mpf.py` يتحقق من الناتج بقارئ MPF مستقل (IMG-06). `tests/avif_alpha.rs` يفك ألفا عينات AVIF الثلاث الشفافة، و`test_native/compare_avif_alpha.swift` يقارنها بـImageIO وffmpeg (IMG-02). `tests/alpha_facts.rs` يقرأ ألفا كل العينات من الحاوية ويقارنها بما يراه ImageIO. `color_grid_alpha_nogrid.avif` هو الاستثناء: ImageIO لا يرى ألفا البلاطات فيه، والمواصفة تجيزها، ووصف libavif يعدّه ملفًا بألفا (IMG-02). بقية العينات مُحضَّرة للبنود المذكورة ولم تدخل اختبارًا بعد؛ وجودها هنا لا يعني أن بندها مختبر. لا عينة HLG من كاتب ثالث مستقل عن Apple بعد.
