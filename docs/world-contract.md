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
        ├── Arena_1 (Model: Concrete Cage)
        ├── Arena_2 (Model: Neon Futsal)
        ├── Arena_3 (Model: Club House)
        ├── Arena_4 (Model: Industrial)
        ├── Arena_5 (Model: Training Lab)
        └── Arena_6 (Model: Championship)
```

`CentralStreet` непрерывно идёт от точки появления мимо трёх пар комнат к `EndLandmark`. Комнаты располагаются слева и справа от улицы; у каждой есть переход и собственная уличная точка возврата.

Основной Rojo-проект помещает запечённый `src/world/PannaDistrict.model.json` в `Workspace`, чтобы район был виден в Edit Mode. При старте `WorldBuilder` переиспользует корень только если это `Model` с совпадающим `LayoutVersion`, `ArenaCount = 6`, моделями `DistrictEnvironment`/`Lobby` и ровно шестью комнатами в `Arenas`. Несовместимый корень заменяется новым, собранным вне `Workspace`; ошибка посередине генерации не оставляет частичный мир.

## Корень, улица и лобби

| Объект | Класс | Назначение |
| --- | --- | --- |
| `PannaDistrict` | `Model` | Единственный корень; повторный builder не создаёт второй район |
| `DistrictEnvironment` | `Model` | Улица, окружение, вечерний свет и дальний ориентир |
| `CentralStreet/StreetSurface` | `BasePart` | Непрерывный пешеходный маршрут через весь район |
| `Lobby` | `Model` | Общая безопасная стартовая зона |
| `LobbySpawn` | `SpawnLocation` | Первичное появление и запасной возврат |
| `QueuePad/QueuePrompt` | `BasePart` + `ProximityPrompt` | Альтернативная общая очередь 1v1 |
| `TrainingZone` | `Model` | Отдельный тренировочный blockout; не считается матчевой комнатой |
| `Facilities` | `Model` | Визуальные Shop, Locker, Trophy и Rest-зоны; экономика/инвентарь пока не подключены |
| `EndLandmark` | `Model` | Видимый ориентир конца улицы |

Корневые диагностические атрибуты:

- `GeneratedBy = "WorldBuilder"`;
- `DistrictName = "PannaDistrict"`;
- `ArenaCount = 6`;
- `LayoutVersion = Config.Version`;
- `RoomStateContract = "Free,Waiting,Countdown,Active,Result"`.

`DistrictEnvironment` имеет `DistrictStyle = "EveningStreetFootball"` и `ExternalAssetCount = 0`; у `CentralStreet` задано `Continuous = true` и сохранены её границы `StartZ`/`EndZ`.

`QueuePad` и `QueuePrompt` имеют `QueueMode = "1v1"`. UI-кнопка быстрой очереди и prompt должны идти через один серверный путь. Для prompt используются `T` на клавиатуре и `R3` на геймпаде; touch использует стандартное взаимодействие Roblox.

## Шесть комнат

| ID | `DisplayName` / `RoomTitle` | Сторона | Тема blockout |
| --- | --- | --- | --- |
| `Arena_1` | `Concrete Cage` | Left | грубый бетон и клетка |
| `Arena_2` | `Neon Futsal` | Right | неоновая футзальная площадка |
| `Arena_3` | `Club House` | Left | клубный уличный двор |
| `Arena_4` | `Industrial` | Right | трубы и индустриальные опоры |
| `Arena_5` | `Training Lab` | Left | измерительная тренировочная тема |
| `Arena_6` | `Championship` | Right | финальная турнирная сцена |

Темы оригинальны и выполнены только геометрией, цветом, материалами и встроенным освещением. Декоративные модели можно менять независимо, пока обязательные прямые дети и их смысл сохраняются.

### Обязательные прямые дети комнаты

| Имя | Класс | Роль и требования |
| --- | --- | --- |
| `HomeSpawn` | `BasePart` | Матчевая позиция Home, ориентирована внутрь поля |
| `AwaySpawn` | `BasePart` | Матчевая позиция Away, ориентирована внутрь поля |
| `BallSpawn` | `BasePart` | Центр reset мяча над поверхностью |
| `HomeGoal` | `BasePart` | Невидимая серверная голевая зона Home |
| `AwayGoal` | `BasePart` | Невидимая серверная голевая зона Away |
| `Bounds` | `BasePart` | Объём sanity-check, изоляции и восстановления мяча |
| `Ball` | `BasePart` | Единственный физический авторитетный мяч комнаты |
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

### Атрибуты модели комнаты

| Атрибут | Тип | Начальное значение | Смысл |
| --- | --- | --- | --- |
| `ArenaId` | `string` | `Arena_N` | Уникальный стабильный ID |
| `RoomIndex` | `number` | `1`…`6` | Порядок комнаты |
| `DisplayName`, `RoomTitle` | `string` | тема из таблицы выше | Название на табло/UI |
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

Невидимые маркеры закреплены и не сталкиваются с персонажами/мячом. `Ball` — незакреплённая сфера под network ownership сервера. Видимые стойки, сетка, ограждения, трибуны и theme-модели не должны подменять служебные зоны.

У мяча и двух участников каждой комнаты собственные collision groups; остальные игроки относятся к spectator-группе. Периодический scan занятого `Bounds` возвращает постороннего к `StreetSpawn` даже если регистрация collision groups недоступна. Матрицу столкновений, `CanCollide`, `CanTouch`, `CanQuery` и поведение StreamingEnabled всё равно необходимо проверить в многоклиентном Studio-прогоне.

Дополнительные диагностические атрибуты:

- `HomeSpawn.TeamSide = "Home"`, `AwaySpawn.TeamSide = "Away"`;
- голевые зоны: `TeamSide` и `ArenaId`;
- `Bounds.ArenaId`;
- `Ball.ArenaId`, `OwnerUserId`, `LastTouchUserId`;
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
2. выполните `./scripts/bake-editable-place.ps1`, чтобы чистый `source.project.json` обновил `src/world/PannaDistrict.model.json` и основной place;
3. проверьте diff запечённой модели и непрерывность `CentralStreet` до всех трёх рядов;
4. проверьте `EntryZone`, waiting spawn, `Barrier`, `StreetSpawn` и spectator-трибуну каждой комнаты;
5. проверьте обе голевые зоны, `Bounds`, reset и возврат мяча;
6. запустите матчи параллельно во всех комнатах;
7. убедитесь, что лобби, улица и spectator-зоны не попадают внутрь матчевого `Bounds`;
8. повторите [Studio-smoke и ручной тест-план](TESTING.md).

## Lighting и производительность

Builder задаёт вечернее освещение и помечает собственные эффекты `PannaDistrictBuilderEffect = true`: `PannaAtmosphere`, `PannaColorGrade` и `PannaNeonBloom`. Чужие эффекты в `Lighting` не удаляются.

Геометрия модульная: повторяющиеся элементы группируются в модели, круговая разметка ограничена сегментами, а PointLight не отбрасывают динамические тени. Это снижает стоимость blockout, но не заменяет профилирование всех шести комнат, StreamingEnabled и LOD на слабом устройстве.

## Ручная арт-карта

При замене blockout:

- отключите/замените `WorldBuilder.Build`, иначе ручной корень будет заменён;
- сохраняйте служебные Parts отдельно от декора и не переименовывайте их без изменения сервисов;
- не помещайте доверенные скрипты внутрь импортированной модели;
- учитывайте StreamingEnabled и сетевой бюджет;
- проверяйте prompts, табло, барьеры, collision groups и все переходы комнаты;
- внесите каждый внешний ресурс и его лицензию в [ASSETS.md](../ASSETS.md).
