# Документация NorthernLab

Документы описывают текущие сцены и код. Проектные намерения вынесены в раздел «Игровая концепция» и не обозначают готовые механики. История изменений хранится в Git; даты отдельных правок не используются как признак актуальности документа.

## Руководства

- [Состояние проекта](project_status.md).
- [Запуск, зависимости и сборка](guides/getting_started.md).
- [Проверки экспорта и запускателя](technical/export_build_checks.md).
- [Версия для тестеров: установщик и portable](guides/distributing_playtest.md).
- [Оптимизация тестовой поставки](technical/playtest_optimization.md).
- [Управление и проверка игрового маршрута](guides/playtesting.md).
- [Автотесты и ручные проверки](guides/testing.md).
- [Правила разработки и обновления документации](guides/contributing.md).
- [Имена, размещение и переименование файлов](guides/naming.md).
- [Оптимизация и размещение файлов: рабочие правила](guides/optimization_and_file_layout.md).
- [Результат проверки перед Git — 13 октября 2026](reviews/2026_10_13_pre_git.md).
- [Состояние, документация и производительность — 15 октября 2026](reviews/2026_10_15_project_review.md).
- [Проверка объединения обновлений — 15 октября 2026](reviews/2026_10_15_merge_check.md).

## Устройство игры

- [Архитектура и ответственность систем](architecture.md).
- [Игровая концепция](design/game_concept.md).
- [Уровни и планировка](design/levels.md).
- [Состояние базы, дни и питание](technical/base_gameplay_state.md).
- [Обслуживание электросистемы](technical/maintenance.md).
- [Второй день: ключ шифрования](technical/day_two_slice.md).
- [Лабораторный кликер](technical/lab_clicker.md).
- [Сохранения и совместимость](technical/save_system.md).
- [Steam и репликация](technical/steam_networking.md).
- [Вертолёт и начало экспедиции](technical/helicopter_lobby.md).
- [Лифт](technical/elevator.md).
- [Пещера дня 7 и нижняя долина](technical/cave_environment.md).

## Игровые механики

- [Детали, сборка и стрельба огнемёта](technical/flamethrower_crafting.md).

- [Игрок, движение и ввод](technical/player.md).
- [Персонажи, анимация и ragdoll](technical/character_visuals.md).
- [Предметы и взаимодействие](technical/item_system.md).
- [Инвентарь](technical/equipment_inventory.md).
- [Фонарик](technical/flashlight.md).
- [Оружие и боеприпасы](technical/weapons.md).
- [Монстры и ИИ](technical/containment.md).
- [Перенос тела и медицинские койки](technical/corpse_recovery.md).
- [Здоровье, смерть и радиация](technical/survival.md).
- [Двери](technical/interactive_door.md).
- [Контейнер растений и ежедневный полив](technical/base_gameplay_state.md#контейнер-растений-и-ежедневный-полив).
- [Снегоход и гараж](technical/garage_snowmobile.md).
- [Настройка объектов в Inspector](technical/inspector_gameplay_tuning.md).
- [Консоль разработчика](technical/developer_console.md).

## Интерфейс, звук и окружение

- [Главное меню, Esc и лобби](technical/menus.md).
- [Игровой HUD](technical/northern_lab_hud.md).
- [Проверка обновления меню и освещения](technical/menu_lighting_qa.md).
- [Обратная связь тестеров и GitHub](technical/tester_feedback.md).
- [Журнал и анимация](technical/journal_presentation.md).
- [Иллюстрации журнала](technical/journal_illustration_style.md).
- [Звук и акустика](technical/audio_mix.md).
- [Графика и пользовательские настройки](technical/settings.md).
- [Освещение мира и отладочная видимость](technical/world_lighting.md).
- [Источники света и их назначение](technical/lighting_sources.md).
- [Проверка света, новая расстановка и очистка скриптов](technical/lighting_audit_2026_10_22.md).
- [Снежное окружение и следы](technical/snow_exterior.md).
- [Скалистый обрыв](technical/east_cliff_revision.md).
- [Следы пуль](technical/bullet_surface_marks.md).
- [Подготовка моделей и текстур](technical/art_pipeline.md).
- [Модели снаряжения и генератора](technical/item_models.md).
- [Оптимизация и измерения](technical/project_optimization.md).
- [Ревизия оптимизации от 19 октября](technical/optimization_2026_10_19.md).
- [Доработки игровой логики от 19 октября](technical/runtime_polish_2026_10_19.md).
- [Контрольный замер окружения](technical/performance_baseline.md).
- [Версия игры](technical/game_version.md).

## Как читать справочники

«Поведение» описывает правила игры. «Настройка» указывает сцену или ресурс для редактирования. «Проверка» содержит воспроизводимые действия или существующий тест. Ограничения описываются отдельно. Числовые значения в таблицах — текущие настройки, а не обязательный баланс для будущих обновлений.

- [Радиовышка, замок, лестница и ландшафт с высоты](technical/radio_tower.md).

## Технические материалы

- [Завершение архитектурного прохода — 14.11.2026](technical/architecture_completion_2026_11_14.md).
- [Оболочка базы и освещение — 06.11.2026](technical/base_exterior_rebuild.md).
- [Каталожные двери базы](technical/catalog_doors.md).
- [Калибровка экрана и HUD](technical/display_calibration.md).
- [Graphics settings documentation audit — 2026-11-19](technical/graphics_settings_audit_2026_11_19.md).
- [Наружный свет и изоляция помещений — 06.11.2026](technical/interior_daylight.md).
- [Фон главного меню](technical/menu_background.md).
- [Экипировка и границы ответственности — 14.11.2026](technical/player_equipment_architecture_2026_11_14.md).
- [Сетевые снимки персонажа — 14.11.2026](technical/player_replication_architecture_2026_11_14.md).
- [Архитектура: запасы игрока — 14.11.2026](technical/player_supplies_architecture_2026_11_14.md).
- [Операции запасов игрока — 14.11.2026](technical/player_supplies_operations_2026_11_14.md).
- [Полярный дневной свет и метель — 15.11.2026](technical/polar_daylight_2026_11_15.md).
- [Общая композиция полярной локации — 11.11.2026](technical/polar_location_2026_11_11.md).
- [Текущий вариант: вода и семь ледяных образований](technical/polar_lowland_2026_11_11.md).
- [Разломы, ручей и грубый лёд — 11.11.2026](technical/polar_waterways_2026_11_11.md).
- [Очистка и рефакторинг NorthernLab — 14.11.2026](technical/refactor_cleanup_2026_11_14.md).
- [Vulkan / Direct3D 12 и загрузка ресурсов — 14.11.2026](technical/render_loading_investigation_2026_11_14.md).
- [Смягчение наружного света и сугробов — 11.11.2026](technical/soft_snow_lighting_2026_11_11.md).

## Отчёты по датам

- [Проверка обращений NorthernLab от 28–30 октября](reviews/2026_10_30_feedback_fixes.md).
- [Второй набор исправлений обратной связи](reviews/2026_10_30_feedback_followup.md).
- [Локальные доработки щитка, задач и журнала](reviews/2026_10_30_feedback_local.md).
- [Звуки интерфейса, радиации, сигнализация и CSG-лампы](reviews/2026_10_31_audio_and_lamps.md).
