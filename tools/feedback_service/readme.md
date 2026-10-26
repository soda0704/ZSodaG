# Подключение обратной связи к GitHub

Сервис предназначен для Cloudflare Workers: отдельный сервер/включённый компьютер не нужен. Тестеры пользуются формой игры; GitHub и аккаунты им не нужны. Команда читает Issues в закрытом репозитории.

**Подключено 13 октября 2026 года.** Сервис размещён в Cloudflare Workers; `GITHUB_TOKEN` задан как секрет окружения Production. Игра сохраняет ZIP и отправляет отчёт по HTTPS.

- Репозиторий: закрытый [`soda0704/NorthernLab-feedback`](https://github.com/soda0704/NorthernLab-feedback), Issues включены, ветка `main`.
- Endpoint: `https://northernlab-feedback.denserbinlol.workers.dev/reports` — записан в `assets/config/tester_feedback.tres`.
- Проверка сервиса: [`/health`](https://northernlab-feedback.denserbinlol.workers.dev/health).
- Windows-сборка пересобрана: `build/windows-dev/NorthernLab.exe`.
- GitHub-токен ограничен репозиторием отчётов; текущий срок действия — до **12 ноября 2026 года**. До истечения замените секрет.
- Приглашение `xDiR0` отправлено; на момент настройки ожидает принятия. Проверка ссылок под аккаунтом коллеги остаётся после принятия приглашения.

Настоящая доставка проверена: [тестовый Issue №1](https://github.com/soda0704/NorthernLab-feedback/issues/1) содержит JSON и PNG. Форма Godot отправила отчёт через размещённый Worker; после намеренной потери первого ответа повтор и загрузка прежнего ZIP вернули тот же `report_id` без второго Issue. Отдельно прошла прямая HTTPS-отправка из Godot по адресу из ресурса игры. Ссылки на файлы проверены под аккаунтом владельца. Локальные проверки: 5 тестов Worker и 12 проверок доставки Godot — без ошибок проверок.

После перевыпуска GitHub-токена настройка повторно проверена: Wrangler показывает `GITHUB_TOKEN` с типом `secret_text`; новый отчёт создал [Issue №2](https://github.com/soda0704/NorthernLab-feedback/issues/2) с JSON и PNG, повторы вернули ту же квитанцию. Два тестовых Issue относятся к двум разным отчётам, дубликатов при повторе нет.

## Однократная настройка владельцем (для повторного размещения)

1. Создайте **закрытый** репозиторий, например `NorthernLab-feedback`, включите Issues, добавьте README для создания ветки `main`, пригласите коллег. Это хранилище отчётов, без исходников игры.
2. Создайте fine-grained GitHub token с доступом **только к этому репозиторию**: `Issues: Read and write`, `Contents: Read and write`, `Metadata: Read-only`. Задайте срок действия и следите за обновлением. Токен вводится в секрет сервиса: не присылайте его в чат, не добавляйте в `.tres`, Git или сборку.
3. Войдите в Cloudflare. На компьютере размещения нужны Node.js и npm. В `tools/feedback_service/wrangler.toml` задайте `GITHUB_REPOSITORY = "owner/NorthernLab-feedback"` и нужную ветку. Из этой папки выполните:

   ```powershell
   npx wrangler login
   npx wrangler deploy
   npx wrangler secret put GITHUB_TOKEN
   ```

   Последняя команда запрашивает токен интерактивно; секрет не попадает в аргументы или историю команд. До его добавления endpoint отвечает ошибкой настройки.

4. В Godot откройте **`assets/config/tester_feedback.tres`** и задайте **Endpoint**: `https://<выданный-адрес-Worker>/reports`. Сохраните ресурс и пересоберите игру. `/health` отвечает без раскрытия конфигурации, но не проверяет доступ к GitHub.
5. Отправьте тестовый отчёт: должны появиться Issue, JSON и PNG. Проверьте ссылки под аккаунтом коллеги и повтор при потере сети. Это обязательная проверка настоящего подключения.

Правила: [GitHub tokens](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens), [Cloudflare secrets](https://developers.cloudflare.com/workers/configuration/secrets/), [Durable Objects SQLite](https://developers.cloudflare.com/durable-objects/reference/durable-objects-migrations/), [лимит обращений](https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/). Тариф и лимиты Cloudflare проверяются при размещении; бесплатность при любой нагрузке не обещается.

## Устройство

`POST /reports`: multipart `report` (JSON) + необязательный `screenshot` (PNG). Предел тела — 16 МБ, JSON — 128 КБ. Сервер задаёт репозиторий/ветку, проверяет размер фактически прочитанного тела, поля и изображение. Клиент не выбирает чужой репозиторий.

Durable Object хранит квитанцию и отпечаток по ID отчёта. Повтор не дублирует Issue; несовпадающее содержимое возвращает 409. Неоднозначный ответ GitHub восстанавливается проверкой файлов и Issue с маркером. Ответы игры не раскрывают секреты/тексты ошибок GitHub.

Файлы находятся в `reports/<report_id>/`. Issue содержит описание, шаги, контекст и ссылки. Доступ к закрытым файлам имеют приглашённые коллеги; inline-превью скриншота не требуется для доставки.

Endpoint публичный, без аккаунта тестера. Лимит IP не заменяет защиту массового открытого сервиса. Не выдавайте токену доступ к репозиторию игры. При росте тестирования понадобятся проверка отправителя, бюджет и политика хранения.

## Локальная проверка

Из корня игрового проекта:

```powershell
node --test tools/feedback_service/worker.test.mjs
node tools/tests/run_tester_feedback_delivery.mjs
```

GitHub подменяется; реальный HTTP-запрос делает Godot, сервер выполняет рабочий Worker. Внешних публикаций нет. Проверки не подтверждают размещение в Cloudflare.

Окружение Workers можно проверить через `npx wrangler dev`. Локальные секреты задаются в `.dev.vars`, исключённом из Git. HTTP localhost разрешён только в редакторной сборке Godot; экспортированная игра требует HTTPS.
