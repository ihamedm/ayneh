<div dir="rtl" align="right">

# آینه (Ayneh)

**اسکنر و تنظیم‌کنندهٔ میرورهای ایرانی مخازن نرم‌افزاری**

<p align="left">
  <img alt="version" src="https://img.shields.io/badge/version-2.0.0-blue">
  <img alt="license" src="https://img.shields.io/badge/license-MIT-green">
  <img alt="bash" src="https://img.shields.io/badge/bash-%3E%3D%204-4EAA25?logo=gnubash&logoColor=white">
  <a href="https://github.com/ihamedm/ayneh/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/ihamedm/ayneh/actions/workflows/ci.yml/badge.svg"></a>
</p>

«آینه» یک ابزار خط فرمان است که مخازن بسته‌های نرم‌افزاری را از نظر دسترسی بررسی می‌کند و وقتی یک مخزن خارجی (مثل `registry.npmjs.org`، `pypi.org`، `archive.ubuntu.com` یا `registry-1.docker.io`) در دسترس نبود، با یک منوی ساده به شما کمک می‌کند به یک میرور ایرانی قابل‌دسترس سوییچ کنید.

> [!NOTE]
> این ابزار فقط فایل‌های پیکربندی را تغییر می‌دهد؛ خودش بسته‌ای نصب نمی‌کند و به هیچ سروری جز میرورهایی که تست می‌کند داده نمی‌فرستد.

---

## نصب و اجرا با یک خط

بدون نصب، مستقیم از GitHub اجرا کنید:

```bash
curl -fsSL https://raw.githubusercontent.com/ihamedm/ayneh/main/dist/ayneh.sh | bash
```

اجرای غیرتعاملی (مثلاً روی سرور یا داخل اسکریپت):

```bash
curl -fsSL https://raw.githubusercontent.com/ihamedm/ayneh/main/dist/ayneh.sh | bash -s -- --scan
```

نصب دائمی به‌عنوان دستور `ayneh` (پیشنهادشده برای سرور):

```bash
curl -fsSL https://raw.githubusercontent.com/ihamedm/ayneh/main/install.sh | sudo bash
ayneh
```

پس از نصب:

```bash
ayneh              # منوی تعاملی
ayneh --scan       # اسکن همهٔ مخازن
ayneh --help       # راهنما
```

> [!TIP]
> اسکریپت با `curl | bash` هم به‌درستی کار می‌کند؛ ورودی منو از `/dev/tty` خوانده می‌شود، نه از `stdin`.
> اگر روی سروری بدون ترمینال تعاملی هستید، از `--scan`، `--list` یا `--apply` استفاده کنید و
> عملیات سیستمی را با `sudo bash -s -- ...` اجرا کنید.

---

## ابزار چه کاری انجام می‌دهد؟

1. **تشخیص سیستم** — توزیع لینوکس، نسخه، معماری و مدیر بستهٔ فعال (apt، dnf/yum، pacman، apk و …).
2. **اسکن مخازن فعلی** — تمام مخازن پیکربندی‌شده (از جمله `sources.list.d`، فایل‌های deb822 و `yum.repos.d`) را پیدا و آدرس واقعی هرکدام را تست می‌کند.
3. **تست واقعی میرورها** — به‌جای اکتفا به صفحهٔ اصلی، مسیر واقعی بسته‌ها را بررسی می‌کند:
   - npm: مسیر یک بستهٔ نمونه
   - PyPI: مسیر `/simple/pip/`
   - Docker: مسیر `/v2/` (پاسخ `401` هم یعنی رجیستری زنده است)
   - apt: فایل `Release` مربوط به همان suite واقعی
   - dnf/yum: فایل `repodata/repomd.xml` مطابق نسخه و معماری
   - pacman و apk: مسیر `APKINDEX` / مخزن `core`
4. **پشتیبان‌گیری و اعمال** — قبل از هر تغییر یک نسخهٔ پشتیبان زمان‌دار می‌سازد، فایل را بازنویسی می‌کند و دستور به‌روزرسانی ایندکس را نشان می‌دهد.
5. **بازگردانی** — با `ayneh --restore` می‌توانید هر تغییر را برگردانید.

---

