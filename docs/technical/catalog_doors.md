# Каталожные двери базы

35 обычных дверей на этажах 0, −1, −3 и −5 используют 27 сцен в scenes/art/doors/catalog_fitted/. DoorMetal, DoorDarkMetal и DoorSimple взяты из существующего sci-fi каталога Quaternius CC0. Лифт и отдельные гаражные ворота не заменены.

LegacyFrame хранит прежнюю сцену для возврата и источника звука. Корень скрыт, обработка выключена, collision_layer/mask старых тел обнулены, CSG-коллизии выключены. Квадратные индикаторы старых рамок отключены. Исходные art-сцены и материалы сохранены.

12 стыков используют уже установленную sci-fi выемку, ещё 23 получили DoorFrameSquare из каталога. Повторные рамки не создаются. Внутренний проём измерен пересечением треугольников рамки с лучами, затем учтены масштаб и ориентация экземпляра в уровне. Корни дверей выровнены с рамками; имена и пути для сейва и управления сохранены.

Узкие входные полотна поднимаются вверх, чтобы не заходить в соседнее стекло. Пары расходятся в стороны. Конечные положения заданы OpenPreview; движение выполняет прежний BaseAutoDoorManager через Tween за 0.7 с. Питание, приближение, монтировка, ручное состояние и звук используют прежние системы. Старые AnimationSockets не управляют новыми полотнами.

Шейдер assets/shaders/catalog_door_leaf.gdshader отсекает фрагменты движущегося полотна за фиксированной областью проёма, включая глубину и тени. Цветовые карты, ORM, Normal, metallic, roughness и UV взяты из исходных материалов поверхностей. На экземплярах собственные ShaderMaterial; общие Mesh и текстуры не меняются. modular_catalog_door.gd обновляет матрицу отсечения при переносе узла.

Для изменения проёма согласовать passage_size, размеры CatalogMesh, OpenPreview и рамку. В сценах без CatalogFrame используется рамка окружения. Фактические размеры:

| Дверь | Проём X/Y/Z, м | Рамка |
| --- | --- | --- |
| West_Hub_Decon_Door_Visual_Prototype | Vector3(2.7189043, 3.1577294, 0.24) | Walls/DoorFrameSquare |
| West_Decon_Equipment_Door_Visual_Prototype | Vector3(1.9192265, 2.7337654, 0.24) | Walls/DoorFrameSquareTall3 |
| West_Equipment_Garage_Door_Visual_Prototype | Vector3(1.9192265, 2.7337654, 0.24) | Walls/DoorFrameSquareTall2 |
| West_Garage_Cold_Warm_Door_Visual_Prototype | Vector3(3.1987107, 2.7337654, 0.24) | Walls/DoorFrameSquareTall |
| West_Pedestrian_Inner_Door_Visual_Prototype | Vector3(1.3964419, 2.321195, 0.24) | новая каталожная |
| West_Pedestrian_Exterior_Door_Visual_Prototype | Vector3(1.8282268, 3.6268656, 0.24) | новая каталожная |
| Technical_Hub_Storage_Door_Visual_Prototype | Vector3(2.7189043, 3.1577294, 0.24) | Walls/DoorFrameSquare2 |
| Technical_Storage_Generator_Door_Visual_Prototype | Vector3(2.622626, 2.7673745, 0.24) | новая каталожная |
| living_hermetic_door | Vector3(2.7189043, 3.1577294, 0.24) | Walls/DoorFrameSquare2 |
| Standard_Door_Visual_Prototype | Vector3(1.8232651, 3.1577294, 0.24) | Wall/DoorFrameSquare |
| Standard_Door_Frosted_Visual_Prototype | Vector3(2.8788395, 3.1577294, 0.24) | Wall11/DoorFrameSquare2 |
| Medical_Hermetic_Door_Visual_Prototype | Vector3(2.8788395, 3.1577294, 0.24) | Wall11/DoorFrameSquare3 |
| Science_Entrance_Door_Visual_Prototype | Vector3(2.7189043, 3.1577294, 0.24) | Walls/DoorFrameSquare2 |
| Science_Briefing_Research_Door_Visual_Prototype | Vector3(2.7189043, 2.9719806, 0.24) | Wall3/DoorFrameSquare |
| Science_Research_Isolation_Door_Visual_Prototype | Vector3(2.7189043, 3.1577294, 0.24) | Wall10/DoorFrameSquare |
| l1_checkpoint_spine | Vector3(5.049814, 3.4767787, 0.24) | новая каталожная |
| l1_security_post | Vector3(2.9600325, 3.4767787, 0.24) | новая каталожная |
| l1_communications | Vector3(2.9600325, 3.4767787, 0.24) | новая каталожная |
| l1_surveillance | Vector3(3.424431, 3.4767787, 0.24) | новая каталожная |
| l1_data_vault | Vector3(3.424431, 3.4767787, 0.24) | новая каталожная |
| l1_incident_record_gallery | Vector3(3.424431, 3.4767787, 0.24) | новая каталожная |
| l1_emergency_coordination | Vector3(3.424431, 3.4767787, 0.24) | новая каталожная |
| l1_access_systems | Vector3(3.424431, 3.4767787, 0.24) | новая каталожная |
| l1_response_coordination_gallery | Vector3(3.424431, 3.4767787, 0.24) | новая каталожная |
| l1_command_center | Vector3(5.049814, 3.4767787, 0.24) | новая каталожная |
| ArrivalAccess | Vector3(2.7512527, 2.9214122, 0.24) | новая каталожная |
| ControlAccess | Vector3(2.7512527, 2.9214122, 0.24) | новая каталожная |
| EastServiceAccess | Vector3(2.7512527, 2.9214122, 0.24) | новая каталожная |
| ExposureAccess | Vector3(2.7512527, 2.9214122, 0.24) | новая каталожная |
| ExposureRearAccess | Vector3(2.7512527, 2.9214122, 0.24) | новая каталожная |
| ControlServiceAccess | Vector3(2.7512527, 2.9214122, 0.24) | новая каталожная |
| ObservationAAccess | Vector3(2.7512527, 2.9214122, 0.24) | новая каталожная |
| ObservationBAccess | Vector3(2.7512527, 2.9214122, 0.24) | новая каталожная |
| ObservationServiceAccess | Vector3(2.7512527, 2.9214122, 0.24) | новая каталожная |
| l5_machine_room_fire | Vector3(6.2108054, 5.699412, 0.24) | новая каталожная |

