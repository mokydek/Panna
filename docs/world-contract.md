# Контракт мира Roblox

## Зачем нужен контракт

Игровые сервисы ищут комнаты и служебные точки по фиксированным именам и классам. `WorldBuilder` создаёт совместимый `PannaDistrict` автоматически. Ручная арт-карта должна сохранить этот контракт либо предоставить адаптер.

Внешние модели, asset ID и неизвестные free-model scripts не требуются. Весь текущий мир состоит из стандартных Roblox Instances и UI; реестр находится в [ASSETS.md](../ASSETS.md).

## Иерархия Workspace

Корневое имя задаёт `Config.World.RootName`; текущее значение — `PannaDistrict`.

```text
Workspace
└── PannaDistrict (Model)
    ├── DistrictEnvironment (Model)
    │   ├── DistrictGround (BasePart)
    │   ├── CentralStreet (Model)
    │   │   ├── StreetSurface (BasePart)
    │   │   ├── WestWalk / EastWalk (BasePart)
    │   │   ├── LaneMarkers (Model)
    │   │   └── RoomCrosswalks (Model)
    │   ├── DistrictLighting (Model)
    │   ├── DistrictSkyline (Model)
    │   └── EndLandmark (Model)
    ├── Lobby (Model)
    │   ├── Plaza (BasePart)
    │   ├── LobbySpawn (SpawnLocation)
    │   ├── QueuePad (BasePart)
    │   │   └── QueuePrompt (ProximityPrompt)
    │   ├── TrainingZone (Model)
    │   ├── Facilities (Model)
    │   │   ├── StreetShop (Model)
    │   │   ├── LockerRoom (Model)
    │   │   ├── TrophyCorner (Model)
    │   │   └── RestZone (Model)
    │   └── StreetDecor (Model)
    └── Arenas (Folder)
        ├── Arena_1 (Model: Street Football)
        ├── Arena_2 (Model: Community Pitch)
        ├── Arena_3 (Model: Club Ground)
        ├── Arena_4 (Model: Railway End)
        ├── Arena_5 (Model: Training Ground)
        └── Arena_6 (Model: Championship Field)
```

`CentralStreet` непрерывно идёт от точки появления мимо трёх пар комнат к `EndLandmark`. Комнаты располагаются слева и справа от улицы; у каждой есть переход и собственная уличная точка возврата.

Основной Rojo-проект помещает запечённый `src/world/PannaDistrict.model.json` в `Workspace`, чтобы район был виден в Edit Mode. При старте `WorldBuilder` переиспользует корень только если это `Model` с совпадающим `LayoutVersion`, `ArenaCount = 6`, моделями `DistrictEnvironment`/`Lobby` и ровно шестью комнатами в `Arenas`. Несовместимый корень заменяется новым, собранным вне `Workspace`; ошибка посередине генерации не оставляет частичный мир.

## Корень, улица и лобби

| Объект | Класс | Назначение |
| --- | --- | --- |
| `PannaDistrict` | `Model` | Единственный корень; повторный builder не создаёт второй район |
| `DistrictEnvironment` | `Model` | Улица, окружение, светлый дневной стиль и дальний ориентир |
| `CentralStreet/StreetSurface` | `BasePart` | Непрерывный пешеходный маршрут через весь район |
| `Lobby` | `Model` | Общая безопасная стартовая зона |
| `LobbySpawn` | `SpawnLocation` | Первичное появление и запасной возврат |
| `QueuePad/QueuePrompt` | `BasePart` + `ProximityPrompt` | Альтернативная общая очередь 1v1 |
| `TrainingZone` | `Model` | Отдельный тренировочный blockout; `TrainingBall` — свободная физическая демонстрация без match-control `BallService`, зона не считается матчевой комнатой |
| `Facilities` | `Model` | Визуальные Shop, Locker, Trophy и Rest-зоны; экономика/инвентарь пока не подключены |
| `EndLandmark` | `Model` | Видимый ориентир конца улицы |

Корневые диагностические атрибуты:

- `GeneratedBy = "WorldBuilder"`;
- `DistrictName = "PannaDistrict"`;
- `ArenaCount = 6`;
- `FieldStyle = Config.World.FieldStyle`;
- `LayoutVersion = Config.Version`;
- `RoomStateContract = "Free,Waiting,Countdown,Active,Result"`.

`PannaDistrict` и `DistrictEnvironment` имеют `FieldStyle = "NaturalGrassFootballV1"`; `DistrictEnvironment` также имеет `DistrictStyle = "NaturalFootballDistrict"` и `ExternalAssetCount = 0`. У `CentralStreet` задано `Continuous = true` и сохранены её границы `StartZ`/`EndZ`. Отсутствующий или несовпадающий `FieldStyle` делает старый bake несовместимым и заставляет builder безопасно пересобрать ту же сцену.

