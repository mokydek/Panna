# Фактические проверки

Этот файл фиксирует только действительно выполненные проверки и явно отделяет исторический baseline от текущего рабочего дерева. Полный набор будущих сценариев находится в [тест-плане](test-plan.md).

## Текущий статус

Для `0.3.0-alpha` пройдены validator, StyLua, Luau compile, diff-check, пять Rojo build и отдельные проверки Roblox/Blender/FBX-артефактов. Selene не смог получить Roblox API dump, а Roblox Studio в текущей macOS-среде не установлен. Поэтому Studio CLI и полный Play/Local Server lifecycle нового `BrightBlockDistrict` не подтверждены.

Текущий облегчённый bake сохраняет `BallVisualVersion`, `MechanicsVersion = StreetControlV3`, `VFXVersion = StreetReadabilityV1`, шесть панелей, actuator/trail-объекты и procedural-анимации игрока. Чистые regression cases добавлены для stationary close-control braking, прямого tackle takeover, плавной дистанции ведения, ограниченного assist и cushion/Trap. Aim/motion guides и локальные action VFX проверены статическим контрактом и Luau-компиляцией; ручной Play QA физического ощущения, визуальной пластики и рендера VFX остаётся обязательным. Studio CLI smoke ниже относится к историческому baseline `0.2.0-alpha`.

| Проверка | Статус | Что доказано |
| --- | --- | --- |
| Интеграция полностью физического мяча | **частично подтверждена** | Static/build/bake/Studio smoke пройдены; фактическое сетевое ощущение требует Play/Local Server |
| `scripts/validate-project.ps1` | **пройдена: `47 OK / 0 WARN / 0 FAIL`** | Пять разрешённых Rojo-профилей, обязательные пути, secret-patterns, физический контроллер, procedural-анимации, action cues, VFX/direction contract, единый каталог управления и guide |
| StyLua / Luau compile / `git diff --check` | **пройдены** | StyLua с Unix line endings, компиляция `30/30` Luau-файлов и whitespace-check завершились без ошибок |
| Selene | **не завершён: внешний API dump недоступен** | Бинарник запущен, но не смог получить Roblox standard library; это не результат lint |
| Пять manifest build | **пройдены, 5/5** | `default`, `source`, `world`, `multiplayer` и `asset-kit` собраны Rojo `7.7.0` с exit code 0 |
| Roblox/Blender artifact contract | **пройден** | `639` Parts/`6` WedgePart основного района; встроенная галерея содержит `12` Roblox-групп/`120` отдельных частей; `12` Blender mesh-объектов, минимум `3840` полигонов; общий FBX импортирован обратно как 12 конечных meshes с конечными координатами |
| Roblox Studio CLI `RunScript` для `0.3.0-alpha` | **не выполнялся** | Roblox Studio отсутствует в текущей среде; нужен ручной Edit/Play повтор |
| Исторический Roblox Studio CLI `RunScript` | **пройден для `0.2.0-alpha`** | Маркер `PANNA_STUDIO_SMOKE_OK version=0.2.0-alpha arenas=6`; физический/анимационный pipeline подтверждён до bright-block изменения |
| Запечённая модель Edit Mode | **структурно пройдена** | Единственный `PannaDistrict`; `MechanicsVersion = StreetControlV3`, `VFXVersion = StreetReadabilityV1`; 639 Parts и 6 WedgePart, семь сфер диаметром `2.3` stud, по шесть welded-панелей, шесть Grass-полей без Neon и отключённые PointLight |
| Исторический `StudioTestService` Local Server smoke (4 клиента, 2 комнаты) | пройден до переработки мяча | Четыре клиента физически активировали `EntryPrompt`, вошли в две независимые комнаты с разными `MatchId`, получили верные `ArenaId`/`InMatch`, а барьеры закрылись |
| Текущий расширенный Local Server ball-smoke (4 клиента, 2 комнаты) | **заблокирован внешним запуском Studio** | Ограниченный прогон 120 секунд не подключил четыре клиента; дочерний локальный `universe 0` получил `GetPlaceSafetyInfoFailure`/`provisional rating 500`; нужен приватный staging Place |
| Physical/goal/control/animation чистые regression cases | **пройдены в Studio smoke** | Проверены tuned radius/density/targets, bounded PD/Magnus/drag, launch/roll, `VectorForce`/`Torque`, no-snap, release/ownership, goal/scoping/cleanup, procedural-позы и 9 guide entries; Heartbeat/UI rendering не симулировались |
| Полный матч, гол, overtime, панна, disconnect, rematch | **не подтверждены** | Требуется ручной многоклиентный прогон |
| DataStore load/save в опубликованном staging | **не подтверждён** | Требуется отдельный staging Experience и безопасные тестовые данные |
| Физические мобильные устройства/геймпад/сетевые условия | **не подтверждены** | Требуются реальные устройства и latency tests |