## سرویس‌های پشتیبانی‌شده

| سرویس | کلید(ها) | فایل‌های تغییرکرده |
| --- | --- | --- |
| npm | `npm` | `~/.npmrc` (یا `npm config`) |
| Python / pip | `pypi` | `/etc/pip.conf` یا `~/.config/pip/pip.conf` |
| Docker | `docker` | `/etc/docker/daemon.json` |
| Ubuntu apt | `ubuntu` | `/etc/apt/sources.list` و `sources.list.d/*` |
| Debian apt | `debian` | `/etc/apt/sources.list` و `sources.list.d/*` |
| CentOS / Rocky / AlmaLinux / Fedora | `centos`، `rocky`، `almalinux`، `fedora` | `/etc/yum.repos.d/*.repo` |
| EPEL | `epel` | `/etc/yum.repos.d/*.repo` |
| Arch / pacman | `pacman` | `/etc/pacman.d/mirrorlist` |
| Alpine / apk | `apk` | `/etc/apk/repositories` |

نام‌های کوتاه هم پذیرفته می‌شوند:

- `apt` → روی اوبونتو به `ubuntu` و روی دبیان به `debian` نگاشت می‌شود.
- `yum` (یا `rhel`) → به نسخهٔ خانوادهٔ RHEL روی سیستم شما نگاشت می‌شود.
- `alma` → `almalinux`.

در حال حاضر حدود **۹۶ میرور ایرانی** از ارائه‌دهندگانی مثل آروان‌کلاد، لیارا،
مبین‌هاست، ایران‌سرور، اصفهان‌یوتی، پارس‌پک، رانفلر و … ثبت شده است.

---

## استفاده

### منوی تعاملی

```bash
ayneh
```

منوی اصلی:

```text
  1) Scan all repositories now
  2) Scan a single service
  3) Apply / switch a mirror  (interactive)
  4) Show current configuration
  5) List all known Iranian mirrors
  6) Test any mirror URL
  7) Restore from backup
  0) Exit
```

در گزینهٔ ۳، میرورهای همان سرویس **به‌صورت موازی** تست می‌شوند و جدولی مثل زیر می‌بینید:

```text
  #   MIRROR                 STATUS     URL
  ------------------------------------------------------------
  1   ArvanCloud             OK         https://mirror.arvancloud.ir/ubuntu
  2   Liara                  OK         https://package-mirror.liara.ir/...
  3   SomeProvider           down       https://...
```

### خط فرمان (مناسب اسکریپت و سرور)

| دستور | کار |
| --- | --- |
| `ayneh --scan` | اسکن همهٔ مخازن و چاپ گزارش |
| `ayneh --scan npm` | اسکن فقط یک سرویس (نام سرویس یا alias) |
| `ayneh --show` | نمایش پیکربندی فعلی |
| `ayneh --list` | فهرست همهٔ میرورهای ثبت‌شده |
| `ayneh --list npm` | فهرست میرورهای یک سرویس |
| `ayneh --test <url>` | تست دسترسی یک URL و چاپ کد HTTP |
| `ayneh --apply npm Liara` | اعمال میرور با نام |
| `ayneh --apply npm --url <url>` | اعمال میرور با URL دلخواه |
| `ayneh --restore` | فهرست پشتیبان‌ها |
| `ayneh --restore <path>` | بازگردانی یک پشتیبان |
| `ayneh --version` | نمایش نسخه |
| `ayneh --help` | راهنما |

نمونه‌ها:

```bash
# فقط مخازن apt را بررسی کن (روی اوبونتو یا دبیان)
sudo ayneh --scan apt

# میرور npm را عوض کن و تأیید کن
ayneh --apply npm Liara
npm config get registry

# یک URL دلخواه را تست کن
ayneh --test https://mirror.arvancloud.ir/debian/dists/bookworm/Release

# پشتیبان‌ها را ببین و یکی را برگردان
sudo ayneh --restore
sudo ayneh --restore /var/backups/ayneh/sources.list.apt.20260101-120000.bak
```

### کد خروج

- `0` — موفق
- `1` — خطای کاربری، سرویس ناشناس، در دسترس نبودن میرور، یا شکست در تغییر فایل

---

