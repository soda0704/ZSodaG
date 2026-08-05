# Steam networking prototype

## Архитектура

Northern Lab использует сюжетный кооператив с авторитетным хостом:

- хост создаёт Steam Lobby и симулирует игровой мир;
- второй игрок подключается по Lobby ID или Steam Invite;
- `SteamMultiplayerPeer` передаёт трафик через Steam Networking Sockets;
- `server_relay = true` позволяет Steam Datagram Relay обходить NAT;
- выделенный сервер для двух игроков не нужен.

Steam Lobby отвечает за обнаружение сессии и участников, но не хранит состояние
мира. Сюжетные флаги, физика и инвентарь остаются у хоста.

## Канонические файлы

- `addons/godotsteam/` — GodotSteam GDExtension 4.21 и Steamworks SDK 1.65;
- `scripts/network/steam/steam_network_service.gd` — Steam, Lobby и peer;
- `scripts/network/lobby/coop_lobby_service.gd` — готовность и старт;
- `scripts/characters/player.gd` и `scenes/characters/player.tscn` — один игрок
  для одиночного и сетевого режима;
- `scripts/gameplay/equipment/flashlight_pickup.gd` и
  `scenes/objects/equipment/flashlight_pickup.tscn` — один world-pickup;
- `scripts/network/tests/mechanics_test_room.gd` — сетевой спавн и синхронизация;
- `scenes/tests/mechanics_test_room.tscn` — единственная тестовая gameplay-сцена;
- `scripts/ui/game_menu.gd` и `scenes/ui/game_menu.tscn` — весь ESC/Steam flow.

Старая пара offline/network player, отдельный network-фонарик и отдельные сцены
двери/фонарика удалены. Production-уровень не инстансится тестовой сценой.

## Авторитет и частоты

1. Клиент отправляет нормализованное движение, поворот и порядковые номера
   одноразовых действий.
2. Хост проверяет sender ID и выполняет `move_and_slide()`.
3. Владелец использует prediction/reconciliation, удалённый игрок — interpolation.
4. Подбор, выброс, дверь и рубильник подтверждаются только хостом.

Частоты:

- input: `30 Hz`, `unreliable_ordered`;
- player snapshot: `20 Hz`, `unreliable_ordered`;
- движущийся фонарик: до `10 Hz`, затем финальный snapshot при sleep;
- критические состояния и создание объектов: `reliable`.

## Первый запуск после Git

Steam-версия Godot может содержать несовместимую `steam_api64.dll`. На каждом
компьютере нужно закрыть Godot и один раз запустить:

```text
SETUP_NORTHERNLAB.cmd
```

Установщик проверяет `addons/godotsteam/`, создаёт совместимую локальную копию
Godot в `tools/.local/` и генерирует:

- `NorthernLab.lnk` — запуск игры напрямую;
- `NorthernLab - Editor.lnk` — редактор.

Игровой ярлык теперь указывает прямо на процесс Godot, а не на PowerShell. Это
важно для Steam Overlay. Локальные runtime и ярлыки содержат пути конкретного ПК и
поэтому генерируются установщиком, а не передаются через Git.

## Проверка на двух компьютерах

1. Оба запускают Steam Client под разными аккаунтами.
2. Оба запускают одинаковую ревизию проекта через `NorthernLab.lnk`.
3. Хост: `ESC` → `Играть с друзьями`.
4. Lobby ID виден в HUD и в `ESC` → `Показать Steam-лобби`.
5. Клиент: `ESC` → `Подключиться к другу`, вставить Lobby ID.
6. Готовность можно менять независимо; хост может начать один.
7. Хост запускает вылет консолью на `E` или кнопкой `Начать игру`.

`ESC` открывает overlay-меню, но не ставит локальное дерево на паузу. Мир и второй
игрок продолжают двигаться; ввод открывшего меню игрока становится нулевым. Это
исключает ложную локальную «паузу» и сетевую рассинхронизацию.

## Steam Overlay и SpaceWar

App ID `480` показывает игру как SpaceWar — это подтверждает Steam API, но не
подтверждает внедрение Overlay в графический процесс.

Valve требует запускать игру через клиент Steam, чтобы Overlay подключился к
процессу до создания DirectX/Vulkan-устройства. Для раннего теста:

1. Повторно запустить `SETUP_NORTHERNLAB.cmd`, чтобы обновить прямой ярлык.
2. В Steam выбрать `Добавить игру` → `Добавить стороннюю игру`.
3. Добавить `NorthernLab.lnk`. Если Steam не принимает `.lnk`, добавить
   `tools/.local/godotsteam-editor/godot.exe`, указать launch options
   `--path "полный_путь_к_проекту"` и Start In — корень проекта.
4. Переименовать запись в NorthernLab и запускать её только из библиотеки Steam.
5. Проверить `Shift+Tab`, затем кнопку `Пригласить через Steam`.

Overlay может несколько секунд возвращать `false` после запуска. Также он должен
быть включён глобально в настройках Steam и для этой записи библиотеки.

Штатное решение для команды — собственный Steamworks App ID и одинаковая сборка,
загруженная через SteamPipe/Playtest. `SteamAPI_RestartAppIfNecessary(480)` здесь
не используется: для SpaceWar он может перезапустить чужой executable, а не
текущий Godot-проект.

Официальные источники:

- [Steam Overlay](https://partner.steamgames.com/doc/features/overlay)
- [Steamworks API initialization](https://partner.steamgames.com/doc/sdk/api)
- [GodotSteam MultiplayerPeer](https://godotsteam.com/tutorials/multiplayer_peer/)
- [GodotSteam Lobbies](https://godotsteam.com/tutorials/lobbies/)

## До Steam Playtest

- получить собственный App ID и доступ обоим разработчикам;
- заменить `network/steam/app_id` в `project.godot`;
- загрузить одинаковую Windows-сборку в depot/Playtest;
- проверить Invite Overlay, late join, разрыв связи и версии сохранений;
- позже добавить host migration/reconnect, сюжетные флаги и build compatibility.