После изменения мира, мяча, lifecycle, GoalMath, контрактов Arena/Remote или Rojo mapping эти проверки нужно повторить и вписать новый commit/log отдельно.

## Устройство многоклиентных smoke

`multiplayer.project.json` собирает тестовый place из того же игрового кода и `src/world/PannaDistrict.model.json`, что и основной проект, и дополнительно подключает:

- `tests/multiplayer-server.server.lua` — серверные ожидания готовности, размещение четырёх игроков в двух комнатах, два реальных паса, revisions, скорость, last touch, изоляция и устойчивость после malformed spam;
- `tests/multiplayer-client.client.lua` — клиентское физическое использование `EntryPrompt`, цепочка `ChargeStart → Pass`, проверка `ActionFeedback` и отправка 72 некорректных запросов от каждого из двух управляющих клиентов;
- `scripts/multiplayer-smoke.luau` — драйвер `StudioTestService:ExecuteMultiplayerTestAsync(4, ...)`.

Тестовые server/client-скрипты отсутствуют в `default.project.json`, поэтому не попадают в обычную сборку.

Предыдущая, более узкая версия room-сценария до текущей переработки мяча завершилась точным маркером дочернего server-процесса:

```text
PANNA_MULTIPLAYER_END PANNA_MULTIPLAYER_SMOKE_OK clients=4 arenas=2 matches=2
```

Маркер означает, что:

1. сервер и четыре клиента дождались готовности игрового runtime и персонажей;
2. две пары клиентов были перемещены к `EntryZone` комнат `Arena_1` и `Arena_2`;
3. каждый клиент физически удержал свой `EntryPrompt`, после чего обе комнаты вошли в `Countdown` или `Active`;
4. комнаты получили два разных непустых `MatchId`, а каждый игрок — `InMatch = true` и ожидаемый `ArenaId`;
5. барьеры обеих занятых комнат закрылись.

Это исторический программный Local Server результат через `StudioTestService`, а не подтверждение текущего расширенного ball-сценария и не ручной Play-прогон. Он подтверждает две одновременно работающие комнаты на прежнем runtime, но не текущие пас/revision/security проверки, полный матч до `Result`/`Free`, реванш или все шесть комнат одновременно.

Расширенный baseline-сценарий ранее запускался с таймаутами 180 и 420 секунд. Текущий build был повторно запущен с ограничением 120 секунд. Во всех случаях Studio `0.732.0.7321040` создавала дочерний Local Server, но локальный `universe 0` получал:

```text
GetPlaceSafetyInfoFailure: Failed to get provisional rating for universe 0, error code 500
```

Текущий драйвер завершён по 120-секундному таймауту без `PANNA_MULTIPLAYER_DRIVER_OK`: четыре клиента не подключились. Ошибка возникает на этапе открытия дочернего place, поэтому результат классифицирован как внешний блокер локального unpublished `universe 0`, а не как пройденный или упавший тест механик. Безопасный следующий прогон требует приватного staging Place с ненулевыми `placeId`/`universeId`; публикация не выполнялась без отдельного разрешения владельца.

## Исторический подтверждённый Studio CLI smoke (`0.2.0-alpha`)

Предыдущая версия `scripts/studio-smoke.luau` была выполнена над place `0.2.0-alpha` задачей Roblox Studio CLI `RunScript` и завершилась с exit code 0 и маркером:

```text
PANNA_STUDIO_SMOKE_OK version=0.2.0-alpha arenas=6
```

Исторический smoke подтвердил:

