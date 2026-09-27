# عينات انحدار الحفظ

نُزلت في 2026-09-27 من [corpus libavif الرسمي](https://github.com/AOMediaCodec/libavif/tree/main/tests/data)، دون تعديل. الملفات الأصلية عامة وليست من مكتبة المستخدم. الرخصة «same as libavif» بحسب [وصف العينات](https://github.com/AOMediaCodec/libavif/blob/main/tests/data/README.md)؛ نسخة الرخصة الكاملة في [LICENSE.libavif](LICENSE.libavif).

- `seine_hdr_rec2020.avif`: HDR مباشر Rec.2020/PQ. استخدم لاختبار رفض المرور عبر RGBA8 بلا tone mapping.
- `seine_sdr_gainmap_srgb.avif`: أساس SDR وخريطة ISO. استخدم لاختبار رفض إسقاط الخريطة مع تغيير الهدف/التصغير/إزالة البيانات أو graph غير قابل للقراءة.

| الملف | بايت | SHA-256 |
|---|---:|---|
| `seine_hdr_rec2020.avif` | 87071 | `fd002bd4d51152b1cac533046ebfbc710aca7aaa519c0e7dc59d668aa12313ac` |
| `seine_sdr_gainmap_srgb.avif` | 129773 | `e0ebdb2f1f44c7d901e6b5f817eb2520eace344624cab0d57aaa929d05d6d971` |

`preservation.rs` ينشئ مشتقين في الذاكرة فقط: تعطيل اسم علاقة dimg، وتغيير أول خانة IFD0 في EXIF إلى Orientation=6 دون تحريك offsets. كلاهما اختبار رفض، وليس صورة مرجعية صحيحة للعرض. المصدران أعلاه من كاتب مستقل؛ اختبار القارئ المستقل ImageIO في `test_native/inspect_preservation.swift` من جذر التطبيق. اختبارات الرفض لا تثبت جودة إعادة بناء HDR، ولا تغطي Apple HEIC أو HLG أو grids ذات alpha.

مسار التنزيل لكل ملف: `https://raw.githubusercontent.com/AOMediaCodec/libavif/main/tests/data/<filename>`. تضمن البصمات هوية النسخ المستخدمة إذا تغير الفرع البعيد؛ الاختبارات تعمل أوفلاين بالملفات المودعة. ليست ضمن assets ولا تُشحن داخل التطبيق.
