# Документация NorthernLab

Документы описывают текущие сцены и код. Проектные намерения вынесены в раздел «Игровая концепция» и не обозначают готовые механики. История изменений хранится в Git; даты отдельных правок не используются как признак актуальности документа.

## Руководства

- [Состояние проекта](PROJECT_STATUS.md).
- [Запуск, зависимости и сборка](guides/getting_started.md).
- [Управление и проверка игрового маршрута](guides/playtesting.md).
- [Автотесты и ручные проверки](guides/testing.md).
- [Правила разработки и обновления документации](guides/contributing.md).

## Устройство игры

- [Архитектура и ответственность систем](architecture.md).
- [Игровая концепция](design/game_concept.md).
- [Уровни и планировка](design/levels.md).
- [Состояние базы, дни и питание](technical/base_gameplay_state.md).
- [Обслуживание электросистемы](technical/maintenance.md).
- [Второй день: ключ шифрования](technical/day_two_slice.md).
- [Сохранения и совместимость](technical/save_system.md).
- [Steam и репликация](technical/steam_networking.md).
- [Вертолёт и начало экспедиции](technical/helicopter_lobby.md).
- [Лифт](technical/elevator.md).

## Игровые механики

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
- [Снегоход и гараж](technical/garage_snowmobile.md).
- [Настройка объектов в Inspector](technical/inspector_gameplay_tuning.md).
- [Консоль разработчика](technical/developer_console.md).

## Интерфейс, звук и окружение

- [Журнал и анимация](technical/journal_presentation.md).
- [Иллюстрации журнала](technical/journal_illustration_style.md).
- [Звук и акустика](technical/audio_mix.md).
- [Графика и пользовательские настройки](technical/settings.md).
- [Снежное окружение и следы](technical/snow_exterior.md).
- [Скалистый обрыв](technical/east_cliff_revision.md).
- [Следы пуль](technical/bullet_surface_marks.md).
- [Подготовка моделей и текстур](technical/art_pipeline.md).
- [Модели снаряжения и генератора](technical/item_models.md).
- [Оптимизация и измерения](technical/project_optimization.md).
- [Контрольный замер окружения](technical/performance_baseline.md).
- [Версия игры](technical/game_version.md).

## Как читать справочники

«Поведение» описывает правила игры. «Настройка» указывает сцену или ресурс для редактирования. «Проверка» содержит воспроизводимые действия или существующий тест. Ограничения описываются отдельно. Числовые значения в таблицах — текущие настройки, а не обязательный баланс для будущих обновлений.
