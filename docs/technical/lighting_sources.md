# Источники света и переключение качества

## Настройки качества

Общее деление на Basic/Advanced и команда `/light_swap` удалены. Тени, GI, SSAO и Glow выбираются независимо в «Настройки → Качество» и сохраняются в Graphics. `GIQuality=0` выключает только VoxelGI; 1/2/3 задают качество. Отключение GI не меняет SSAO, Glow, тени, питание, яркость или цвет ламп.

`GraphicsQuality.apply()` применяет сохранённые значения к рендерингу и существующим узлам; `apply_node()` передаёт их позднее загруженным камерам, GI, декалям и SnowTracks. `WorldIndirectLighting.set_quality_enabled()` освобождает/возвращает данные GI; `InteriorAmbientOcclusion.set_gi_enabled()` выбирает ambient isolation при отсутствии GI. `set_gi_quality()` — узкий программный помощник без изменения остальных параметров.

При аварии VoxelGI не отображается независимо от его качества: работают прямые красные лампы. При восстановлении питания возвращается сохранённый выбор GI, включая «Выкл.». `/fullbright` остаётся отдельным отладочным ограничителем и не отменяется сменой качества. Глобальный Environment и экспозиция от питания не меняются.

Подробности применения, пресетов и проверки — [graphics_settings_2026_11_11.md](graphics_settings_2026_11_11.md).

## Основное освещение базы

Сборочная сцена — `scenes/levels/base_blockout_v03.tscn`. Размещение ламп — `scenes/levels/world_lighting.tscn`.

| Узел | Что делает | Управление |
| --- | --- | --- |
| `WorldLighting/Standard/*` — 143 SpotLight3D | Основные рабочие лампы и освещение помещений | `world_lighting.gd::_register_lamp()`, `base_light_pool.gd::update()`, `_update_lamps()` |
| `WorldLighting/Emergency/*` — 121 SpotLight3D | Красные аварийные лампы | `world_lighting.gd::_advance_emergency()`; питание выбирает `base_power_lighting_controller.gd::apply_power_state()` |
| `WorldLighting/OvercastSun` — DirectionalLight3D | Наружный направленный свет через слой 17 | `world_lighting.gd::_process()` ограничивает дальность теней с учётом положения камеры |
| `SnowExterior/OvercastDayEnvironment` — WorldEnvironment | Небо, фоновый свет, отражения, туман, SSAO, Glow, тональная обработка | Авторский Environment в `scenes/levels/snow_exterior.tscn`; качество — `GraphicsQuality.apply_environment()` |
| `WorldIndirectLighting/*` — десять VoxelGI | Отражённый свет от ламп на геометрии базы | `world_indirect_lighting.gd::update_floor()` |

WorldLighting выбирает ближайшие лампы и ограничивает одновременный набор и его тени. Поэтому видимые в сцене авторские источники не обязательно все одновременно активны в рендерере. Их положение, цвет, энергия, радиус, угол, `light_indirect_energy` и `light_volumetric_fog_energy` берутся из сцены.

Контроллер копирует исходный Environment на активную камеру для локального качества и калибровки. Крыша влияет на наружные эффекты и бюджет солнечных теней, но не меняет ambient/exposure всего изображения. Комнаты затемняются геометрией и комнатными GI/ReflectionProbe. Искусственная лампа EntranceSky удалена.

Десять зон GI: Entrance, Hub, Living, NorthWing, SouthWing, Control, LifeSupport, Trials, Containment, Expedition. Данные — assets/environments/base_gi/*.res. После перестройки статической геометрии их нужно пересчитать через tools/bake_world_gi.gd; перенос обычной лампы не требует такого запекания. Подробнее: [освещение мира](world_lighting.md), [дневной свет](interior_daylight.md).

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

Сам `ViewLighting` находится в изолированном World3D превью рук. В аварийном профиле VoxelGI не отображается: остаются настоящие красные источники, без обнаруженной белёсой GI-добавки. При восстановлении штатного питания возвращается выбранное пользователем качество GI, включая Off. Чёрный diffuse override четырёх ReflectionProbe у проходов отключён. Текущие настройки — [graphics_settings_2026_11_11.md](graphics_settings_2026_11_11.md); причины аварийного профиля — в историческом [lighting_advanced_profile_2026_11_11.md](lighting_advanced_profile_2026_11_11.md).

`RepairBeam` представляет фонарик игрока в режиме ремонта. Без фонарика самостоятельного света от этого узла не будет.

## Откуда свечение дверей и поверхностей

Индикаторы текущих дверей базы используют MeshInstance3D со светящимися материалами. `BaseAutoDoorManager` задаёт красную/зелёную эмиссию с множителем 0.35; это собственная яркость поверхности, ореол создаёт Glow/Bloom. Отдельная старая тестовая цепь с DoorStatusIndicator удалена. Светильник `WorldLighting/Standard/GeneratorPanel` относится к действующей генераторной и сохранён.

Металл дверей дополнительно получает блики от реальных ламп и отражение HDR-неба (`reflected_light_source = Sky`). Фоновый ambient также делает поверхность видимой без прямого попадания лампы. Изменение Brightness/Gamma и AgX меняет итоговое изображение, но не добавляет источник света.

Для поиска причины яркого участка проверяйте по порядку: ближайшие Light3D и их маски, материал `Emission`, Environment камеры (ambient/sky/glow), активные VoxelGI, пользовательские Brightness/Gamma и состояние `/fullbright`.

## Проверка

`tools/tests/light_swap_regression.gd` теперь проверяет удаление общего режима, независимость параметров, освобождение/возврат GI, питание, fullbright, позднюю загрузку, меню и сохранение смешанного профиля после реального перезапуска. `graphics_parameters_regression.gd` применяет три пресета через Settings и проверяет настоящие узлы и кадры.

Обновление 10.11.2026: расстановка и ограниченный пул переработаны. Проверки покрытия и кадров всех десяти секций — base_light_coverage_regression.gd и base_light_render_regression.gd. Огибающая тревоги достигает точного нуля; набор ламп не зависит от фазы звука. Питание и неисправности сохраняют существующий авторитетный контроллер.
