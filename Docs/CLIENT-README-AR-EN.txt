AP Manager — نسخة العميل

التشغيل:
1. فك ضغط الحزمة بالكامل في مجلد تملك صلاحية الكتابة فيه، مثل سطح المكتب.
2. يلزم Windows 10/11 إصدار 64-bit وMicrosoft Excel Desktop. لا يلزم تثبيت Node.js أو أدوات برمجة.
3. ملف AP-Info-Manager.xlsx المرفق قالب فارغ. أدخل بيانات أجهزة الشبكة فيه، أو استبدله بملفك الأصلي بنفس الاسم. احتفظ باسم الورقة Sheet1 وعناوين الأعمدة في الصف الأول، وعمود Clients في K.
4. افتح AP-Manager.exe. تفتح لوحة التحكم تلقائيًا في المتصفح على http://127.0.0.1:8787.
5. اترك نافذة البرنامج مفتوحة. لإيقافه استخدم Ctrl+C أو أغلق نافذته.

الصلاحية والتفعيل:
تعمل هذه النسخة حتى 25 أكتوبر 2026 الساعة 23:59:59 بتوقيت القاهرة.
من 26 أكتوبر 2026 الساعة 00:00 تظهر شاشة التفعيل وتُمنع العمليات الجديدة.
أرسل رقم الجهاز الظاهر في شاشة التفعيل إلى مزوّد البرنامج، ثم الصق المفتاح الذي يصلك واضغط تفعيل.
يمكن فتح شاشة التفعيل مبكرًا من زر Activate / Renew.
التفعيل خاص بالجهاز. لا يحتاج اتصالًا بالإنترنت. حافظ على صحة تاريخ ووقت Windows.
انتهاء الصلاحية لا يحذف ملف Excel أو النسخ الاحتياطية أو سجلات العمليات.
قد تستكمل العملية التي بدأت قبل انتهاء الصلاحية خطواتها لحفظ إعدادات الجهاز بأمان.

البيانات:
احفظ نسخة احتياطية من ملف Excel قبل استخدامه. يحتوي على كلمات مرور أجهزة الشبكة؛ تعامل معه كملف سري.
توجد السجلات في Logs والنسخ الاحتياطية في Backups بجانب البرنامج.
يُضمّن البرنامج اعتماد SSH ولا يتطلب تنزيل Posh-SSH عند العميل.
لا تتضمن الحزمة ملفات السورس الخاصة بالتطبيق.

AP Manager — Client edition

1. Extract the entire ZIP into a writable folder, such as Desktop.
2. Requires 64-bit Windows 10/11 and Microsoft Excel Desktop. No Node.js or development tools are required.
3. AP-Info-Manager.xlsx is an EMPTY TEMPLATE. Enter the customer's AP data or replace it with the original workbook using the same filename. Keep Sheet1, row-one headers and Clients in column K.
4. Open AP-Manager.exe. The dashboard opens at http://127.0.0.1:8787.
5. Keep the program window open. Press Ctrl+C or close that window to stop it.

Valid through 25 October 2026, 23:59:59 Cairo time. Activation is required from 26 October 2026, 00:00.
Send the displayed machine ID to your software provider, paste the returned activation key and choose Activate.
Activate / Renew is also available before expiry. Activation is offline and tied to this computer.
Keep the Windows date/time correct. Expiry does not delete your workbook, logs or backups.
An operation started before expiry may finish saving the device configuration; no new operation starts after expiry.

Keep your Excel workbook backed up and private: it contains device passwords.
Logs and Backups are saved beside the EXE. The SSH dependency is included; no Posh-SSH download is needed.
This package contains no loose application source files.
