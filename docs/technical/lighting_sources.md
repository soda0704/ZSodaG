# Источники света и переключение качества

## Команды

`/light_swap` переключает обычный и продвинутый режим освещения. Для явного выбора: `/light_swap basic` и `/light_swap advanced`. При каждом запуске включён продвинутый режим, включая первый запуск на новом компьютере. Обычный включается только явной командой до закрытия игры. Выбор действует локально, сохраняется при смене игровых сцен в пределах запуска и не записывается в сохранение или настройки графики. В кооперативе команда не отправляется хосту.

Продвинутый режим возвращает эффекты, разрешённые авторским окружением и пользовательскими настройками. Если SSAO, объёмный туман или Bloom выключены в настройках, команда их принудительно не включает.

| Параметр | Обычный режим | Продвинутый режим |
| --- | --- | --- |
| Прямой свет ламп, солнца, фонариков и эффектов | Работает | Работает |
| Цвет, энергия и положение источников | Авторские | Авторские |
| Тени | Сохранены, атласы 2048 и минимальная фильтрация | По настройкам графики, атласы до 4096 |
| Максимальная дальность солнечных теней | Ограничена 48 м и пользовательской настройкой | По настройке, до 96 м |
| VoxelGI — непрямой свет | Отключён, данные отсоединяются от GPU-объёмов | Подключаются зоны текущего и приближающегося этажа |
| SSAO — затемнение мелких стыков | Выключено | По авторским и пользовательским настройкам |
| Объёмный туман — рассеивание света в воздухе | Выключен | По авторским и пользовательским настройкам |
| Glow/Bloom — ореолы ярких поверхностей | Выключен | По авторским и пользовательским настройкам |
| Обычная дальняя дымка, ambient, отражение неба | Сохранены | Сохранены |
| SSR, SSIL, SDFGI | Выключены | Выключены, как и до добавления команды |

Под крышей WorldLighting дополнительно сокращает солнечные тени до 24 м. Настройки разрешения, сглаживания, текстур, яркости и гаммы эта команда не переключает. Она также не меняет питание базы и состояние оборудования. Сохраняются прямые тени дверей и перекрытий.

Связь функций:

- `scripts/ui/developer_console.gd::_execute_light_swap()` разбирает команду до ветки серверных RPC; команда есть в `/help` и автодополнении.
- `scripts/ui/graphics_quality.gd::set_advanced_lighting_enabled()` применяет выбранный режим; `toggle_lighting_mode()` меняет его на противоположный.
- `GraphicsQuality._lighting_quality()`, `_update_shadow_atlas()` и `_update_render_budgets()` выбирают эффективное качество, не перезаписывая сохранённые значения.
- `GraphicsQuality.apply_node()` применяет режим к загружаемым узлам; `apply_environment()` управляет SSAO, объёмным туманом и Glow.
- `scripts/levels/world_indirect_lighting.gd::set_quality_enabled()` и `update_floor()` отключают/возвращают VoxelGI. `finish_loading()` учитывает режим, поэтому загрузка прибытия не включает GI обратно в обычном режиме.

`/fullbright` остаётся отдельным отладочным режимом. Пока он включён, нельзя оценивать художественное освещение: мир и руки рисуются без светотеневого затемнения. Переключение качества не отменяет его. После `/fullbright off` действует выбранный режим качества.

## Основное освещение базы

Сборочная сцена — `scenes/levels/base_blockout_v03.tscn`. Размещение ламп — `scenes/levels/world_lighting.tscn`.

| Узел | Что делает | Управление |
| --- | --- | --- |
| `WorldLighting/Standard/*` — SpotLight3D и OmniLight3D | Основные рабочие лампы и освещение помещений | `world_lighting.gd::_register_lamp()`, `_select_nearest()`, `_update_lamps()` |
| `WorldLighting/Emergency/*` | Красные аварийные лампы | `world_lighting.gd::_advance_emergency()`; питание выбирает `base_power_lighting_controller.gd::apply_power_state()` |
| `WorldLighting/OvercastSun` — DirectionalLight3D | Наружный направленный свет через слой 17 | `world_lighting.gd::_process()` ограничивает дальность теней с учётом положения камеры |
| `SnowExterior/OvercastDayEnvironment` — WorldEnvironment | Небо, фоновый свет, отражения, туман, SSAO, Glow, тональная обработка | Авторский Environment в `scenes/levels/snow_exterior.tscn`; качество — `GraphicsQuality.apply_environment()` |
| `WorldIndirectLighting/*` — восемь VoxelGI | Отражённый свет от ламп на геометрии базы | `world_indirect_lighting.gd::update_floor()` |

WorldLighting выбирает ближайшие лампы и ограничивает одновременный набор и его тени. Поэтому видимые в сцене авторские источники не обязательно все одновременно активны в рендерере. Их положение, цвет, энергия, радиус, угол, `light_indirect_energy` и `light_volumetric_fog_energy` берутся из сцены.

Контроллер копирует исходный Environment на активную камеру. `is_covered()` проверяет крышу, а `_process()` плавно меняет фоновую освещённость и параметры тумана. В сборочной сцене заданы `outdoor_ambient = 0.13` и `indoor_ambient = 0.035`; значения по умолчанию отдельного контроллера — 0.12 и 0.025. Для проверки итогового изображения следует смотреть также `Camera3D.environment` во время игры.