`QueuePad` и `QueuePrompt` имеют `QueueMode = "1v1"`. UI-кнопка быстрой очереди и prompt должны идти через один серверный путь. Для prompt используются `T` на клавиатуре и `R3` на геймпаде; touch использует стандартное взаимодействие Roblox.

## Шесть комнат

| ID | `DisplayName` / `RoomTitle` | Сторона | Покрытие | Тема blockout |
| --- | --- | --- | --- | --- |
| `Arena_1` | `Street Football` | Left | Grass | городской футбольный двор |
| `Arena_2` | `Community Pitch` | Right | Grass | общественное поле с металлическими балками |
| `Arena_3` | `Club Ground` | Left | Grass | клубный футбольный двор |
| `Arena_4` | `Railway End` | Right | Grass | индустриальные опоры без свечения |
| `Arena_5` | `Training Ground` | Left | Grass | спокойная тренировочная тема |
| `Arena_6` | `Championship Field` | Right | Grass | финальная турнирная сцена |

Темы оригинальны и выполнены только геометрией, цветом, материалами и встроенным освещением. Декоративные модели можно менять независимо, пока обязательные прямые дети и их смысл сохраняются.

Каждый `Court` — зелёный `Grass` с явными одинаковыми `CustomPhysicalProperties` (`Friction = 0.55`, `Elasticity = 0.05`) и имеет `PitchFinish` с чередующимися полосами покоса. Отдельные неколлизионные элементы создают `LeftTouchLine`, `RightTouchLine`, `HomeGoalLine`, `AwayGoalLine`, `CenterLine`, `CenterSpot`, сегменты `CenterCircle` и линии штрафных зон. Разметка является визуальной; серверные `Goal`/`Bounds` остаются независимыми невидимыми маркерами.

### Обязательные прямые дети комнаты

| Имя | Класс | Роль и требования |
| --- | --- | --- |
| `HomeSpawn` | `BasePart` | Матчевая позиция Home, ориентирована внутрь поля |
| `AwaySpawn` | `BasePart` | Матчевая позиция Away, ориентирована внутрь поля |
| `BallSpawn` | `BasePart` | Центр reset мяча над поверхностью |
| `HomeGoal` | `BasePart` | Невидимая геометрия створа/глубины Home; передняя грань задаёт плоскость линии |
| `AwayGoal` | `BasePart` | Невидимая геометрия створа/глубины Away; передняя грань задаёт плоскость линии |
| `Bounds` | `BasePart` | Объём sanity-check, изоляции и восстановления мяча |
| `Ball` | `BasePart` | Единственный авторитетный мяч комнаты: всегда `Anchored = false` и server-owned; в `Controlled` движение создают ограниченные `VectorForce`/`Torque` |
| `EntryZone` | `BasePart` | Внешняя зона входа; содержит `EntryPrompt` |
| `ExitZone` | `BasePart` | Внутренняя зона выхода; содержит `ExitPrompt` |
| `Barrier` | `BasePart` | Ворота комнаты, открытые в ожидании и закрытые во время матча/результата |
| `HomeWaitingSpawn` | `BasePart` | Место первого ожидающего игрока |
| `AwayWaitingSpawn` | `BasePart` | Краткая позиция второго игрока перед стартом |
| `StreetSpawn` | `BasePart` | Безопасный возврат к тротуару этой комнаты |
| `StatusBoard` | `BasePart` | Физическая основа табло |
| `SpectatorZone` | `BasePart` | Диагностический объём трибуны вне `Bounds` |

Служебные объекты должны оставаться **прямыми детьми** `Arena_N`, потому что `ArenaService` ищет их без рекурсивного обхода. `EntryPrompt` и `ExitPrompt` являются прямыми детьми соответствующих зон. В `StatusBoard/Display/Panel` должны существовать `TextLabel` с именами `RoomLabel`, `StateLabel` и `ScoreLabel`; сервис ищет эти labels рекурсивно.

Матчевое ядро (`HomeSpawn`…`Ball`) является жёстким требованием конструктора `ArenaService`. Комнатные зоны сейчас читаются как optional для совместимости со старой картой, но для `PannaDistrict` и `RoomService` считаются обязательными: отсутствующий prompt отключит вход/выход и даст предупреждение сервера.

