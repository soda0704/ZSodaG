# Steam networking prototype

## Архитектура

NorthernLab использует сюжетный кооператив с авторитетным хостом:

- хост создаёт Steam Lobby и симулирует игровой мир;
- до трёх дополнительных игроков подключаются по Lobby ID или Steam Invite;
- `SteamMultiplayerPeer` передаёт трафик через Steam Networking Sockets;
- `server_relay = true` позволяет Steam Datagram Relay обходить NAT;
- выделенный сервер для текущего кооператива не нужен.

Steam Lobby отвечает за поиск сессии и участников. Физика, предметы, дверь,
рубильник и сюжетное состояние подтверждаются хостом.

## Канонические файлы

- `addons/godotsteam/` — GodotSteam GDExtension 4.21 и Steamworks SDK 1.65;
- `scripts/network/steam/steam_network_service.gd` — Steam, Lobby и transport peer;
- `scripts/network/lobby/coop_lobby_service.gd` — готовность и старт;
- `scripts/network/tests/mechanics_test_room.gd` — сетевой roster и gameplay spawn;
- `scripts/characters/player.gd` и `scenes/characters/player.tscn` — единый игрок;
- `scripts/ui/game_menu.gd` и `scenes/ui/game_menu.tscn` — ESC/Steam flow;
- `scenes/tests/mechanics_test_room.tscn` — единственная тестовая gameplay-сцена.

## Готовность и первый spawn

Начать вылет может только хост, когда каждый фактически подключённый участник,
включая самого хоста, нажал «Готов». Если хост тестирует один, ему всё равно нужно
подтвердить собственную готовность. Проверяются одновременно живые transport peers
и кэш состояний — короткое окно во время подключения не позволяет обойти gate.

Игроки создаются через явный авторитетный roster, а не через отдельный
`MultiplayerSpawner`. После первого подключения клиент сам запрашивает roster, а
хост повторно отправляет его после сигнала `peer_joined`. Создание идемпотентно по
peer ID, поэтому ранний и повторный пакеты не создают дубликаты. Late join получает
существующих игроков и их текущие позиции.

## Авторитет и частоты

1. Клиент отправляет нормализованное движение, поворот, crouch и порядковые номера
   одноразовых действий.
2. Хост проверяет sender ID и выполняет `move_and_slide()`.
3. Владелец использует prediction/reconciliation, удалённый игрок — interpolation.
4. Подбор, выброс, дверь и рубильник подтверждаются только хостом.

Частоты:

- input: `30 Hz`, `unreliable_ordered`;
- player snapshot: `20 Hz`, `unreliable_ordered`;
- движущийся фонарик: до `10 Hz`, затем финальный snapshot при sleep;
- roster, готовность и критические состояния: `reliable`.

## Development EXE

Сборка и запуск:

```text
NorthernLab.cmd
```

Лаунчер при каждом запуске:

- проверяет локальную связку Godot/GodotSteam;
- создаёт `build/windows-dev/NorthernLab.exe` из текущего проекта;
- пересоздаёт единый `NorthernLab.lnk`, ведущий обратно в лаунчер;
- предлагает настройки окна, разрешения, монитора и VSync.

Для обычной разработки проект открывается напрямую из списка проектов Godot.

Это development export, а не релиз. Он нужен потому, что Steam Overlay должен
подключаться к настоящему игровому EXE; запуск редактора или Project Manager для
этой проверки ненадёжен. `build/` локален и не коммитится.

## Проверка на двух компьютерах

1. Оба участника делают `pull` одной ревизии.
2. Оба запускают `NorthernLab.cmd` и дожидаются успешной пересборки.
3. Оба добавляют `build/windows-dev/NorthernLab.exe` как стороннюю игру Steam и запускают
   его из библиотеки под разными аккаунтами.
4. Хост: `Esc` → `Играть с друзьями`.
5. Клиент принимает invite уже внутри игры либо вводит Lobby ID.
6. Убедиться, что оба сразу видят друг друга.
7. Оба нажимают «Готов»; до этого кнопка старта у хоста недоступна.
8. После старта проверить движение, прыжок, `Ctrl`, фонарики и выброс.
9. Одним игроком установить предохранитель и запустить генератор; оба должны
   увидеть свет и активный вход рубильника.
10. Вторым игроком включить линию, открыть дверь и затем остановить генератор;
    свет, индикаторы и питание двери должны совпасть у обоих.
11. Снова запустить цепь, открыть дверь и активировать терминал V3 одним игроком;
    оба должны появиться в V3 с прежними персонажами и предметами в руках.

`Esc` открывает overlay-меню, но не ставит локальный мир на паузу. Ввод игрока с
открытым меню обнуляется, а симуляция и второй участник продолжают двигаться.

## Steam Overlay и SpaceWar

App ID `480` показывает игру как SpaceWar. Он подходит для раннего API/network
прототипа, но не связывает пользовательский EXE с устанавливаемым Steam-продуктом.
Поэтому друг должен заранее открыть игру: приглашение не может надёжно запустить
`build/windows-dev/NorthernLab.exe` на его ПК.

Для полного invite-flow нужны собственный Steamworks App ID, одинаковая сборка в
SteamPipe/Playtest и доступ обоих аккаунтов. До этого отсутствие автозапуска по
invite является ограничением SpaceWar, а не ошибкой сетевого кода.

Официальные источники:

- [Steam Overlay](https://partner.steamgames.com/doc/features/overlay)
- [Steamworks API initialization](https://partner.steamgames.com/doc/sdk/api)
- [GodotSteam MultiplayerPeer](https://godotsteam.com/tutorials/multiplayer_peer/)
- [GodotSteam Lobbies](https://godotsteam.com/tutorials/lobbies/)

## До Steam Playtest

- получить собственный App ID и доступ обоим разработчикам;
- заменить `network/steam/app_id` в `project.godot`;
- загрузить одинаковую Windows-сборку в depot/Playtest;
- проверить Overlay Invite, late join, reconnect и несовпадающие версии;
- затем добавить host migration и восстановление сюжетного состояния.