Восемь зон GI: Entrance, Hub, Living, Control, LifeSupport, Trials, Containment, Expedition. Данные геометрии — `assets/environments/base_gi/*.res`. После перестройки статических стен, полов и мебели их нужно пересчитать через `tools/bake_world_gi.gd`. Перенос обычной лампы не требует запекания геометрии. Подробнее: [освещение мира](world_lighting.md).

## Свет вне обычных ламп

| Источник | Где находится | Что его включает |
| --- | --- | --- |
| Вспышка выстрела | `MuzzleFlash` — OmniLight3D в моделях `scenes/characters/visuals/tactical_a/` и `tactical_b/`, в сценах рук и тела | `weapon_controller.gd::_play_effect()` переносит свет к маркеру `Muzzle`, показывает его и запускает `MuzzleTimer`; таймер скрывает свет через 0.045 с |
| Подсветка рук и оружия | Создаваемый в игре DirectionalLight3D `ViewLighting` | `first_person_presentation.gd::_update_lighting()` берёт оценку из `WorldLighting.sample_view_light()`; освещает только слой рук/оружия |
| Ручной фонарик | `Beam` и `Spill` — два SpotLight3D в `scenes/objects/equipment/flashlight.tscn` | `player_flashlight.gd::set_enabled()` и логика батареи/неисправностей |
| Фонарик на оружии | `Beam` — SpotLight3D в `scenes/objects/equipment/mounted_flashlight.tscn` | `weapon_controller.gd::_physics_process()` учитывает состояние фонарика, батарею и показ оружия |
| Подсветка щита при ремонте | `Wiring/RepairCamera/RepairBeam` — SpotLight3D в `scenes/objects/base/base_main_breaker.tscn` | `breaker_wiring_interaction.gd::_process()`: открыт ремонт и есть включённый исправный фонарик с зарядом |
| Свет кабины лифта | `CabinMoving/CabinLight` — SpotLight3D в `scenes/objects/elevator/elevator_functional_blockout.tscn` | `elevator_controller.gd::_refresh_cabin_light()`; свет находится внутри движущейся кабины и зависит от питания |
| Свет лебёдки и площадок | `CabinMoving/CabinLight`, `Landings/Floor_0/CallLight`, `Landings/Floor_1/CallLight` в `scenes/objects/elevator/expedition_winch.tscn`; `ServiceLight` в `scenes/objects/elevator/winch_preparation.tscn` | Узлы локального оборудования; это отдельные реальные источники |
| Свет огнемёта | Два OmniLight3D `Glow` и `Impact/Glow` в `scenes/objects/effects/flamethrower_jet.tscn` | `flamethrower_jet.gd::set_jet()` и анимации воспламенения/горения/затухания; свет попадания работает при контакте со стеной |
| УФ-лампа контейнера | `Active/UVFill` — OmniLight3D в `scenes/objects/base/plant_uv_lamp.tscn`, плюс светящийся материал | Состояние локального объекта |
| Кабина вертолёта | `ArrivalCabin/LobbyCabinLights/*` в `scenes/levels/base_session.tscn`; `CabinRearLamp` и `CabinFrontLamp` в `scenes/objects/lobby/chinook.tscn` | Локальное освещение сцен прибытия и лобби |
| Превью персонажа | Два DirectionalLight3D в `scenes/ui/character_selection.tscn` | Изолированный `PreviewViewport`; помечен `ui_presentation`, профиль игрового освещения его не меняет |

Вспышка выстрела имеет энергию 0.45 и радиус 1.2 м. Она не участвует в GI и объёмном тумане. Частицы `MuzzleDischarge` — дополнительный видимый эффект; соседние поверхности освещает именно `MuzzleFlash`.

`ViewLighting` не подсвечивает комнату: маска света ограничена слоем 20 рук и оружия. Энергия плавно следует за оценкой освещения мира. Тени, GI и вклад в объёмный туман у него отключены.

`RepairBeam` представляет фонарик игрока в режиме ремонта. Без фонарика самостоятельного света от этого узла не будет.

## Откуда свечение дверей и поверхностей

Индикаторы текущих дверей базы используют MeshInstance3D со светящимися материалами. `BaseAutoDoorManager` задаёт красную/зелёную эмиссию с множителем 0.35; это собственная яркость поверхности, ореол создаёт Glow/Bloom. Отдельная старая тестовая цепь с DoorStatusIndicator удалена. Светильник `WorldLighting/Standard/GeneratorPanel` относится к действующей генераторной и сохранён.

Металл дверей дополнительно получает блики от реальных ламп и отражение HDR-неба (`reflected_light_source = Sky`). Фоновый ambient также делает поверхность видимой без прямого попадания лампы. Изменение Brightness/Gamma и AgX меняет итоговое изображение, но не добавляет источник света.

Для поиска причины яркого участка проверяйте по порядку: ближайшие Light3D и их маски, материал `Emission`, Environment камеры (ambient/sky/glow), активные VoxelGI, пользовательские Brightness/Gamma и состояние `/fullbright`.

## Проверка

`tools/tests/light_swap_regression.gd` проверяет старт нового профиля в продвинутом режиме, переключение, освобождение/возврат GI, сохранность настроек и питания, наследование режима новыми сценами, загрузку прибытия и независимость fullbright. После сохранения настроек в обычном режиме тест запускает новый процесс с тем же профилем и проверяет возврат продвинутого освещения. Существующие проверки графики и мира явно выбирают продвинутый режим там, где проверяют GI и постэффекты.