## امنیت و رفتار ابزار

- **قبل از اجرا کد را ببینید.** الگوی `curl | bash` راحت است، اما همیشه می‌توانید اول فایل را دانلود و بررسی کنید:

  ```bash
  curl -fsSL https://raw.githubusercontent.com/ihamedm/ayneh/main/dist/ayneh.sh -o ayneh.sh
  less ayneh.sh
  bash ayneh.sh --scan
  ```

- **فقط فایل‌های سیستمی به root نیاز دارند.** تغییر تنظیمات npm و pip در سطح کاربر بدون sudo انجام می‌شود. برای apt/dnf/pacman/apk/داکر، ابزار در صورت نیاز از sudo استفاده می‌کند و رمز را از ترمینال می‌پرسد.
- **همیشه پشتیبان می‌گیرد.** پشتیبان‌ها در این مسیرها ذخیره می‌شوند:
  - کاربر: `~/.ayneh-backup/`
  - سیستم: `/var/backups/ayneh/`
  - پشتیبان‌های نسخهٔ قدیمی (`~/.mirrors-backup` و `/var/backups/mirrors`) هم شناسایی می‌شوند.
  - کنار هر پشتیبان یک فایل `.meta` با مسیر اصلی فایل ذخیره می‌شود تا بازگردانی مطمئن باشد.
- **هیچ میروری بدون تست اعمال نمی‌شود.** اگر میرور در دسترس نباشد یا مسیر بسته‌ها را سرو نکند، عملیات متوقف می‌شود.
- **بدون تلمتری.** ابزار هیچ داده‌ای جمع‌آوری یا ارسال نمی‌کند.
- **گواهی TLS** به‌صورت پیش‌فرض توسط `curl` بررسی می‌شود؛ میان‌افزار SSL را غیرفعال نمی‌کنیم.

---

## متغیرهای محیطی

| متغیر | پیش‌فرض | توضیح |
| --- | --- | --- |
| `NO_COLOR` | تنظیم‌نشده | با مقدار `1` رنگ‌ها غیرفعال می‌شوند |
| `AYNEH_CONNECT_TIMEOUT` | `6` | مهلت اتصال curl (ثانیه) |
| `AYNEH_MAX_TIME` | `12` | مهلت کل درخواست curl (ثانیه) |
| `AYNEH_REPO` | `ihamedm/ayneh` | مخزن مورد استفاده در پیام‌های راهنما |
| `AYNEH_BRANCH` | `main` | شاخهٔ مورد استفاده در پیام‌های راهنما |
| `AYNEH_REF` | `main` | شاخه/تگ برای `install.sh` |
| `AYNEH_BASE_URL` | آدرس GitHub | آدرس پایهٔ دانلود در `install.sh` (برای میرور/تست) |
| `PREFIX` | `/usr/local` | مسیر نصب در `install.sh` |
| `BINDIR` | `$PREFIX/bin` | مسیر دقیق نصب دستور |

روی شبکهٔ کند:

```bash
AYNEH_CONNECT_TIMEOUT=10 AYNEH_MAX_TIME=30 ayneh --scan
```

---

## ساختار پروژه

```text
ayneh                 نقطهٔ ورود توسعه (lib/*.sh را source می‌کند)
lib/
  00-core.sh          رنگ‌ها، لاگ، پرسش‌ها، sudo، پوشهٔ موقت
  10-os.sh            تشخیص توزیع و مدیر بسته
  20-http.sh          تست HTTP و بررسی دسترسی میرور
  30-registry.sh      رجیستری میرورها  ← برای افزودن میرور اینجا را ویرایش کنید
  40-scan.sh          اسکن مخازن و نمایش پیکربندی
  50-backup.sh        پشتیبان‌گیری و بازگردانی
  60-apply.sh         اعمال میرور برای هر سرویس
  70-menu.sh          منوهای تعاملی
  90-main.sh          پارس آرگومان‌ها و main
build.sh              ساخت dist/ayneh.sh از lib/*.sh
dist/ayneh.sh         نسخهٔ تک‌فایلی (تولیدشده و کامیت‌شده)
install.sh            نصب‌کنندهٔ یک‌خطی
tests/smoke.sh        تست‌های آفلاین
Makefile              build / test / lint / install
```

