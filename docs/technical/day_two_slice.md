# Day 2 — ключ шифрования

## Маршрут и состояния

Получить задание у `Daily_Task_Terminal_Socket` центрального хаба, спуститься
на −1, извлечь ключ у восточной панели `Encryption_Key_Terminal` в
`Secure_Data_Vault`, вернуться в хаб и сдать ключ. После сдачи доступен сон
и переход в Day 3. Day 3–5 пока не содержат заданий; журнал и койки сообщают
о конце доступного прототипа.

`BaseGameplayController.quest_stage` входит в общий snapshot и checkpoint:

| Значение | Стадия |
| --- | --- |
| 0 | UNAVAILABLE — Day 1 |
| 1 | OFFERED — задача доступна в хабе |
| 2 | ACCEPTED — ключ доступен на −1 |
| 3 | COLLECTED — ключ в общем сюжетном слоте |
| 4 | DELIVERED — ключ сдан, сон разрешён |

Общий слот принадлежит команде, не имеет transient peer-владельца и не вытесняет
фонарик. Любой участник может сдать ключ; disconnect не теряет предмет.
Физическое бросание сюжетного ключа не реализовано. Карманное снаряжение и
квест-предметы показаны отдельно в журнале; см. `equipment_inventory.md`.

Терминалы создаёт `BaseBlockoutRuntime` из общей сцены
`scenes/objects/base/day_two_terminal.tscn`, без изменения геометрии этажей.
`DayTwoTerminal` использует стандартный raycast на E, проверяет peer, расстояние
и стадию. Извлечение/сдача анимируют ключ и экран после snapshot хоста.
Начальный snapshot (в том числе late join) применяется мгновенно.

## Продолжение игры

Одиночный checkpoint: `user://base_gameplay_state.cfg`.
Кооп-checkpoint: `user://base_gameplay_state_coop.cfg`.
Прежний общий файл остаётся одиночным, автоматически в кооп не переносится.
При создании лобби существующий кооп-save можно продолжить или подтвердить
его сброс. Continue пропускает тестовую цепочку; начиная с Day 2 используются
утренние маркеры коек. Карманное снаряжение, предмет в руках и оставленные
pickup-предметы V3 сохраняются в дополнительной секции checkpoint.
Заправленная база при загрузке не создаёт новую канистру.

Checkpoint версии 1 без quest_stage совместим: Day 1 получает стадию 0,
Day 2 — стадию 1. Сброс Day 1 очищает задание. Все новые стадии сохраняются
хостом, клиент читает только сетевой snapshot.

## Совместимость сборок

Протокол 2 проверяет game tag, версию протокола и SHA-256 отпечаток `.gd`,
`.tscn`, `.tres` из scripts/scenes, `project.godot` и manifest управления.
Переводы строк нормализуются. Это проверка gameplay-контента, не хеш всего
EXE или внешних ассетов. Проверка выполняется после входа в Steam Lobby,
до подключения игрового transport peer. Редактор рассчитывает отпечаток,
export читает `network_build.cfg`, который генерирует лаунчер перед сборкой.
При ручном export предварительно запускать `tools/write_build_identity.gd`.
`pet-runs` и тестовые инструменты исключены из export.

## Проверки

Из корня проекта, Godot 4.7.2:

```powershell
godot --headless --path . --script tools/tests/base_gameplay_controller_test.gd
godot --headless --path . --script tools/tests/day_two_flow_test.gd
```

В двух терминалах; клиент запускается после `DAY_TWO_NETWORK_HOST_READY`:

```powershell
godot --headless --path . tools/tests/day_two_network_peer.tscn -- host
godot --headless --path . tools/tests/day_two_network_peer.tscn -- client
```

Сетевой тест использует localhost ENet:29473. Он проверяет реальный поздний
вход второго процесса после получения ключа, сдачу клиентским вводом через
raycast хоста и репликацию результата. Оба процесса должны вывести PASS
без runtime-ошибок. Все тесты используют отдельные checkpoint-файлы.

`godot --path . --script tools/tests/day_two_visual_preview.gd` сохраняет
PNG новых терминалов в `%TEMP%/NorthernLab-DayTwo*Terminal.png`.
Визуальная проверка выполнена на D3D12/Forward+; она не заменяет проход всего
маршрута. Steam Overlay, два разных аккаунта, внешний канал, packet loss
и производительность на слабом ПК требуют отдельного совместного прогона.
