# Настройка объектов в Inspector

## Общие правила

Меняйте настройки в сцене-владельце или назначенном ресурсе. Профиль `.tres` может быть общим: изменение затронет все экземпляры. Для отдельного варианта используйте Make Unique и сохраните новый ресурс.

Сохранённое состояние имеет приоритет над стартовыми значениями. Изменение Max Health не лечит уже повреждённое существо; смена Item State не должна переписывать сохранённые патроны. Для нового баланса проверяйте новый прогресс либо существующую отладочную команду сброса соответствующей системы.

## Где настраивать

| Объект | Сцена или ресурс | Основные параметры |
| --- | --- | --- |
| Игрок | `scenes/characters/player.tscn` | Movement, бег/отдых, Interaction Reach, батарея, перенос тела |
| Здоровье | PlayerSurvival внутри Player | HP, падение, респавн и радиация |
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

Текущий баланс: [монстры](containment.md).

## Предметы

`Item State` содержит `battery_charge`, `charge_amount`, `fuel_liters`, `rounds` или `amount` по типу предмета. `Pickup Enabled` и `Draggable` независимы. `Push Resistance = -1` сохраняет автоматическое правило типа.

Масса и CollisionShape настраиваются как свойства RigidBody3D. У оружия и инструмента `Use Authored Collision` сохраняет форму редактора. Дальность ограничивается и объектом, и лучом Player.

## Визуал и проверка

Свет, материалы, окружение, анимационные клипы и UI-разметка остаются в сценах и ресурсах движка. Ссылки программных компонентов назначаются через Inspector; не добавляйте второй механизм настройки того же состояния.

Проверки: `monster_inspector_ai_regression.gd` и профильные тесты изменённого объекта. Проверяйте экземпляр в сцене, новый прогресс и продолжение, чтобы отличить стартовую настройку от восстановленного состояния.
