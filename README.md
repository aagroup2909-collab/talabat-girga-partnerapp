# تطبيق الشركاء — طلبات جرجا

Partner mobile app for Talabat Girga (Flutter): one app for drivers and merchants; `user.role` decides the screens.

- Customer app: https://github.com/aagroup2909-collab/talabat-girga-customerapp
- Backend and API reference: https://github.com/aagroup2909-collab/talabat-girga-backend — see `backend/docs/API.md` there.
- Production API: `https://talabat.ahgroup.online/api/v1` (the app's default)
- Run: `flutter pub get`, then the commands under "التشغيل" below.
- No secrets in this repo: keystores, `key.properties` and Firebase files are git-ignored; ask the project owner for them.

تطبيق واحد للسائقين والتجار. بعد الدخول، `user.role` يحدد الواجهة (`driver` أو `vendor`).
نفس هيكل وأسلوب تطبيق العميل (مستودع `talabat-girga-customerapp`): Riverpod 3، go_router، dio، flutter_map.

## التشغيل

```bash
# الإنتاج (الافتراضي)
flutter run

# السيرفر المحلي على موبايل حقيقي
adb reverse tcp:9123 tcp:9123
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:9123/api/v1

# APK للإنتاج
flutter build apk --release
```

حسابات التجربة المحلية: سائقين 01200000001 / 01200000002، تاجر 01111111111 (كلمة المرور من DemoSeeder).
لا يوجد تسجيل من التطبيق: الإدارة تنشئ حسابات السائقين والتجار وكلمات المرور من لوحة التحكم.

## الهيكل

```
lib/
  core/       api (ApiException برسائل عربية)، theme، widgets، format، config، launch (اتصال/خرائط)
  data/       repository.dart — كل نداءات الـ API
  models/     models.dart
  services/   location_tracker (خدمة أمامية للموقع)، offer_alert (رنين + اهتزاز)
  state/      auth.dart، driver.dart (الاتصال، الموقع، استطلاع العروض)، vendor.dart (المتجر، استطلاع الطلبات الجديدة والرنين)
  features/
    auth/             الدخول (موبايل + كلمة مرور) وشاشة "حسابك لسه مش جاهز"
    driver/info       "بياناتي" (المركبة + المستندات) وشاشة انتظار الموافقة
    driver/home       زر الاتصال، الطلب الجاري، ملخص اليوم
    driver/offer      عرض الطلب بملء الشاشة وعدّاد تنازلي
    driver/order      تنفيذ الطلب: وصلت ← استلمت ← سلّمت (كود التسليم)
    driver/earnings   الأرباح والكاش والحركات
    driver/history    سجل الطلبات
    account/          حسابي + تغيير كلمة المرور
    support/          تذاكر الدعم
    vendor/orders     الطلبات: فتح/إغلاق المتجر، جديدة (رنين) / جارية / السابقة، قبول بمدة التجهيز، رفض/إلغاء بسبب، تجهيز/جاهز
    vendor/products   المنتجات: توفر، بحث، أقسام
    vendor/menu       إضافة/تعديل/حذف المنتجات بالصور والإضافات، وإدارة الأقسام
    vendor/store      مواعيد العمل الأسبوعية
    vendor/finance    الرصيد وكشف الحساب، طلب صرف/تسجيل تحويل (بموافقة الإدارة)، استلام كاش من السائقين (بتأكيد السائق)
    vendor/sales      ملخص المبيعات والرصيد والأكثر مبيعًا
```

## بدون WebSockets

الاستضافة المشتركة لا تدعم WebSockets، فالتطبيق يستطلع:
العروض كل 5 ثوانٍ أثناء الاتصال، الطلب الجاري كل 10 ثوانٍ، والموقع يُرسل كل 10 ثوانٍ.
التاجر: الطلبات الجديدة كل 10 ثوانٍ طالما التطبيق شغال، ويرن حتى يقبل/يرفض أو يوقف الصوت.
السائق يرى طلبات تأكيد تسليم الكاش للمتاجر في الرئيسية (تتحدث كل 30 ثانية).
أثناء الاتصال يعمل تتبع الموقع كخدمة أمامية بإشعار ثابت، فيستمر مع قفل الشاشة.