Начальный `Ball` имеет `ControlModel = "PhysicalForce"`, `BallState = "Reset"`, нулевые owner/last touch/revision и физические дочерние объекты `PannaControlAttachment`, `PannaDribbleForce` (`VectorForce`) и `PannaRollTorque` (`Torque`). Оба actuator в Edit Mode/`Reset` выключены и обнулены; `BallService` переиспользует или восстанавливает этот runtime-контракт и включает их только для `Controlled`. Текущий bake с маркером `PANNA_BAKE_OK` содержит ровно семь `PannaDribbleForce` и семь `PannaRollTorque`: шесть матчевых комплектов и один комплект выключенных объектов у свободного `TrainingBall`.

### Атрибуты модели комнаты

| Атрибут | Тип | Начальное значение | Смысл |
| --- | --- | --- | --- |
| `ArenaId` | `string` | `Arena_N` | Уникальный стабильный ID |
| `RoomIndex` | `number` | `1`…`6` | Порядок комнаты |
| `DisplayName`, `RoomTitle` | `string` | тема из таблицы выше | Название на табло/UI |
| `PitchStyle` | `string` | `NaturalGrassFootballV1` | Версия визуального и физического контракта поля |
| `DistrictSide` | `string` | `Left`/`Right` | Сторона центральной улицы |
| `ArenaState` | `string` | `Free` | Состояние комнаты |
| `Busy` | `boolean` | `false` | `true` во всех состояниях кроме `Free` |
| `MatchId` | `string` | `""` | ID матча или пустая строка |
| `WaitingCount` | `number` | `0` | Число ожидающих в состоянии `Waiting` |
| `Occupants` | `number` | `0` | Число назначенных игроков |
| `HomeUserId`, `AwayUserId` | `number` | `0` | UserId назначенных сторон или `0` |
| `HomeScore`, `AwayScore` | `number` | задаётся сервисом | Текущий счёт для табло |

### Машина состояний комнаты

```text
Free → Waiting → Countdown → Active → Result → Free
  ↑        └── выход/timeout ─────────────────────┘
  └──────────── отмена/освобождение ──────────────┘
```

| Состояние | Вход | Барьер | Exit | Табло |
| --- | --- | --- | --- | --- |
| `Free` | включён, `ENTER ROOM` | открыт | выключен | `FREE` |
| `Waiting` | включён, `JOIN 1v1` | открыт | включён | `WAITING` |
| `Countdown` | выключен | закрыт | включён | `COUNTDOWN` |
| `Active` | выключен | закрыт | включён | `ACTIVE` + счёт |
| `Result` | выключен | закрыт | включён | `RESULT` + итоговый счёт |

Первый игрок ждёт не больше `Config.Rooms.WaitingTimeoutSeconds` (сейчас 120 секунд). Второй допустимый игрок запускает матч в той же комнате. После результата или выхода `ArenaService:ReturnToStreet` предпочитает `StreetSpawn` и использует `LobbySpawn` только как fallback.

## Геометрия, физика и изоляция

Невидимые маркеры закреплены и не сталкиваются с персонажами/мячом. Матчевый `Ball` остаётся `Anchored = false` и server-owned (`network owner = nil`) во всех состояниях. В `Controlled` сервер строит цель перед направлением `HumanoidRootPart`, выравнивает её по земле raycast-проверкой, превращает ограниченную ошибку позиции/скорости в `PannaDribbleForce` и поддерживает качение через `PannaRollTorque`. `Spherecast` только сокращает физическую цель перед препятствием и никогда не двигает сферу прямой записью transform. При shot/pass/panna/tackle/loss/death/detach actuators выключаются, а действие применяет серверный линейный/угловой импульс; в `Shot`/`Flight`/`Bounce` допускается ограниченная Magnus-подкрутка. Reset авторитетно возвращает мяч на `BallSpawn`. Видимые стойки, сетка, ограждения, трибуны и theme-модели не должны подменять служебные зоны.

У мяча, участников каждой комнаты и остальных игроков назначены отдельные collision groups. Физические столкновения мяча с персонажами намеренно отключены: касание, владение, shield, tackle и финты определяет авторитетная серверная геометрия, чтобы клиентская физика персонажа не могла напрямую толкать мяч. Мяч при этом сталкивается с площадкой и окружением. Периодический scan занятого `Bounds` возвращает постороннего к `StreetSpawn` даже если регистрация collision groups недоступна. Матрицу столкновений, `CanCollide`, `CanTouch`, `CanQuery` и поведение StreamingEnabled всё равно необходимо проверить в многоклиентном Studio-прогоне.

Для гола `GoalMath` ориентирует локальную ось глубины Goal marker от `Bounds.Position` внутрь соответствующих ворот. Передняя грань — плоскость голевой линии; поле имеет отрицательную signed distance, пространство сетки — положительную. `MatchService` проверяет swept-отрезок предыдущей/текущей позиции и принимает только движение поле → ворота, когда центр прошёл дальше радиуса и сфера целиком помещается в створе. Touch/half crossing, касание стойки/перекладины, проход снаружи и вход с задней стороны не считаются голом; debounce допускает одно начисление на episode.

