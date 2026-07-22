AP Manager — Cisco Aironet 3600 — Web Dashboard
================================================

متطلبات التشغيل:
- Windows 10 أو Windows 11
- Node.js 18 أو أحدث (LTS)
- Microsoft Excel Desktop
- الاتصال بأجهزة AP عبر كابل Ethernet أثناء تغيير إعدادات Wi-Fi
- PowerShell 5.1 أو أحدث
- وحدة Posh-SSH (يتم تثبيتها تلقائيًا عبر Install-AP-Manager.bat)

طريقة التثبيت:
1) افتح مجلد AP Manager
2) شغّل Install-AP-Manager.bat
3) انتظر رسالة "Installation completed successfully"

طريقة تشغيل الموقع:
1) شغّل Start-AP-Manager.bat
2) سيفتح المتصفح تلقائيًا على: http://127.0.0.1:8787
3) إذا كان السيرفر يعمل مسبقًا، لن يُفتح نسخة ثانية

طريقة إغلاق الموقع:
1) شغّل Stop-AP-Manager.bat
2) يتم إيقاف السيرفر وتنظيف ملفات Runtime المؤقتة

مكان ملف Excel:
- AP-Info-Manager.xlsx في جذر مجلد AP Manager
- يمكن فتح الملف في Excel أثناء عمل الموقع
- القراءة تتم من القيم الحية إذا كان Excel مفتوحًا
- عدد Clients يُكتب دائمًا في العمود K

طريقة إضافة AP جديد:
1) افتح AP-Info-Manager.xlsx
2) أضف صفًا جديدًا بالأعمدة: Access Point Name, IP, MAC, Access User, Access Password
3) اضغط Reload Excel في الموقع

قراءة Clients:
1) اضغط Get Clients في صف الـAP
2) أو استخدم Refresh All Clients لجميع الأجهزة (3 اتصالات متزامنة كحد أقصى)
3) أثناء التحميل تظهر "..." في Excel والرمز 🏃‍♂️‍➡️ في الموقع

تغيير SSID:
1) اكتب New WiFi SSID في Excel
2) اضغط Apply Changes
3) إذا تركت الحقل فارغًا، لن يتغير SSID

تغيير Wi-Fi Password:
1) اكتب New WiFi Password في Excel (8–63 حرف)
2) اضغط Apply Changes
3) إذا تركت الحقل فارغًا، لن تتغير كلمة المرور
4) بعد النجاح، تُمسح كلمة المرور الجديدة من Excel لأسباب أمنية

أماكن Logs و Backups:
- Logs/ — سجلات عمليات Get Clients و Apply Changes
- Backups/ — نسخ running-config قبل أي تعديل

أشهر الأخطاء وحلولها:
- AP لا يرد على Ping → تحقق من الكابل والـIP
- Port 22/23 مغلق → فعّل Telnet/SSH على الجهاز
- Login failed → تحقق من Access User و Access Password في Excel
- Excel locked → أغلق أي نسخة مقفلة أو احفظ الملف
- SSH negotiation failed → يتم التحويل تلقائيًا إلى Telnet
- ERROR في عمود Clients → راجع Logs/ للتفاصيل

تحذيرات مهمة:
- لا تفصل كابل Ethernet أثناء تغيير Wi-Fi
- لا تشارك ملف Excel — يحتوي على كلمات مرور بplaintext
- اختبر على AP واحد قبل التعديل الجماعي
- التعديلات الجماعية تتم جهازًا واحدًا في كل مرة

النسخ الاحتياطية:
- السكربتات الأصلية محفوظة في Backups/Scripts_Original_*
- لا تُعدّل السكربتات الأصلية مباشرة — استخدم Scripts/Get-Clients.ps1 و Update-AccessPoint.ps1

المنفذ والأمان:
- الموقع يعمل محليًا فقط على 127.0.0.1:8787
- كلمات المرور لا تُرسل إلى المتصفح
- لا تُخزَّن كلمات المرور في LocalStorage
