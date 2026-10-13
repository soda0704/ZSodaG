# Проверки проекта

## Обратная связь тестеров

`tester_feedback_regression.gd` проверяет форму, ZIP/JSON/PNG, черновик, диагностику и возврат в игру; `--capture` добавляет графическую проверку снимка без меню и UI при 720p. `node --test tools/feedback_service/worker.test.mjs` проверяет сервис, а `node tools/tests/run_tester_feedback_delivery.mjs` проводит реальный HTTP-запрос из Godot через Worker с подменённым GitHub, включая повтор, timeout и неверные квитанции. [Подключение и ограничения](../technical/tester_feedback.md). Размещённый сервис и настоящий GitHub проверяются отдельно после настройки.

## Подготовка

Запускайте из корня проекта локальный GodotSteam после импорта ресурсов. На Windows используйте PowerShell. Тесты находятся в `tools/tests`; в таблице приведены действующие файлы, а не прежние имена проверок.

```powershell
$godotExe = '.\tools\.local\godotsteam-editor\godot.exe'
& $godotExe --headless --path . --editor --import
& $godotExe --headless --path . --script res://tools/tests/project_resource_audit.gd
& $godotExe --headless --path . --script res://tools/tests/day_split_checkpoint_regression.gd
```

Ожидается успешное завершение и итог без ошибок. Часть старых тестов печатает `RESULT []`, новые — `RESULT FAILURES 0`. Проверяйте весь лог на `SCRIPT ERROR`, `ERROR` и `FAIL`, а не только последнюю строку. `project_resource_audit` проверяет существование зависимостей; это не загрузка каждой сцены и не проверка динамических имён ресурсов.

Перед новым тестом, загружающим базу, назначьте отдельный `northern_lab/testing/base_save_path` либо `northern_lab/testing/save_slots_root` для тестирования слотов. Тест не должен читать, удалять или записывать файлы обычной экспедиции. Не запускайте одинаковую проверку одновременно: несколько тестов имеют фиксированный тестовый путь.

## Автоматические проверки

| Область | Файлы в `tools/tests/` |
| --- | --- |
| Ресурсы | `project_resource_audit.gd` |
| Меню Menu, ESC_MENU, LOBBY_MENU и применение настроек | `menu_integration_regression.gd` (для визуальной проверки без `--headless`, с `-- --capture`) |
| Модели предметов и батарейки | `item_models_regression.gd` |
| Персонажи и физический скелет | `character_integration_regression.gd`, `character_visual_review.gd`, `run_character_multiplayer.gd`, `character_skin_selection_regression.gd`, `character_accessory_fit_regression.gd`, `character_model_integrity_regression.gd`, `character_idle_stability_regression.gd`, `character_view_isolation_regression.gd` |
| Дни и checkpoint | `day_split_checkpoint_regression.gd` |
| Солнечный резерв лифта, предохранитель и продолжение | `elevator_backup_power_regression.gd` |
| Поездки, двери и пассажиры лифта | `elevator_reliability_regression.gd`, `run_elevator_multiplayer.py` |
| Респавн и консоль | `respawn_debug_controls_regression.gd`, `debug_free_camera_regression.gd` |
| Бег и ускорение | `sprint_boost_regression.gd` |
| Рывки собственных рук при разном FPS | `first_person_frame_pacing_regression.gd` (графический запуск) |
| ИИ и Inspector | `monster_inspector_ai_regression.gd` |
| Медицинский перенос | `medical_corpse_recovery_regression.gd` |
| Журнал | `journal_presentation_regression.gd` |
| Оружие, машина, звук | `weapon_vehicle_audio_regression.gd`, `audio_balance_startup_regression.gd` |
| Новые звуки и музыка | `expanded_audio_regression.gd`, `background_music_regression.gd` |
| Акустика и графика | `acoustic_portal_regression.gd`, `audio_graphics_regression.gd` |
| Снегоход | `snowmobile_model_recovery_regression.gd`, `snowmobile_driving_tracks_regression.gd` |
| Пулевые следы | `bullet_surface_marks_regression.gd` |
| Двери и прибытие | `door_arrival_regression.gd` |
| Направление следов | `snow_track_heading_regression.gd` |
| Окружение | `snow_expansion_test.gd`, `landscape_grounding_test.gd`, `valley_grounding_regression.gd`, `south_forest_cliff_regression.gd`, `world_boundary_regression.gd` |

Запускайте профильный набор после изменения системы. Базовые условия не нужно прогонять повторно без новых изменений или нерешённой ошибки.

Ручная проверка дружественного огня проводится вдвоём без `/god` и отладочного полёта, вне радиации и падений. При исходных 100 здоровья одиночное попадание пистолета должно оставить 65, M4A1 — 75, ножа в пределах 2 м — 50. Повторите атаку в обе стороны, чтобы проверить действие хоста и запрос клиента. Затем проверьте препятствие перед целью: патрон расходуется, здоровье напарника не меняется. Завершите сценарий смертельным уроном и обычным возрождением; наблюдайте здоровье и смерть на компьютере пострадавшего. Эти значения относятся к текущему балансу сцены оружия, а не к отдельным правилам для команды.

