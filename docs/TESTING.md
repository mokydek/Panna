# Фактические проверки

Этот файл фиксирует только действительно выполненные проверки и явно отделяет исторический baseline от текущего рабочего дерева. Полный набор будущих сценариев находится в [тест-плане](test-plan.md).

## Текущий статус

Для текущего рабочего дерева выполнены статические проверки, четыре существующих Rojo build, дневной bake и Studio CLI smoke. Чистые вычисления, структура сцены и три цикла server cleanup подтверждены. Полный Play/Local Server lifecycle не подтверждён: текущая 4-клиентная попытка снова остановилась на внешней ошибке safety rating локального `universe 0` до подключения четырёх клиентов.

| Проверка | Статус | Что доказано |
| --- | --- | --- |
| Интеграция текущих gameplay/world/lifecycle изменений | **частично подтверждена** | Static/build/bake/Studio smoke пройдены; реальный Play/Local Server lifecycle и сетевое ощущение остаются открытыми |
| `scripts/validate-project.ps1` | **пройдена: `34 OK / 0 WARN / 0 FAIL`** | Четыре разрешённых внутренних Rojo-профиля, один canonical `default.project.json`, обязательные пути, отсутствие известных сигнатур секретов и эвристический баланс 26 Luau-файлов |
| StyLua / Selene / Luau compile / `git diff --check` | **пройдены** | Форматирование чистое; Selene: `0 errors / 0 warnings / 0 parse errors`; 26 Luau-файлов компилируются; whitespace-ошибок нет |
| Четыре существующих внутренних manifest build | **пройдены** | Собраны `default.project.json`, `source.project.json`, `world.project.json` и `multiplayer.project.json`; новых manifests/проектов нет |
| Roblox Studio CLI `RunScript` | **пройдена, exit code 0** | Маркер `PANNA_STUDIO_SMOKE_OK version=0.2.0-alpha arenas=6`; текущие daylight/map, GoalMath/kinematic cases, config, revision-scoping эффектов/snapshots и три cleanup-цикла прошли |
| Запечённая модель Edit Mode | **пройдена с `PANNA_BAKE_OK`** | Обновлён `src/world/PannaDistrict.model.json` и собран canonical place с `BrightDayFootballDistrict`, покрытиями и разметкой |
| Исторический `StudioTestService` Local Server smoke (4 клиента, 2 комнаты) | пройден до переработки мяча | Четыре клиента физически активировали `EntryPrompt`, вошли в две независимые комнаты с разными `MatchId`, получили верные `ArenaId`/`InMatch`, а барьеры закрылись |
| Текущий расширенный Local Server ball-smoke (4 клиента, 2 комнаты) | **заблокирован внешним запуском Studio** | Ограниченный прогон 120 секунд не подключил четыре клиента; дочерний локальный `universe 0` получил `GetPlaceSafetyInfoFailure`/`provisional rating 500`; нужен приватный staging Place |
| Kinematic/goal/control чистые regression cases | **пройдены в Studio smoke** | Проверены цели/качение, shield direction, шесть вариантов линии гола, обе перестановки нового/старого матчевого контекста, stale Result/snapshot и три lock→cleanup→unlock цикла; Heartbeat/сеть не симулировались |
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

## Текущий подтверждённый Studio CLI smoke

После финальной сборки `scripts/studio-smoke.luau` выполнен официальной задачей Roblox Studio CLI `RunScript` над текущим place. Процесс завершился с exit code 0 и маркером:

```text
PANNA_STUDIO_SMOKE_OK version=0.2.0-alpha arenas=6
```

Текущий прогон проверил:

