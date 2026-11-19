<div align="center">

<img src="docs/icon.png" width="120" alt="Bloom Desk">

# Bloom Desk 🌸

**مكتبك الهادئ: مشاريعك، وتركيزك، وحديقة يومك في برنامج واحد لويندوز**

*A calm Windows desk for makers: launch your projects in one click, focus with a growing rose, and see where your day went.*

[**⬇️ حمّل لويندوز / Download for Windows**](https://github.com/marwathebest/bloom-desk/releases/latest/download/BloomDesk-Setup.exe)
 · [الموقع / Website](https://marwathebest.github.io/bloom-desk/)

</div>

## الصور

![مشاريعي](docs/screenshots/projects.png)

| 🌱 جلسة تركيز | 🌷 حديقة اليوم |
|---|---|
| ![جلسة تركيز](docs/screenshots/focus.png) | ![حديقة اليوم](docs/screenshots/garden.png) |

## المميزات

| | |
|---|---|
| 📂 **مشاريعك في مكان واحد** | اسحب مجلد المشروع وافلته، ويتعرف على نوعه (Flutter، أو React/Node، أو موقع) واسمه ورابط GitHub والموقع المنشور |
| ▶️ **شغّل بضغطة** | يشغّل المشروع بالأمر الصحيح، وينتظر السيرفر إلى أن يجهز، ويفتح المتصفح لحاله |
| ✅ **جهّز للعرض** | يفحص كل مشاريعك قبل الاجتماع 🟢🟡🔴، ويصلّح المكتبات الناقصة، ويصحّي المواقع النايمة |
| 📋 **لوحة كانبان** | 💡 فكرة، و🛠️ قيد العمل، و✅ مكتمل: اسحب البطاقة بين الأعمدة، وأضف أفكار بملاحظات بدون مجلد |
| 🌱 **جلسة تركيز** | وردة تكبر وتتمايل مع وقتك، ومدة تختارها، و«زِد ٥ دقائق»، ونافذة صغيرة فوق البرامج، وإشعار ويندوز لما تخلص، وأصوات هادئة، وتكمّل الجلسة لو انقفل البرنامج |
| 💡 **الأفكار الطارئة** | تكتبها وسط الجلسة، وبعدها تروح لملاحظات المشروع أو تصير أفكار في اللوحة |
| ☕ **الراحة** | تذكير بعد كل جلسة: 💧 ماء، و🧘 تمدد، و👀 قاعدة 20-20-20، وراحة طويلة كل ٤ جلسات، وهدف يومي |
| 🌷 **حديقة اليوم** | وردة لكل جلسة، ووين راح وقتك لكل مشروع، وكل أفكارك مجمّعة |

## التثبيت

1. حمّل [`BloomDesk-Setup.exe`](https://github.com/marwathebest/bloom-desk/releases/latest/download/BloomDesk-Setup.exe)
2. افتحه واضغط **Install** (ما يحتاج صلاحيات مدير)
3. لو طلع تحذير **"Windows protected your PC"**، اضغط **More info** ثم **Run anyway**. هذا طبيعي لأن البرنامج ما عليه توقيع رقمي مدفوع

يشتغل على **Windows 10 و 11 (64-bit)**. وبياناتك كلها تبقى على جهازك.

## البناء من الكود

يحتاج [Flutter](https://flutter.dev) و Visual Studio مع **Desktop development with C++**.

```bash
flutter pub get
flutter test
flutter build windows
```

ولبناء المثبّت تحتاج [Inno Setup 6](https://jrsoftware.org/isinfo.php):

```bash
ISCC /DCRT_DIR="<Visual Studio>\VC\Redist\MSVC\<version>\x64\Microsoft.VC145.CRT" installer\bloom_desk.iss
```

## الرخصة

[MIT](LICENSE) © 2026 marwathebest

أيقونة الوردة 🌸 من [Fluent Emoji](https://github.com/microsoft/fluentui-emoji) من Microsoft (رخصة MIT).