Дополнительные диагностические атрибуты:

- `HomeSpawn.TeamSide = "Home"`, `AwaySpawn.TeamSide = "Away"`;
- голевые зоны: `TeamSide` и `ArenaId`;
- `Bounds.ArenaId`;
- `Ball.ArenaId`, `OwnerUserId`, `LastTouchUserId`, `BallState`, `BallRevision`, `LastAction`, `ControlModel = "PhysicalForce"`;
- `Barrier.Closed`;
- комнатные зоны: `ArenaId` и `RoomAction`.

`ArenaService` не выдаёт комнату при отсутствующем матчевом объекте, несовместимом классе или дублирующемся `ArenaId`. `Config.World.MinimumArenaCount = 6` запрещает старт с неполным набором.

## Атрибуты Player

| Атрибут | Тип | Смысл |
| --- | --- | --- |
| `InQueue` | `boolean` | Игрок находится в общей локальной очереди |
| `InRoomWaiting` | `boolean` | Игрок ожидает соперника в выбранной комнате |
| `SelectedArenaId` | `string` | ID выбранной комнаты или пустая строка |
| `InMatch` | `boolean` | Игрок привязан к незавершённому матчу |
| `MatchId`, `ArenaId` | `string` или отсутствие | Текущие авторитетные ссылки |
| `DataLoaded` | `boolean` | Профиль завершил загрузку/fallback |
| `DataSessionFallback` | `boolean` | Сохранение небезопасно; награды и published ranked блокируются |
| `ControlsLocked` | `boolean` | Действия запрещены во время countdown/pause/result |
| `MovementViolationCount` | `number` или отсутствие | Число отклонённых невозможных перемещений |
| `ArenaIntrusionCount` | `number` или отсутствие | Число возвратов из чужого занятого `Bounds` |

Атрибуты отражают серверное состояние для UI/диагностики. Клиент не получает права менять комнату, результат или награды записью атрибута.

## Изменение карты

Геометрические параметры находятся в `Config.World`. После изменения позиций, размеров или числа комнат:

1. сохраните минимум шесть уникальных `ArenaPositions` и при несовместимом layout увеличьте `Config.Version`;
2. выполните `./scripts/bake-editable-place.ps1`: внутренний build-профиль `source.project.json` обновит `src/world/PannaDistrict.model.json`, после чего canonical `default.project.json` соберёт основной release place;
3. проверьте diff запечённой модели и непрерывность `CentralStreet` до всех трёх рядов;
4. проверьте `EntryZone`, waiting spawn, `Barrier`, `StreetSpawn` и spectator-трибуну каждой комнаты;
5. проверьте обе голевые зоны, `Bounds`, reset и возврат мяча;
6. запустите матчи параллельно во всех комнатах;
7. убедитесь, что лобби, улица и spectator-зоны не попадают внутрь матчевого `Bounds`;
8. повторите [Studio-smoke и ручной тест-план](TESTING.md).

## Lighting и производительность

Builder задаёт нейтральное дневное освещение (`ClockTime = 13.8`) с читаемыми тенями и помечает собственные эффекты `PannaDistrictBuilderEffect = true`: `PannaAtmosphere`, `PannaColorGrade`, `PannaSoftBloom` и `PannaSunRays`. Bloom снижен до `0.04`, насыщенность — до `0.02`; чужие эффекты в `Lighting` не удаляются. В процедурном мире нет деталей с `Material = Neon`.

Геометрия модульная: повторяющиеся элементы группируются в модели, полосы покрытия и круговая разметка имеют фиксированное число сегментов, а PointLight не отбрасывают динамические тени. Это снижает стоимость blockout, но не заменяет профилирование всех шести комнат, StreamingEnabled, дневных post-effects и LOD на слабом устройстве. Текущий арт/lighting-проход запечён с `PANNA_BAKE_OK` и прошёл структурный Studio smoke вместе с единственным `PannaDistrict`; screenshot-review не выполнен, потому что `StudioCaptureService` недоступен в headless `RunScript`.

## Ручная арт-карта

При замене blockout:

- отключите/замените `WorldBuilder.Build`, иначе ручной корень будет заменён;
- сохраняйте служебные Parts отдельно от декора и не переименовывайте их без изменения сервисов;
- не помещайте доверенные скрипты внутрь импортированной модели;
- учитывайте StreamingEnabled и сетевой бюджет;
- проверяйте prompts, табло, барьеры, collision groups и все переходы комнаты;
- внесите каждый внешний ресурс и его лицензию в [ASSETS.md](../ASSETS.md).
