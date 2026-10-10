# Журнал: физический FP viewmodel и world pose

Журнал полностью перенесён в новую FP систему. Сохраняются исходные задания, инвентарь, шрифты, иллюстрации и действия; прежние отдельные journal arms, ModelViewport и анимация перехода к плоскому PNG удалены.

`QuestJournal` открывается на J, закрывается на J/Esc или кнопкой страницы. Переходы: Normal → JournalOpen (0.88 с) → JournalReading → JournalClose (0.72 с) → Normal. Ввод движения и оружия блокируется с первого кадра открытия до полного закрытия; сетевой мир продолжает работать. Смерть, сон и меню вызывают force_close. Повторное нажатие во время перехода сохраняет текущую фазу через TimeSeek и обратный native clip.

## Риги и книга

`GameFirstPersonPresentation` использует тот же единственный FP arms rig для оружия, фонарика и книги. `Journal` — самостоятельный Node3D в `first_person.tscn`, рядом со Skeleton3D, а не предмет, скопированный из camera transform или закреплённый за одной кистью. `LeftGrip`/`RightGrip` находятся у нижних внешних краёв разворота. Два TwoBoneIK3D доводят кисти к grip markers; CopyTransformModifier3D задаёт ориентацию, сохранённые Journal_Left/Right управляют фалангами. Дыхание/sway всей системы очень умеренные.

AnimationLibrary каждого варианта содержит отдельные FP/world JournalOpen, JournalReading и JournalClose. Корень книги, обложка, сгиб бумаги и обе руки используют один clip clock. Полная траектория подъёма сохранена отдельными native keys — она не зависит от удаления постоянных wrist-relative keys. Journal StateMachine не перезапускает ожидающий переход каждый physics frame.

Редактируемая книга: `scenes/ui/journal/book/articulated_journal.tscn`. Передняя кожа, внутренняя страница и три листа принадлежат FrontCoverPivot. PaperBindingRig имеет две кости для сгиба, связанного с обеими страницами. Источник glTF и текстуры сохранены. `prepare_journal_presentation.gd` пересобирает только геометрию книги; после этого `prepare_player_characters.gd` пересобирает её анимации в вариантах.

Удалённый игрок видит отдельную полную TP модель и самостоятельную книгу перед грудью с собственной позой. По сети передаются только Journal phases 0/1/2/3. Координаты FP книги, UI и текстура страниц не отправляются.

## Живые страницы и ввод

`scenes/ui/quest_journal.tscn` сохраняет привычные Controls. После _ready их NotebookPivot перемещается в `JournalInkViewport` размером 1400×986. Его texture отображается двумя page meshes FP книги через `assets/shaders/journal_ink.gdshader`; он не заменяет руки или 3D книгу при чтении. Левая страница располагается перед верхним листом, правая — перед ReadingPage. Свет и материалы книги принадлежат общей FP системе.

Mouse ray от view_camera пересекает плоскость страницы, UV превращается в координаты UI atlas и передаётся в SubViewport.push_input. Так действуют настоящие карточки, scrolling, справка, кнопки батареек/drop/mount и закрытия. Leave/release отправляется и при уходе курсора за страницу, чтобы не оставлять зажатую карточку. Клавиатура и controller navigation также передаются в UI viewport. Фокус проверяется внутри этого viewport. J/Esc обслуживает QuestJournal. При закрытом журнале рендер текста отключён.

Текст остаётся состоянием существующих BaseGameplayController и инвентаря Player; не создаётся второй gameplay inventory. Основной шрифт — `assets/fonts/journal/body.ttf`, заголовки — `headings.otf`; кириллица и латиница проверены. Разметка, шрифты и иллюстрации редактируются в существующих nodes/theme. Кнопки footer сдвинуты внутрь страницы, чтобы большой палец не закрывал Close.

## Проверено

`journal_presentation_regression.gd` реально запускает Base_Blockout_v03 и проходит 22 проверки без ошибок: подъём, early close/reopen, раскрытие обложки, mission text, выбор батарейки синтетическим OS mouse click по проекции страницы, Help/Close, восстановление HUD/фонаря, сохранение инвентаря и закрытие при смерти.

`first_person_actions_regression.gd` проверяет обе модели и фактический контакт обоих wrists с markers. Два HOST + CLIENT запуска с обратным распределением проверяют, что другой игрок действительно достигает JournalReading, поднимает книгу к груди и полностью раскрывает обложку. Кадры FP/world reading/open/close сохранены в `tools/.local/`. См. [архитектуру персонажей и полные результаты](character_visuals.md).