`dist/ayneh.sh` به‌صورت خودکار ساخته می‌شود و همان فایلی است که دستور `curl` دانلود می‌کند.
آن را دستی ویرایش نکنید.

---

## توسعه

```bash
git clone https://github.com/ihamedm/ayneh.git
cd ayneh

./build.sh                 # ساخت dist/ayneh.sh
bash -n dist/ayneh.sh      # بررسی سینتکس
make test                  # تست‌های آفلاین
make lint                  # shellcheck (در صورت نصب)
./ayneh --help
```

نصب از سورس:

```bash
make install               # در /usr/local/bin/ayneh
# یا:
sudo install -m 0755 dist/ayneh.sh /usr/local/bin/ayneh
```

> هر تغییری در `lib/` باید با اجرای `./build.sh` و کامیت‌کردن `dist/ayneh.sh` همراه باشد.
> CI اگر `dist` قدیمی باشد شکست می‌خورد.

### افزودن میرور جدید

۱. فایل [`lib/30-registry.sh`](lib/30-registry.sh) را باز کنید و یک خط به آرایهٔ مربوطه اضافه کنید:

```bash
NPM_MIRRORS=(
    "Liara|https://package-mirror.liara.ir/repository/npm/"
    "MyProvider|https://npm.myprovider.ir/"
)
```

۲. تست کنید:

```bash
./ayneh --test "https://npm.myprovider.ir/npm"
./ayneh --list npm
./build.sh && make test
```

قواعد مسیر هر نوع میرور در [`CONTRIBUTING.md`](CONTRIBUTING.md) توضیح داده شده است.

---

## عیب‌یابی

**`ayneh: requires bash 4 or newer`**
سیستم شما bash قدیمی دارد (مثلاً macOS پیش‌فرض). bash 4+ نصب کنید یا از یک کانتینر لینوکسی استفاده کنید:

```bash
docker run --rm -it -v "$PWD":/w -w /w bash:5 ./ayneh
```

**sudo رمز می‌خواهد اما منوی تعاملی نیست**
ابزار تلاش می‌کند رمز را از `/dev/tty` بگیرد. اگر ترمینال ندارید، مستقیم با sudo اجرا کنید:

```bash
curl -fsSL .../dist/ayneh.sh | sudo bash -s -- --apply debian ArvanCloud
```

**یک میرور `down` نشان داده می‌شود**
ممکن است موقتاً قطع باشد یا مسیر آن تغییر کرده باشد. با `ayneh --test <url>` بررسی کنید و در صورت خرابی issue باز کنید.

**بعد از تغییر apt، خطای ۴۰۴ می‌گیرم**
ممکن است codename سیستم شما روی آن میرور موجود نباشد. با `ayneh --restore` برگردانید و میرور دیگری امتحان کنید.

**داکر هنوز از میرور استفاده نمی‌کند**
بعد از اعمال، سرویس داکر را ری‌استارت کنید:

```bash
sudo systemctl restart docker
```

**پورت/فایروال**
ابزار به HTTP/HTTPS خروجی (۴۴۳/۸۰) نیاز دارد. در شبکه‌های محدود، ممکن است برخی میرورها اصلاً قابل دسترس نباشند.

---

## مشارکت

از مشارکت شما استقبال می‌شود! مهم‌ترین کمک، **افزودن یا اصلاح میرورها** است.
راهنمای کامل در [`CONTRIBUTING.md`](CONTRIBUTING.md) آمده است.

- باگ یا میرور خراب را در [Issues](https://github.com/ihamedm/ayneh/issues) گزارش دهید.
- برای تغییر کد، یک شاخه بسازید، `make lint && make test` را اجرا کنید و Pull Request بفرستید.

English documentation: [`README.en.md`](README.en.md)

---

## سپاس

- از پروژهٔ [Mirava](https://github.com/MiravaOrg/Mirava) برای فهرست‌کردن ارائه‌دهندگان میرور.
- از همهٔ ارائه‌دهندگانی که میرورهای عمومی برای کاربران ایرانی نگه می‌دارند.

## مجوز

[MIT](LICENSE) © 2026 ihamedm and contributors

</div>
