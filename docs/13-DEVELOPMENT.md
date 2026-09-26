# 13 — بيئة التطوير والتخزين الخارجي

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

بقي `~/.cargo` الصغير نسبيًا وملفات إعداد الطرفية داخليًا. Xcode والمتصفحات وبياناتها لم تُنقل. مجلدا build وRust target داخل المشروع موجودان أصلًا على القرص الخارجي.

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
