# Модели сборного огнемёта

Исходные архивы сохранены без изменений у автора проекта. Каталоги `*_source/` содержат импортированные исходники для повторной подготовки; игра использует отдельные сцены `scenes/art/crafting/` и облегчённые сетки `prepared/`.

## Лицензии

- **Apocalyptic Flamethrower** — [Nazareno_rojas](https://sketchfab.com/Nazareno_rojas), [модель](https://sketchfab.com/3d-models/apocalyptic-flamethrower-3f3ed85845574db48b4c943161469d14), CC BY 4.0.
- **Russian cola Dobriy Coca cola** — [EREMA_GEP](https://sketchfab.com/EREMA_GEP), [модель](https://sketchfab.com/3d-models/russian-cola-dobriy-coca-cola-12b9d507cc7d458b8f78b341fc1b1355), CC BY 4.0.
- **Republic Steel Fastener Case** — [Connections XR](https://sketchfab.com/connectionsxr), [модель](https://sketchfab.com/3d-models/republic-steel-fastener-case-6bf269f2c99b4e4dae65d6a15e77e560), CC BY 4.0.

Полные лицензии находятся в каталогах исходников. При распространении проекта необходимо сохранить эти указания авторства. Подготовленные версии изменены: упрощены сетки, нормализованы размеры и ориентация, из исходного огнемёта выделены самостоятельные детали. На готовой модели сохранена исходная насадка у выхода пламени; лишней банки на корпусе нет. Отдельные баллоны используют собственный штатный материал без следов скотча. Связка труб собрана из простых статических сеток.

## Подготовка

`tools/authoring/author_flamethrower_assets.gd` — офлайн-подготовка native-сцен и сеток. `tools/authoring/render_crafting_assets.gd` — изображения предметов для штатных карточек журнала. Эти инструменты не создают декорации во время игры. Баллоны редактируются через `prepared/loose_cylinder_paint.tres`; готовая модель сохраняет исходные материалы креплений.

Сетка готового огнемёта: 43 087 → 21 543 треугольника. Коробка: 30 072 → 1 878. Большой/малый баллон: 400 / 240; манометр: 676; вентиль: 1 218; банка: 158. Подробности — `prepared/mesh_report.json`. Это число треугольников сеток, а не замер FPS.
