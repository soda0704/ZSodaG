# Проверки проекта

## Подготовка

Запускайте из корня проекта локальный GodotSteam после импорта ресурсов. На Windows используйте PowerShell. Тесты находятся в `tools/tests`; в таблице приведены действующие файлы, а не прежние имена проверок.

```powershell
$godotExe = '.\tools\.local\godotsteam-editor\godot.exe'
& $godotExe --headless --path . --editor --import
& $godotExe --headless --path . --script res://tools/tests/project_resource_audit.gd
& $godotExe --headless --path . --script res://tools/tests/day_split_checkpoint_regression.gd
```

Ожидается успешное завершение и итог без ошибок. Часть старых тестов печатает `RESULT []`, новые — `RESULT FAILURES 0`. Проверяйте весь лог на `SCRIPT ERROR`, `ERROR` и `FAIL`, а не только последнюю строку. `project_resource_audit` проверяет существование зависимостей; это не загрузка каждой сцены и не проверка динамических имён ресурсов.

Перед новым тестом, загружающим базу, назначьте отдельный `northern_lab/testing/base_save_path`. Тест не должен читать, удалять или записывать файлы обычной экспедиции. Не запускайте одинаковую проверку одновременно: несколько тестов имеют фиксированный тестовый путь.

## Автоматические проверки

| Область | Файлы в `tools/tests/` |
| --- | --- |
| Ресурсы | `project_resource_audit.gd` |
| Модели предметов и батарейки | `item_models_regression.gd` |
| Персонажи и физический скелет | `character_integration_regression.gd`, `character_visual_review.gd`, `run_character_multiplayer.gd` |
| Дни и checkpoint | `day_split_checkpoint_regression.gd` |
| Респавн и консоль | `respawn_debug_controls_regression.gd` |
| Бег и ускорение | `sprint_boost_regression.gd` |
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

## Графические проверки

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