Проверка лифта в двух процессах запускается через `python tools/tests/run_elevator_multiplayer.py`. Для приближения к нестабильному соединению: `python tools/tests/run_elevator_multiplayer.py --latency-ms 80 --loss 0.05 --client-fps 30`. Задержка указана в одну сторону (примерно 160 мс round-trip), jitter составляет ±25%, потеря — доля UDP-пакетов. Логи находятся в `tools/.local/elevator-network-*.log`. Используется production-код через ENet; для Steam нужны две учётные записи на двух компьютерах с одинаковой обновлённой сборкой. При исчезновении процесса без доставленного сообщения о выходе тест ждёт обнаружения разрыва транспортом.

`debug_free_camera_regression.gd` проверяет отделение и возврат камеры, блокировку управления телом, скорость и видимость обоих персонажей. Без `--headless` также сохраняет снимки в `tools/.local/freecam-variant-0.png` и `freecam-variant-1.png`. Для проверки на двух реальных ENet-процессах запустите в разных терминалах тот же скрипт с `-- --host` и `-- --client` (порт 28753). Хост допускает `--headless`; клиент требует графический запуск для проверки захвата мыши и реального полёта.

## Графические проверки

Для проверки рывков рук: `& $godotExe --path . --script res://tools/tests/first_person_frame_pacing_regression.gd`. Для собственного viewmodel настоящего сетевого клиента запустите `run_character_multiplayer.gd` в двух графических процессах: хост с `-- --presentation-clock --host --port=28756`, клиент с `-- --presentation-clock --port=28756`. Проверка использует production-персонажей и ENet, без чтения или записи сохранения экспедиции.

`character_accessory_fit_regression.gd` проверяет пропорции кепок, контакт чашек наушников с головой, высоту лямок Tactical и сохранение креплений при поворотах, взгляде вверх/вниз, ходьбе, беге и приседании. Графический запуск сохраняет крупные кадры спереди, сбоку и сзади в `tools/.local/accessory-fit/`, включая жилет в движении. Осмотрите эти кадры: успешные численные проверки сами по себе не обнаруживают все пересечения одежды. Headless проверяет только геометрию и трансформации.

`character_model_integrity_regression.gd` сравнивает число вершин и треугольников с исходными glTF, включая отдельные нескелетные детали и документированный перенос перчаток. Проверяет исходные UV глаз Military, их положение в глазницах, сохранение жёсткой формы наколенников и контакт реальных подошв с физическим полом через production AnimationTree. Проверяются покой, приседание, ходьба вперёд/назад/вбок, бег, движение в приседе, журнал и отсутствие прилипания ног в воздухе. Графические крупные кадры глаз и стоп, а также полный рост сохраняются в `tools/.local/model-integrity/` и требуют осмотра.

`character_idle_stability_regression.gd` проверяет движение таза, бёдер, коленей и стоп по всем трём осям через два полных цикла idle. Используются обе модели, production AnimationTree с пустыми руками, пистолетом и винтовкой, возврат после ходьбы, а также прямое проигрывание клипа, как в выборе скина. Допускается меньше 1 мм движения нижней части тела; лёгкое дыхание проверяется отдельно. Графический запуск сохраняет последовательности кадров в `tools/.local/idle-stability/`. Проверка одной высоты подошв не обнаруживает раскачивание ног по горизонтали.

`character_view_isolation_regression.gd` проверяет, что внешняя камера с обычной маской всех слоёв не рисует owner FP-геометрию. Проверяются мгновенный переход в осмотр, оружие и журнал, возврат к камере игрока, переключение на другую камеру без специального флага, настоящая freecam и восстановление после смерти. Свечение игровых Light3D сохраняется при скрытии геометрии рук. Крупные кадры обеих моделей сохраняются в `tools/.local/view-isolation/`. Для внешних кадров используйте `set_external_view(true)`, а не изменение приватного `_local` или однократное скрытие оверлея.

Проверка трансформаций MultiMesh требует реального рендерера; headless не заменяет её. `landscape_grounding_test` запускайте без `--headless`. Другие проверки окружения с чтением MultiMesh также выполняйте графически.

```powershell
& $godotExe --path . --script res://tools/tests/landscape_grounding_test.gd
& $godotExe --path . --script res://tools/tests/medical_corpse_recovery_regression.gd
```

Графический медицинский тест проверяет нажатие E с захватом мыши; headless проверяет серверное действие другим способом. Журнал, швы обрыва, прозрачные текстуры, баланс звука и HDR требуют осмотра/прослушивания.

## Совместный сценарий

Два разных аккаунта запускают одинаковую Windows-сборку через Steam. Последовательно проверить:

1. Создание лобби, вход по ID, готовность и высадку.
2. Подбор клиентом, расход батарейки, выстрел и перезарядку.
3. Питание, ручную дверь, лифт с двумя пассажирами и поздний вход во время поездки.
4. Сон, ключ второго дня и доступ уровней 2/3 в разные дни.
5. Тело на плече, койку, смерть и отключение носильщика.
6. Снегоход, запуск без тяги, ускорение и совместные ворота.
7. Выход, продолжение кооператива и отсутствие дублированных предметов.

Автотесты не моделируют внешний Steam P2P, потерю пакетов или собственное приглашение из Playtest. Подробности ограничений: [сеть](../technical/steam_networking.md).

Для персонажей предусмотрен запуск двух процессов HOST + CLIENT через ENet с действующими игровыми RPC. Он проверяет обе перестановки моделей, движения, оружие, журнал, физические позы после смерти и возрождение. Этот тест выполняется графически; команды и границы проверки описаны в [устройстве персонажей](../technical/character_visuals.md).

## Сборка и документация

После изменения импорта или экспортных фильтров соберите Windows Dev и проверьте запуск EXE. После правки документации выполните:

```powershell
python tools/check_documentation.py
```

Проверка ссылок не доказывает правильность описания поведения; это подтверждается кодом и профильным сценарием.

## Слоты и полное продолжение

```powershell
& $godotExe --headless --path . --script res://tools/tests/expedition_save_slots_regression.gd
& $godotExe --headless --path . --script res://tools/tests/expedition_resume_regression.gd
& $godotExe --path . --script res://tools/tests/expedition_menu_regression.gd -- --capture
python tools/tests/run_expedition_multiplayer.py
```

Тесты назначают изолированные каталоги до загрузки базы и не читают игровые файлы пользователя. Проверяются разные компании, две точки отката без накопления ручных сейвов, ошибки и повреждение записи, миграция, сон, загрузка настоящей базы и сетевого клиента. В графическом тесте кадры сохраняются в `tools/.local/expedition-menu-*.png`. Реальный Steam ID и транспорт отдельно проверяются двумя аккаунтами на разных компьютерах по [правилам сохранений](../technical/save_system.md).

## Механический щит и 3D-проводка

```powershell
& $godotExe --headless --path . --script res://tools/tests/breaker_wiring_regression.gd
& $godotExe --path . --script res://tools/tests/breaker_wiring_regression.gd -- --capture
python tools/tests/run_expedition_multiplayer.py --wiring
```

Проверяются физические контакты и настоящий ввод мыши, неверное соединение, четыре правильных пары, выход без открытия меню, сохранение в открытом ремонте и продолжение, ограничения по дистанции, состоянию персонажа и видимости. Крышка должна оставаться закрытой до E, открываться на петлях и закрываться после выхода; нижняя опора рукояти неподвижна. Сетевой тест проверяет подтверждение клиентских RPC, позднее подключение к частичному ремонту, конкурентный выбор одного провода и возврат камеры при включении питания напарником. Кадры находятся в `tools/.local/breaker-*.png`; ручное прохождение обоими участниками через Steam остаётся отдельной проверкой.

## Терминалы второго дня

```powershell
& $godotExe --headless --path . --script res://tools/tests/day_two_terminal_regression.gd
& $godotExe --path . --script res://tools/tests/day_two_terminal_regression.gd -- --capture
python tools/tests/run_expedition_multiplayer.py --terminal
```

Проверяются два authored-экземпляра и UI-материалы, физический луч взаимодействия, запрет действия для мёртвого/спящего и удалённого игрока, препятствие, маршрут ключа, нативные клипы, основной щит и резерв лифта, загрузка без повторного проигрывания события, текст третьего дня. Сетевой запуск использует production-базу и персонажей; ключ извлекает напарник, сдаёт хост. Графический запуск проверяет настоящий shader и создаёт кадры на обычной высоте персонажа.

## Бак, заправка и стрелочный указатель

```powershell
& $godotExe --headless --path . --script res://tools/tests/fuel_station_regression.gd
& $godotExe --path . --script res://tools/tests/fuel_station_regression.gd -- --capture
python tools/tests/run_expedition_multiplayer.py --wiring
```

Проверяются настоящий луч E, полный/частичный/пустой объём канистры, переполнение бака с сохранением остатка, отсутствие подсказки без подходящего предмета, запрет переливания из-за стены, вдали, во сне и после смерти, сохранение топлива и позы стрелки, расход генератора и труба в пол. Графические кадры — `tools/.local/fuel-*.png`. Headless не захватывает курсор: в нём проверяется содержимое контекстного значка, а видимость Label проверяется графическим запуском. Сетевой прогон проверяет клиентский production-ввод E, репликацию остатка, стрелки и единый checkpoint бака/канистры. На двух компьютерах через Steam повторить заправку и совместный ремонт; обходить бак и открытую крышку для визуальной проверки монтажа.