1. загрузку текущих `Config`, `BallMath`, `BallService`, `WorldBuilder`, `ProceduralPoseCatalog`, `PlayerAnimationController`, `ControlCatalog`, `InputController`, `UIController` и остальных модулей из canonical place;
2. меньший `Radius = 1.15`, почти сохранённую массу, упорядоченные цели ведения, устойчивые tuned PD limits и уменьшенное наследование скорости игрока для ударов/пасов;
3. отсутствие старых transform-follow helper-функций и сохранение `Anchored = false` в `Reset`, `Controlled` и action-состояниях;
4. наличие `PannaDribbleForce`/`PannaRollTorque`, их включение только в `Controlled`, обнуление при выходе и восстановление server network ownership;
5. отсутствие прямого скачка transform при входе во владение, вызов action-импульса и корректный same-mode runtime reconciliation;
6. Low/Normal/Chip/Pass launch envelopes, drag, speed/radius-derived roll, tackle geometry, full-sphere `GoalMath` с текущим радиусом, revision-scoping, RemoteRegistry и server cleanup;
7. единый каталог всех восьми действий и девять непустых разделов guide для keyboard/mouse, gamepad и touch, включая методы modal toggle;
8. ровно семь сфер диаметром `2.3` stud с `Density = 0.835`, по шесть welded-панелей, runtime-repair trail, radius-aware offsets и корневой `BallRadius = 1.15`;
9. конечные procedural-позы всех действий/финтов, additive-применение и восстановление `Motor6D.Transform`, фильтрацию stale/scoped `PlayerAction`, приём запоздалого scoped `Stop`, локальный hard-timeout hold-позы, а также серверный таймаут и cleanup удержания заряда;
10. прежний `NaturalFootballDistrict`, `FieldStyle = NaturalGrassFootballV1`, шесть зелёных `Grass`-полей с одинаковой физикой, мягкий Bloom и полное отсутствие `Material = Neon` в мире. Новый smoke-код уже ожидает `BrightBlockDistrict`, отключённые Bloom/SunRays/глобальные тени, но ещё не запускался в Studio.

Edit `RunScript` не запускает обычный клиентский Play lifecycle, не рендерит `PlayerGui` и не шагает Heartbeat-сетевую физику. Поэтому smoke подтверждает данные guide, рассчитанные ненулевые `VectorForce`/`Torque`, вызовы release/ownership и чистую математику, но не адаптивный визуальный layout, фактический отклик `ApplyImpulse`, движение PD-follow, obstacle `Spherecast`, первый приём или поведение при latency. Эти области и полный матч/реванш требуют Play/Local Server в доступном staging.

Этот перечень подтверждает trajectory/visual/animation-контракты на уровне canonical bake и Edit `RunScript`: шесть панелей, launch/drag/roll, наземный `Shot → Free`, flight-only trail и восстановление поз. Он не заменяет Play QA фактической траектории, контакта с газоном, визуального вращения, плавности анимаций и сетевой синхронизации.

## Bake для Edit Mode

Для воспроизводимого обновления статической карты используется:

```powershell
./scripts/bake-editable-place.ps1
```

Процесс строит place без статического корня через `source.project.json`, запускает `WorldBuilder` в Studio, извлекает детерминированный Rojo JSON в `src/world/PannaDistrict.model.json` и собирает `build/Panna-Football.rbxlx` через основной проект. Для отдельной проверки модели можно выполнить `rojo build world.project.json --output build/PannaDistrict.rbxmx`.

Успех полного Studio bake определяется маркером `PANNA_BAKE_OK`, а не только существованием выходного файла. Для `0.3.0-alpha` облегчённый Edit Mode snapshot обновлён детерминированным `refresh-minimal-bake.py`: записаны `LayoutVersion`, `BrightBlockFootballV1`, 639 Parts/6 WedgePart, сохранены `BallRadius = 1.15`, `CustomPhysicalProperties` и семь сфер с actuator/trail. Полный Studio bake и screenshot/device review нового мира не заявляются пройденными.

Текущий bake уже содержит `BallVisualVersion = "SoccerPanelsV1"`, `MechanicsVersion = "StreetControlV3"`, семь мячей и по шесть процедурных панелей на каждом. `WorldBuilder` дополнительно отвергает bake с устаревшим контрактом механик и восстанавливает повреждённые панели/trail.

## Как воспроизвести

Нужны доступный в `PATH` Rojo и установленный Roblox Studio. Не фиксируйте папку вида `version-...`: Studio обновляется, поэтому найдите текущий `RobloxStudioBeta.exe`.

Из корня репозитория выполните в PowerShell:

```powershell
$pannaRoot = (Resolve-Path '.').Path
$pannaRunId = [guid]::NewGuid().ToString('N')
$pannaSmokeDir = Join-Path ([IO.Path]::GetTempPath()) ("PannaStudioSmoke-$pannaRunId")
New-Item -ItemType Directory -Force -Path $pannaSmokeDir | Out-Null

$pannaPlace = Join-Path $pannaSmokeDir 'Panna-test.rbxlx'
$pannaOutput = Join-Path $pannaSmokeDir 'studio-smoke-output.log'
$pannaScript = Join-Path $pannaRoot 'scripts\studio-smoke.luau'

rojo build (Join-Path $pannaRoot 'default.project.json') --output $pannaPlace
if ($LASTEXITCODE -ne 0) { throw 'Rojo build failed' }

$pannaVersions = Join-Path $env:LOCALAPPDATA 'Roblox\Versions'
$pannaStudio = Get-ChildItem -Path $pannaVersions -Filter 'RobloxStudioBeta.exe' -File -Recurse |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if ($null -eq $pannaStudio) { throw 'RobloxStudioBeta.exe was not found' }

$pannaArguments = @(
    '--task', 'RunScript',
    '--localPlaceFile', ('"' + $pannaPlace + '"'),
    '--runScriptFile', ('"' + $pannaScript + '"'),
    '--outputFile', ('"' + $pannaOutput + '"'),
    '--quitAfterExecution'
)

$pannaProcess = Start-Process `
    -FilePath $pannaStudio.FullName `
    -ArgumentList $pannaArguments `
    -WindowStyle Hidden `
    -Wait `
    -PassThru

if ($pannaProcess.ExitCode -ne 0) {
    throw "Roblox Studio RunScript failed with exit code $($pannaProcess.ExitCode)"
}
if (-not (Test-Path -LiteralPath $pannaOutput -PathType Leaf)) {
    throw 'Roblox Studio did not create the requested output file'
}
Get-Content -LiteralPath $pannaOutput
if (-not (Select-String -LiteralPath $pannaOutput -SimpleMatch 'PANNA_STUDIO_SMOKE_OK' -Quiet)) {
    throw 'Studio smoke marker was not found'
}
```

`--outputFile` содержит сам выполненный скрипт и результат. Успех определяйте по точному маркеру, а не только по существованию файла или exit code.

## Что smoke не проверяют

Исторический Studio CLI smoke и исторический room smoke **не доказывают**:

- полный обычный запуск `init.server.lua` и жизненный цикл сервера;
- общую очередь и шесть одновременных комнат;
- полный последовательный переход комнаты `Free → Waiting → Countdown → Active → Result → Free`, timeout ожидания, выход через `ExitPrompt` и реванш;
- симуляцию Heartbeat, сетевую физику и network ownership во время матча;
- корректность/матрицу collision groups в многопользовательской физике, возврат посторонних, movement envelope и фактическую длительность Dash;
- голевой debounce в реальной физике, таймер, overtime или rematch;
- физическое PD-следование при остановке, ходьбе, спринте, shield, повороте и `Q`-дриблинге, отсутствие устойчивой дрожи/разгона и ground loss;
- obstacle `Spherecast`, который только сокращает цель, не меняет transform и приводит к безопасной потере владения при блокировке;
- сохранение `Anchored = false`, server ownership и корректный lifecycle `VectorForce`/`Torque` после каждого из shot/pass/tackle/panna/reset/loss/death/detach путей;
- физический Trap/первый приём, action-импульсы и противоположная ограниченная Magnus-подкрутка;
- реальное ощущение плавной дистанции ведения, aim assist удара/паса/панны, бокового отбора и cooldown после Miss/Blocked;
- фактические Low/Normal/Chip/Pass-дуги, уменьшение скорости от воздушного drag, переход наземного `Shot` сразу в `Free` и стабильность этих правил при разном Heartbeat;
- соответствие угловой скорости формуле `speed / radius × RollRatio`, читаемое вращение шести панелей без «тарелки» и тонкий trail только у быстрого негрунтового мяча;
- восстановление Humanoid, камеры, PlayerModule controls, transient input/HUD после результата, выхода, смерти/respawn и двух матчей подряд;
- full-sphere swept goal crossing в реальном Heartbeat на высокой скорости и у физической геометрии стоек/перекладины;
- выполнение `PannaDetector:Begin`/`Step`, успешную/ложную панну и отмену кандидата после чужого касания;
- фактическое выполнение текущей цепочки `ChargeStart → Pass`, ActionFeedback, revisions и malformed-spam защиты в многоклиентном runtime;
- контекстный ЛКМ: `Kick` при своём владении, только `Tackle` при владении соперника и отсутствие позднего Kick на отпускании после отбора; отдельно ПКМ/`Q`/`E`, HUD, ContextActionService, mobile/gamepad UX;
- DataStore, уникальность lease при быстром rejoin, unsafe/recovery после save failure, autosave, `BindToClose` и идемпотентность при реальном отключении.

Для этих областей выполните [ручной тест-план](test-plan.md) и не меняйте их статус на «пройдено» без воспроизводимого отчёта.
