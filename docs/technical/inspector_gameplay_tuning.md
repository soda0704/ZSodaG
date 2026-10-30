# Настройка объектов в Inspector

## Общие правила

Меняйте настройки в сцене-владельце или назначенном ресурсе. Профиль `.tres` может быть общим: изменение затронет все экземпляры. Для отдельного варианта используйте Make Unique и сохраните новый ресурс.

Сохранённое состояние имеет приоритет над стартовыми значениями. Изменение Max Health не лечит уже повреждённое существо; смена Item State не должна переписывать сохранённые патроны. Для нового баланса проверяйте новый прогресс либо существующую отладочную команду сброса соответствующей системы.

## Где настраивать

| Объект | Сцена или ресурс | Основные параметры |
| --- | --- | --- |
| Игрок | `scenes/characters/player.tscn` | Movement, бег/отдых, Interaction Reach, батарея, перенос тела |
| Здоровье | `scripts/characters/components/player_survival.gd`; `Survival` создаётся в runtime | Стартовые HP, падение, респавн и радиация — в коде; Remote Inspector показывает текущий экземпляр |
| Ночь | BaseDayProgressionController в базе | `sleep_duration` — 5 секунд; экран век и клипы — `scenes/ui/sleep_eyelids.tscn` |
| Оружие | `scenes/characters/weapon_controller.tscn` | Pistol/M4A1/Knife balance, Audio, Bullet marks |
| Монстры | `scenes/characters/monsters/` и `assets/config/monsters/` | Behavior, Perception, Combat, Navigation |
| Pickup | `scenes/objects/items/`, `scenes/objects/equipment/` | Item State, подбор, перенос, дальность, сопротивление |
| Снегоход | `scenes/objects/vehicles/snowmobile.tscn` | Fuel, Speed and steering, Driving physics, Engine audio |
| Тело | `scenes/objects/medical/medical_corpse.tscn` | Recovery, Carry physics, Interaction |
| Медицинская койка | `scenes/art/base/living/medical_room_art.tscn` | Дистанция и InteractionArea |
| Стартовый день | BaseGameplayController в базе | Starting Day Index |
| Следы снега | SnowTracks в наружной сцене | Расстояния, контакты, жизнь, fade и лимит |

## Монстры

Monster0/1/2 в `ContainmentEncounter` — экземпляры готовых сцен. AI Profile содержит реальные параметры поведения. Attack Distance должен превышать Stop Distance, Attack Reach — покрывать дистанцию начала удара. Field Of View задаёт полный угол в градусах.

`monster_id` связывает сюжетное существо с сохранением; не дублируйте его в сюжетных экземплярах. Место появления назначается через `monster_spawn_paths`. Скелет, масштаб Visual, NavigationAgent и звук принадлежат сцене существа. Меняйте тип заменой сцены, а не строкой внутреннего `model_id`.

В профиле доступны подтверждение цели (`sight_confirmation_time`), маска видимости, сокращение зрения для присевшего игрока, ускорение, угол попадания, восстановление после удара, лимит неудачных маршрутов и RVO. `attacks_enabled` отключает атаки, сохраняя преследование. Разрешения урона оружием и окружением независимы.

На HostileMonster назначаются `ragdoll_scene`, `ai_enabled` и маршрут `patrol_point_paths`; на MonsterVisual — ссылки на модель/AnimationPlayer, имена idle/walk/attack и `walk_reference_speed`. Новые модели используют готовые клипы, `prototype_motion` и `use_animation_reel` выключены. Редактируйте геометрию, клипы, colliders и pivot средствами Blender/редактора, не в ИИ. Для RVO радиус должен соответствовать реальному collider; для обхода стен нужна запечённая сетка.

Текущий баланс и сценарные API: [монстры](containment.md).

## Предметы

`Item State` содержит `battery_charge`, `charge_amount`, `fuel_liters`, `rounds` или `amount` по типу предмета. `Pickup Enabled` и `Draggable` независимы. `Push Resistance = -1` сохраняет автоматическое правило типа.

Сила случайного контакта при ходьбе задаётся на Player в `Loose item contact`: `Item Push Acceleration` (12 м/с²). Это исходное расталкивание ближайших предметов с уменьшенной силой, без проверки направления движения и без добавления вертикальной скорости. Масса, трение и damping самого предмета остаются штатными физическими свойствами его сцены.

Масса и CollisionShape настраиваются как свойства RigidBody3D. У оружия и инструмента `Use Authored Collision` сохраняет форму редактора. Дальность ограничивается и объектом, и лучом Player.

## Визуал и проверка

Свет, материалы, окружение, анимационные клипы и UI-разметка остаются в сценах и ресурсах движка. Ссылки программных компонентов назначаются через Inspector; не добавляйте второй механизм настройки того же состояния.

Проверки: `monster_inspector_ai_regression.gd` и профильные тесты изменённого объекта. Проверяйте экземпляр в сцене, новый прогресс и продолжение, чтобы отличить стартовую настройку от восстановленного состояния.


Контур предмета при наведении: `Highlight Category` на WorldItemPickup; цвета и прозрачность — ресурсы `pickup_focus_common.tres`, `pickup_focus_story.tres`, `pickup_focus_special.tres` в `assets/effects`. Размах прицела — SphereShape3D в `scenes/characters/item_focus.tscn`. См. [предметы](item_system.md#контур-при-наведении).

## Звук существ

У дочернего `MonsterAudio` назначается `MonsterAudioProfile` из `assets/config/monsters/audio`. В нём отдельно редактируются ambient/alert/search/windup/strike/miss, громкость, pitch, паузы, задержка подтверждения потери цели, наборы шагов для пола/металла/снега, дальность и приглушение препятствиями. Это параметры представления: слух и правила атаки остаются в AI Profile.

Для готового walk-клипа включите `animation_contacts` и задайте нормализованные фазы касания: у головы 0/0,5, у трёхногой Эволюции 0/⅓/⅔. Одновременные лапы считаются одним контактом. `walk_reference_speed` находится на MonsterVisual; AnimationPlayer готовых циклов использует физический такт. Для модели без такого клипа выключите `animation_contacts` и настройте `fallback_stride`. Положение MonsterAudio задаёт источник голоса; шаги расположены у земли. Новую модель и клипы подключают через редактор, не через изменения ИИ.

Подробнее: [звук и акустика](audio_mix.md#звуки-существ).
