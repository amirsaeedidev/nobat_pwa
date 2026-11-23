# اتصال اختیاری DateTime به Supabase

## وضعیت معماری

- برنامه به‌صورت پیش‌فرض با داده‌های محلی `Datamonck` اجرا می‌شود.
- Supabase فقط وقتی فعال می‌شود که `SUPABASE_ENABLED=true` و URL و Publishable Key در زمان Build تزریق شده باشند.
- در حالت آفلاین یا وقتی Supabase غیرفعال است، هیچ درخواست شبکه‌ای برای ورود اجرا نمی‌شود و برنامه با `Datamonck` بالا می‌آید. در حالت Cloud، نشست ذخیره‌شده بازیابی و عضویت کاربر در مجموعه بررسی می‌شود.
- کلید Publishable برای کلاینت است. هرگز `service_role` یا `sb_secret` را در اپ، فایل env کلاینت یا Git قرار ندهید.

## تنظیم محیط

1. فایل `.env.example` را به `.env` کپی کنید.
2. مقادیر URL و Publishable Key را از Supabase Dashboard > Connect بردارید.
3. اجرا:

```bash
flutter pub get
flutter run --dart-define-from-file=.env
```

ساخت APK با اتصال فعال:

```bash
flutter build apk --release --dart-define-from-file=.env
```

برای Build آفلاین و بدون اتصال:

```bash
flutter build apk --release
```

در ویندوز PowerShell:

```powershell
Copy-Item .env.example .env
```

## ساختار دیتابیس

Migration `20261120000000_datetime_core_records.sql` شامل موارد زیر است:

- `businesses`: مجموعه‌ها
- `business_memberships`: عضویت و مجوزهای هر کاربر در هر مجموعه
- `app_records`: داده‌های ماژول‌ها به شکل JSONB با کلید مجموعه و نوع رکورد

RLS روی تمام جدول‌ها فعال است. کاربران ناشناس دسترسی ندارند. دسترسی خواندن/نوشتن از طریق عضویت فعال و مجوزهای ذخیره‌شده در `business_memberships.permissions` کنترل می‌شود. نقش `owner` دسترسی کامل مجموعه خودش را دارد.

## احراز هویت و پروفایل

Migration `20261123203907_auth_profile_foundation.sql` جدول `profiles` را به Auth متصل می‌کند. با ایجاد هر کاربر در Supabase Auth، پروفایل پایه به‌صورت خودکار ساخته می‌شود. هر کاربر فقط پروفایل خودش را می‌خواند و ویرایش می‌کند؛ نقش و مجوزها در `business_memberships` باقی می‌مانند و از `user_metadata` برای تصمیم‌های امنیتی استفاده نمی‌شود.

برای ایجاد حساب اولیه، از Supabase Dashboard > Authentication > Users > Add user استفاده کنید و ایمیل `data@time.com` را ثبت کنید. بعد از ایجاد حساب، UUID آن را برای ساخت مجموعه و عضویت مالک استفاده کنید. رمز را در Git یا فایل `.env` قرار ندهید.

## ایجاد اولین مجموعه و عضویت مالک

ابتدا یک کاربر در Supabase Auth ایجاد کنید. سپس در SQL Editor شناسه Auth همان کاربر را جایگزین کنید:

```sql
insert into public.businesses (name, created_by)
values ('DateTime', '<AUTH_USER_UUID>')
returning id;
```

شناسه برگشتی را در دستور بعدی قرار دهید:

```sql
insert into public.business_memberships (business_id, user_id, role, permissions)
values ('<BUSINESS_UUID>', '<AUTH_USER_UUID>', 'owner', '{}'::jsonb);
```

برای افزودن کاربران دیگر و تغییر نقش/مجوزها، از مسیر مدیریتی سمت سرور یا Edge Function احراز هویت‌شده استفاده کنید؛ کلید Secret را به Flutter ندهید.

## ورود Cloud و نشست کاربر

وقتی `SUPABASE_ENABLED=true` باشد، مسیرهای مدیریتی بدون نشست معتبر به صفحه `/login` هدایت می‌شوند. ورود با ایمیل و رمز از طریق Supabase Auth انجام می‌شود؛ نشست پس از راه‌اندازی بعدی برنامه نیز بازیابی می‌شود و تغییر وضعیت ورود/خروج مسیرها را به‌روزرسانی می‌کند.

پس از ورود، برنامه جدول `business_memberships` را برای کاربر جاری می‌خواند و فقط در صورت وجود عضویت فعال با نقش `owner` اجازه ورود به پنل می‌دهد. در این مرحله نقش‌های محدود پرسنل هنوز به سیستم مجوزهای Cloud وصل نشده‌اند؛ برای جلوگیری از اعطای دسترسی ناقص، تا زمان تکمیل مرحله مجوزها اجازه ورود مدیریتی نمی‌گیرند.

- صفحه ثبت‌نام عمومی در اپ قرار داده نشده است؛ کاربرها باید از مسیر مدیریت‌شده Supabase Auth ساخته شوند.
- بازیابی رمز با `resetPasswordForEmail` ایمیل می‌فرستد. نشانی بازگشت (Site URL و Redirect URLs) را در تنظیمات Auth پروژه مطابق دامنه واقعی برنامه تنظیم کنید.
- خروج از حساب از بخش تنظیمات برنامه انجام می‌شود.
- با `SUPABASE_ENABLED=false` یا بدون تنظیمات Cloud، صفحه ورود نمایش داده نمی‌شود و حالت آفلاین `Datamonck` بدون تغییر اجرا می‌شود.
## Repository

`SupabaseRepository` عملیات عمومی Fetch/Upsert/Delete را برای ماژول‌های مجاز فراهم می‌کند. `SupabaseAuthRepository` ورود، بازیابی رمز، خروج و رویدادهای نشست را مدیریت می‌کند و `SupabaseAuthStateNotifier` عضویت Cloud را برای محافظت از Routeها بررسی می‌کند.

این زیرساخت به Provider تزریق شده است؛ Repositoryهای فعلی Mock عمداً پیش‌فرض باقی مانده‌اند تا داده‌های آزمایشی و اجرای آفلاین از بین نروند. مهاجرت هر ماژول به Remote باید مرحله‌ای انجام شود و تنها پس از اضافه شدن نگاشت مدل، تست RLS و راهبرد Cache/Sync آن ماژول فعال شود.