1. `ServerScriptService/PannaServer` и `ReplicatedStorage/PannaShared` попали в place через Rojo.
2. Загружаются `Config`, `BallMath`, `GoalMath`, `EffectScope`, `Net`, `Types`, `WorldBuilder`, `ArenaService`, `RoomService`, `RemoteRegistry`, `RateLimiter`, `PlayerDataService`, `PannaDetector`, `BallService`, `MatchService` и `QueueService`.
3. `BallMath` отклоняет non-finite значения, вычисляет kinematic target/roll, нормализует направления и проверяет правильную ориентацию shield.
4. Low/Normal/Chip/Pass дают конечную и монотонно растущую скорость от minimum к maximum charge, не превышают глобальный speed cap; lift Low < Normal < Chip. Геометрические front/side/rear проверки tackle согласованы с Config.
5. `WorldBuilder.Build` принимает текущий запечённый `PannaDistrict`; проверяются `BrightDayFootballDistrict`, дневные Lighting/SunRays, `ArenaCount = 6`, непрерывная улица и сервисные зоны.
6. `ArenaService` обнаруживает ровно шесть комнат с уникальными темами Concrete Cage, Neon Futsal, Club House, Industrial, Training Lab и Championship и полным комнатным контрактом.
7. Каждая арена содержит новое покрытие, touch/penalty lines и читаемые металлические рамы ворот; начальный мяч физический, незакреплённый и server-owned.
8. `ArenaService:ResetBall` возвращает каждый мяч к `BallSpawn`, обнуляет скорости, owner и last touch.
9. `BallService.new` создаёт runtime-state; legacy `PannaDribbleForce` присутствует только для совместимости и выключен; `Trail` и атрибуты согласованы с `Reset`.
10. `GoalMath` отклоняет касание/половину мяча, касание стойки и вход сзади, но принимает полный и быстрый swept-проход.
11. Матчевые эффекты получают `matchId`/`arenaId`/`matchRevision`; `EffectScope` принимает более новую ревизию при любой очередности каналов и отклоняет старые `Result`, `StateUpdate` и snapshot после начала нового матча.
12. Три последовательных тестовых lock→cleanup→unlock цикла восстанавливают обоим игрокам `WalkSpeed = 18`, `JumpHeight = 7.2`, `JumpPower = 50`, очищают матчевый контекст и освобождают runtime ровно один раз.
13. `ActionRequest`, `ActionFeedback`, `QueueRequest`, `StateUpdate`, `Effect` и `GetSnapshot` созданы с ожидаемыми классами.

Этот smoke не запускает обычный клиентский Play lifecycle и не симулирует Heartbeat-сетевую физику. Фактическое следование `Controlled`, obstacle `Spherecast`, все physical-release ветви и полный матч/реванш всё равно требуют Play/Local Server в доступном staging.

## Bake для Edit Mode

Для воспроизводимого обновления статической карты используется:

```powershell
./scripts/bake-editable-place.ps1
```

Процесс строит place без статического корня через `source.project.json`, запускает `WorldBuilder` в Studio, извлекает детерминированный Rojo JSON в `src/world/PannaDistrict.model.json` и собирает `build/Panna-Football.rbxlx` через основной проект. Для отдельной проверки модели можно выполнить `rojo build world.project.json --output build/PannaDistrict.rbxmx`.

Успех bake определяется маркером `PANNA_BAKE_OK`, а не только существованием выходного файла; текущий дневной bake этот маркер выдал и обновил `src/world/PannaDistrict.model.json`. Финальная автоматическая попытка трёх обзорных PNG не удалась: в headless `RunScript` `StudioCaptureService` трижды не стал доступен до таймаута. Поэтому визуальная структура проверена контрактами Studio smoke, но новый screenshot-review не заявляется пройденным.

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

Текущий Studio CLI smoke и исторический room smoke намеренно ограничены и **не доказывают**:

- полный обычный запуск `init.server.lua` и жизненный цикл сервера;
- общую очередь и шесть одновременных комнат;
- полный последовательный переход комнаты `Free → Waiting → Countdown → Active → Result → Free`, timeout ожидания, выход через `ExitPrompt` и реванш;
- симуляцию Heartbeat, сетевую физику и network ownership во время матча;
- корректность/матрицу collision groups в многопользовательской физике, возврат посторонних, movement envelope и фактическую длительность Dash;
- голевой debounce в реальной физике, таймер, overtime или rematch;
- кинематическое следование мяча перед поворотом владельца, отсутствие дрожания, ground loss и `Spherecast` у стен/бортов;
- корректный physical release после каждого из shot/pass/tackle/reset/loss/death/detach путей;
- восстановление Humanoid, камеры, PlayerModule controls, transient input/HUD после результата, выхода, смерти/respawn и двух матчей подряд;
- full-sphere swept goal crossing в реальном Heartbeat на высокой скорости и у физической геометрии стоек/перекладины;
- выполнение `PannaDetector:Begin`/`Step`, успешную/ложную панну и отмену кандидата после чужого касания;
- фактическое выполнение текущей цепочки `ChargeStart → Pass`, ActionFeedback, revisions и malformed-spam защиты в многоклиентном runtime;
- HUD, ContextActionService, mobile/gamepad UX;
- DataStore, уникальность lease при быстром rejoin, unsafe/recovery после save failure, autosave, `BindToClose` и идемпотентность при реальном отключении.

Для этих областей выполните [ручной тест-план](test-plan.md) и не меняйте их статус на «пройдено» без воспроизводимого отчёта.