Проверки: catalog_doors_regression.gd — все состояния, коллизии, промежуточная анимация, скрытые старые детали, отсутствие дубликатов, ручное управление, неизменные идентификаторы. Контрольный кадр воспроизводит видимость красной створки за проёмом без отсечения и подтверждает исчезновение с отсечением. emergency_alarm_regression.gd проверяет звук через открытый и закрытый вход.

Ограничения: двухклиентный кооператив отдельно не запускался, состояние идёт через прежний snapshot. Визуально просмотрены вход и широкий внутренний стык; полный художественный обход всех комнат остаётся ручной проверкой. Времена переключения проходного блокера сохранены; отдельных движущихся физических тел на полотнах нет.

Проверено 04.11.2026: 80/80 проверок дверей и отсечения, 37/37 аварийного света/звука на исходниках и итоговом Windows-пакете. Script Integrity: 162 скрипта, 563 сцены, 278 подключений скриптов, failures=0. Штатный лаунчер проверил ресурсы, New Game, Save/Continue и запуск EXE. Логи/кадры: tools/.local/modular-doors/build-checks/.

Исправление 04.11.2026: размеры полотен учитывают передние/задние фаски, а не только центральное сечение. У семи дверей удалены старые переопределения transform в сборочной base_blockout_v03.tscn: масштаб и положение теперь берутся из сцены этажа. Правые створки используют производные *_mirrored.res с отражёнными X, нормалями/касательными и обратным порядком треугольников; runtime scale положительный, лицевая сторона совпадает с левой. Разворот на 180° и отрицательный runtime scale не используются. Исходные каталожные Mesh сохранены.

GI: перезапечены Entrance, Hub, Living, Control, Trials и Expedition. В tools/bake_world_gi.gd LegacyFrame вместе со всем поддеревом исключён из запекания, как и движущиеся створки. Опции --zones=A,B и --data-only позволяют обновлять ресурсы без пересохранения сцены GI. Исходная запечённая геометрия заменённых рамок больше не должна оставаться в новых данных. Диагностика отдельно сравнивала GI, Normal и тени; яркий локальный блик от настоящей лампы на стене не является запечённой лампой.

Финальный пакет после исправлений 04.11.2026: 83/83 проверки дверей (включая общую глубину/высоту половин, лицевые нормали и покрытие фасок) и 37/37 аварийного света/звука. New Game, Save/Continue, аудит ресурсов и запуск EXE прошли. Логи и кадры: tools/.local/modular-doors/corrected-build/.
