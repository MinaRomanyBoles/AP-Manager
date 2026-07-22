AP WiFi Manager — Cisco Aironet 3600 — Version 4.1
=================================================

طريقة الاستخدام:
1) كليك يمين على ملف ZIP قبل فك الضغط، ثم Properties، وفعّل Unblock إن ظهرت.
2) فك الضغط بالكامل في مجلد واحد.
3) افتح AP-Info-Manager.xlsx من نفس المجلد.
4) عدّل New WiFi SSID و/أو New WiFi Password في الصف المطلوب.
5) اضغط Run في نفس الصف مباشرة.
6) وافق على رسالة Excel الأمنية ورسالة UAC.
7) لا تفصل كابل Ethernet أثناء التنفيذ.

قراءة القيم من Excel:
- عند الضغط على Run، يقوم Launcher بقراءة القيم الحالية الظاهرة في خلايا نفس الصف من ملف Excel المفتوح.
- لا تحتاج إلى الضغط على Save قبل Run؛ التعديلات غير المحفوظة يتم التقاطها مباشرة من Excel.
- إذا تم تشغيل ملف Run_Row_x.cmd يدويًا بينما Excel مغلق، يستخدم السكربت آخر قيم محفوظة في الملف.
- يسجل الـLog اسم المصدر المستخدم: Live open Excel cells أو Saved workbook file.
- لا يعرض باسورد الـWiFi داخل الـLog؛ يعرض فقط هل الخانة فارغة أو بها قيمة.

الأعمدة التي تُقرأ من نفس الصف:
A: Department
B: Access Point Name
C: Access Point IP
D: Access Point Mac Address
E: Access User
F: Access Password وEnable Password
G: New WiFi SSID
H: New WiFi Password

ما الذي يفعله السكربت؟
- يتصل أولًا عبر Telnet ويدخل Privileged Mode باستخدام نفس كلمة المرور.
- يقرأ SSID المرتبط بـ Dot11Radio0 فقط (2.4GHz).
- يتجاهل Dot11Radio1 (5GHz).
- يغيّر SSID فقط إذا كانت خانة New WiFi SSID غير فارغة.
- يغيّر WPA2 Password فقط إذا كانت خانة New WiFi Password غير فارغة.
- يحفظ Running Configuration إلى Startup Configuration.
- ينشئ RSA Key بحجم 4096 bit عند الحاجة، ويحوّل SSH إلى Version 2، ثم يتحقق منه.
- ينشئ Backup من running-config داخل Backups قبل أي تغيير.
- ينشئ Log داخل Logs.

متطلبات التشغيل:
- Windows + Microsoft Excel Desktop.
- الاتصال بالـAPs من خلال كابل Ethernet.
- Telnet Port 23 مفعّل على الـAPs للوصول الأولي.
- Access Password هو نفسه Enable Password.
- الأجهزة Cisco Aironet 3600 Autonomous وبها SSID واحد مرتبط بـ Dot11Radio0.

تنبيهات:
- اختبر على AP واحد أولًا.
- كلمات مرور الإدارة موجودة داخل Excel كنص واضح؛ احفظ المجلد في مكان مؤمّن.
- لا تغيّر أسماء الملفات ولا تنقل ملف Excel بعيدًا عن مجلد Scripts.

تحديث Version 3:
- القراءة أصبحت من القيم الحالية الفعلية في ملف Excel المفتوح عند الضغط على Run.
- لم يعد حفظ الملف يدويًا قبل Run مطلوبًا.
- يتم تمرير لقطة الصف إلى العملية بصيغة مؤقتة، ثم حذفها فور قراءتها لأنها تحتوي بيانات الدخول.

تحديث Version 4 — Get Clients:
- تمت إضافة زر Get في العمود J لكل Access Point.
- الزر يقرأ IP من العمود C وAccess User من E وAccess Password/Enable Password من F من الخلايا الحالية في Excel.
- يتصل بالـAP عبر Telnet، يدخل Privileged Mode، ثم ينفذ show dot11 associations client.
- يحسب العملاء الظاهرين تحت Dot11Radio0 (2.4GHz) فقط، ويكتب العدد في العمود K.
- Dot11Radio1 (5GHz) لا يدخل في العدد.
- زر Get لا يحتاج Run as Administrator ولا يغيّر أي إعداد على الـAP.
- لو ظهر ERROR في K، ستظهر نافذة توضح سبب الخطأ مثل عدم الوصول إلى Port 23 أو خطأ بيانات الدخول.
- عندما يكون ملف Excel مفتوحًا، تظهر النتيجة فورًا في K؛ احفظ الملف بعد الانتهاء للاحتفاظ بالنتائج.


تحديث Version 4.1 — إصلاح كتابة عدد Clients:
- تم إصلاح خطأ Unable to cast object of type System.Int32 to type System.String.
- تتم كتابة العدد في K كقيمة رقمية في Excel من خلال Formula رقمية آمنة مع Excel COM.
- تمت إضافة اسم مرحلة التنفيذ ورقم سطر السكربت عند ظهور أي خطأ جديد لتسهيل التشخيص.
