# Сборка на GitHub Actions — без своего Mac

Сценарий `.github/workflows/ios.yml` работает на macOS-машинах GitHub:

- **на каждый push** — собирает ядра (`Libbox.xcframework`: sing-box + Xray + mihomo + мосты Tor), генерирует
  Xcode-проект, собирает все цели (приложение, VPN-расширение, виджет) и прогоняет тесты на симуляторе iPhone.
  Подпись и секреты не нужны. Это и есть проверка, что Swift-код компилируется;
- **по кнопке** «Run workflow» с галочкой «Подписать и загрузить в TestFlight» — то же, а затем сборка для App Store
  с автоматической подписью и загрузка в TestFlight. Ставите приложение на iPhone через приложение TestFlight —
  ни Mac, ни кабель не нужны.

## 1. Репозиторий

1. На github.com → **New repository**. Имя любое, например `slmtune-ios`. Ничего не добавляйте (без README и лицензии).
   - **Public** — минуты macOS бесплатны и не ограничены. Код и так под GPL-3.0.
   - **Private** — 2000 бесплатных минут в месяц, но минута macOS считается за 10: выйдет ~200 минут, это 3–5 полных
     сборок (первая — дольше, потом ядра берутся из кэша).
2. Отправьте код (адрес — с кнопки **Code** на странице репозитория):
   ```bash
   git remote add origin https://github.com/<вы>/slmtune-ios.git
   git push -u origin main
   ```
   При первом push Git для Windows откроет браузер для входа в GitHub.
3. Вкладка **Actions** → запуск «iOS». Первый раз — 40–70 минут (сборка ядер), потом 15–25.
   Если упадёт — откройте шаг с ошибкой, лог сборки лежит в артефакте `build-log`.

## 2. TestFlight (нужен платный Apple Developer, $99/год)

### В Apple Developer (developer.apple.com → Certificates, Identifiers & Profiles → Identifiers)

Xcode с ключом API умеет создать всё сам, но надёжнее один раз руками:

1. **App Groups** → `+` → `group.<префикс>`, например `group.ru.vasya.slmtune`.
2. **App IDs** → `+` → App → Bundle ID `ru.vasya.slmtune` (это ваш `BUNDLE_PREFIX`; должен быть уникальным во всём
   App Store) с возможностями **App Groups**, **Network Extensions**, **Access Wi-Fi Information**.
3. Ещё два App ID: `ru.vasya.slmtune.PacketTunnel` (те же три возможности) и `ru.vasya.slmtune.Widget`
   (**App Groups**, **Network Extensions**). У каждого в App Groups отметьте свою группу.

### В App Store Connect (appstoreconnect.apple.com)

4. **Apps** → `+` → **New App**: платформа iOS, имя (если «SLMtune» занято — «SLMtune VPN»), язык русский,
   Bundle ID из шага 2, SKU — любое слово.
5. **Users and Access** → **Integrations** → **App Store Connect API** → **Team Keys** → `+`. Роль **Admin**
   (нужна, чтобы GitHub мог выпустить сертификат подписи). Скачайте `AuthKey_XXXXXXXXXX.p8` — **скачать можно только
   один раз**. Запишите **Key ID** и **Issuer ID** (над списком ключей).
6. Ваш **Team ID**: developer.apple.com → Account → Membership details (10 символов).

### В GitHub (репозиторий → Settings → Secrets and variables → Actions)

7. Вкладка **Secrets** → New repository secret:
   - `ASC_KEY_ID` — Key ID;
   - `ASC_ISSUER_ID` — Issuer ID;
   - `ASC_KEY_P8_BASE64` — файл ключа в base64. В PowerShell:
     ```powershell
     [Convert]::ToBase64String([IO.File]::ReadAllBytes("$HOME\Downloads\AuthKey_XXXXXXXXXX.p8")) | Set-Clipboard
     ```
     (результат уже в буфере — вставьте в поле).
8. Вкладка **Variables** → New repository variable:
   - `TEAM_ID` — Team ID;
   - `BUNDLE_PREFIX` — `ru.vasya.slmtune`;
   - `APP_GROUP` — `group.ru.vasya.slmtune`.

### Сборка и установка

9. **Actions** → **iOS** → **Run workflow** → отметьте «Подписать и загрузить в TestFlight» → Run.
10. Через 5–15 минут после зелёной галочки сборка появится в App Store Connect → ваше приложение → **TestFlight**.
    Первый раз ответьте на вопрос о шифровании (приложение использует стандартное шифрование: TLS, QUIC, WireGuard).
11. TestFlight → **Internal Testing** → `+` группа → добавьте себя (тот же Apple ID). Внутреннее тестирование не
    требует проверки Apple.
12. На iPhone поставьте **TestFlight** из App Store, примите приглашение — и устанавливайте SLMtune. Каждая следующая
    сборка придёт туда же обновлением (сборка TestFlight живёт 90 дней).

## Безопасность

- Ключ `.p8` даёт управление вашим аккаунтом разработчика: храните только в Secrets GitHub, в репозиторий не кладите.
  Если ключ утёк — отзовите его в App Store Connect (Revoke) и сделайте новый.
- Секреты не попадают в логи и в сборки из чужих pull request'ов.
