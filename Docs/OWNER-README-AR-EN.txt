AP Manager — أدوات المالك فقط

أرسل للعميل حزمة AP-Manager-Client-20261025 فقط.
احتفظ بهذه الحزمة لديك، ولا ترسل ملف activation-private-key.pem أو أداة إصدار التفعيل للعميل.

إصدار مفتاح تفعيل:
1. اطلب رقم الجهاز APM-... من شاشة التفعيل عند العميل.
2. افتح AP-Manager-Activation.exe واترك ملف activation-private-key.pem بجانبه.
3. أدخل رقم الجهاز، واسم العميل، وآخر يوم مسموح للتشغيل بصيغة YYYY-MM-DD.
4. الأداة تنشئ ملف .aplicense بجانبها وتعرض المفتاح. أرسل محتوى ملف التفعيل فقط إلى العميل ليُلصقه في البرنامج.
5. الصلاحية تشمل آخر اليوم المحدد بتوقيت القاهرة، مع مراعاة التوقيت الصيفي.

مثال من Terminal داخل المجلد:
AP-Manager-Activation.exe --machine APM-0123456789ABCDEF0123456789ABCDEF --customer "Client" --through 2026-12-31

احتفظ بنسخة آمنة من هذه الحزمة. المفتاح الخاص مطلوب لتجديد النسخة نفسها لاحقًا.
لإعادة البناء استخدم ملفات المفتاح الخاص والمفتاح العام وstate-secret نفسها. توليد مفاتيح جديدة ينتج سلسلة تفعيل مختلفة.

حدود الحماية:
التغليف يمنع تسليم السورس كملفات ظاهرة، لكنه لا يمنع الهندسة العكسية بالكامل.
الترخيص المحلي يقاوم إرجاع الساعة وتعديل سجل الاستخدام المعتاد، لكنه ليس بديلًا عن خادم ترخيص إذا كان المطلوب مقاومة مسؤول جهاز لديه تحكم كامل بالبيئة.
المستودع الأصلي عام على GitHub؛ جعله Private قرار منفصل حتى لا يظل السورس الأصلي متاحًا للعامة.
ملفات EXE غير موقّعة بشهادة ناشر. يلزم توقيعك الرقمي إذا أردت إصدارًا موقّعًا باسمك.
التجميع والاختبارات الآلية لا تغني عن تجربة Excel وأجهزة Cisco الفعلية في شبكة العميل.

OWNER ONLY — Keep this package private

Send only AP-Manager-Client-20261025 to the customer. Never share the private PEM key or activation tool.

To renew: obtain the APM-... machine ID, open AP-Manager-Activation.exe, enter the ID, customer name and last permitted Cairo date (YYYY-MM-DD).
Send only the generated .aplicense file contents. The customer pastes this key into the activation screen.
The selected date is inclusive through the end of that Cairo day, including daylight-saving transitions.
Keep activation-private-key.pem next to the owner tool. Back up the entire owner package.
Rebuild with the same private key, public key and state-secret to retain activation compatibility.

Packaging does not guarantee resistance to reverse engineering. Local clock history is a deterrent, not a substitute for a trusted online licensing service against a machine administrator.
The original GitHub repository is public; making it private is a separate owner decision.
The executables are unsigned. Sign with your own publisher certificate if needed.
Automated checks do not verify Microsoft Excel COM or Cisco device behavior on the customer's actual Windows network.
