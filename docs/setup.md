# Локальная разработка

## 1. Требования

Установите:

1. Roblox Studio.
2. Rojo 7.x и одноимённый плагин Studio. Версии CLI и плагина должны быть совместимы.
3. Git.
4. По желанию — StyLua для форматирования и Selene для статического анализа.

Проверьте доступность инструментов:

```powershell
rojo --version
git --version
```

Проект не устанавливает пакеты из интернета при запуске и не зависит от внешних Roblox-моделей. Лобби, арены, ворота и служебные зоны создаются кодом из стандартных Instances.

## 2. Получение проекта

Клонируйте репозиторий безопасным способом. Не помещайте Personal Access Token в URL:

```powershell
git clone https://github.com/mokydek/Panna.git
cd Panna
```

Для GitHub используйте вход через Git Credential Manager или `gh auth login`. Секрет не должен появляться в терминальной истории, `.git/config`, исходном коде или коммите.

## 3. Синхронизация Rojo

Из корня репозитория выполните:

```powershell
rojo serve default.project.json
```

По умолчанию проект использует порт `34872`. Затем:

1. Откройте новый Baseplate или отдельный тестовый place в Roblox Studio.
2. Откройте плагин Rojo.
3. Подключитесь к `localhost:34872`.
4. Убедитесь, что появились:
   - `ReplicatedStorage/PannaShared`;
   - `ServerScriptService/PannaServer`;
   - `StarterPlayer/StarterPlayerScripts/PannaClient`;
   - `Workspace/PannaDistrict` с шестью комнатами.
5. Не редактируйте синхронизируемые скрипты одновременно в Studio и в рабочей папке: следующая синхронизация может затереть изменения Studio.

`Workspace.StreamingEnabled` задаётся проектом. Основной `default.project.json` подключает запечённую `src/world/PannaDistrict.model.json`, поэтому район виден в Edit Mode. Сервер проверяет/инициализирует этот корень при запуске; `source.project.json` без модели используется только bake-процессом для чистой процедурной регенерации.

После изменения `WorldBuilder.lua` обновите редактируемую модель и place:

```powershell
./scripts/bake-editable-place.ps1
```

Команда перезаписывает `src/world/PannaDistrict.model.json` воспроизводимым экспортом и создаёт `build/Panna-Football.rbxlx`. Проверьте diff модели и не редактируйте её вручную как обычный JSON.

## 4. Локальный многопользовательский запуск

Для проверки полного цикла нужен минимум сервер и два клиента:

1. В Studio откройте **Test**.
2. Выберите режим локального сервера.
3. Установите число игроков `2`.
4. Запустите сессию.
5. На обоих клиентах войдите в очередь и проверьте распределение на арену.

Обычный **Play Solo** подходит для проверки загрузки интерфейса, района и отсутствия ошибок, но не подтверждает работу матча 1v1.

Для автоматизированного сценария с четырьмя клиентами и двумя комнатами используется отдельный тестовый place:

```powershell
rojo build multiplayer.project.json --output build/Panna-multiplayer-test.rbxlx
```

`multiplayer.project.json` подключает тот же `src/shared`, `src/server`, `src/client` и запечённый `PannaDistrict`, но дополнительно помещает `tests/multiplayer-server.server.lua` и `tests/multiplayer-client.client.lua` в place. Эти тестовые скрипты не входят в основной `default.project.json`; драйвер и текущий статус описаны в [фактических проверках](TESTING.md).

## 5. DataStore в Studio

Не включайте доступ Studio к API Services в основном опубликованном Experience ради удобства разработки. Рекомендуемый порядок:

1. Создайте отдельный тестовый Experience.
2. Откройте **Game Settings → Security**.
3. Включите Studio Access to API Services только для тестового Experience.
4. Убедитесь, что тестируете ожидаемое хранилище: текущий сервис автоматически добавляет суффикс `_Studio` к имени DataStore при запуске в Studio.
5. При изменении схемы данных всё равно увеличьте `SchemaVersion` и проверьте миграцию на копии тестовых данных.

В непубликованном локальном place сам вызов получения DataStore может быть недоступен. Сервис перехватывает эту ошибку и создаёт session-only профиль: игрок получает `DataLoaded = true` и `DataSessionFallback = true`, может проверять локальную механику в Studio, но прогресс не сохраняется и награды не применяются. В опубликованном сервере fallback-профиль также не допускается в рейтинговую очередь. Даже при выключенном API Services игра должна корректно переживать ошибку загрузки/сохранения, не выдавая повторные награды. Фактическое поведение проверяется по [тест-плану](test-plan.md).

## 6. Локальные проверки

Read-only проверка репозитория:

```powershell
./scripts/validate-project.ps1
```

Если Windows запрещает прямой запуск скрипта текущей Execution Policy:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ./scripts/validate-project.ps1
```

Если установлены инструменты качества:

```powershell
stylua --check src
selene src
```

При необходимости можно собрать place-файл для ручной проверки:

```powershell
rojo build default.project.json --output Panna-test.rbxlx
```

`Panna-test.rbxlx` — локальный артефакт; не добавляйте его в Git. Сборка Rojo подтверждает структуру проекта, но не заменяет запуск сервера Roblox.

## 7. Типичные проблемы

### Плагин не видит сервер

- проверьте, что `rojo serve` продолжает работать;
- используйте порт `34872`;
- убедитесь, что firewall не блокирует локальное соединение;
- сравните версии Rojo CLI и плагина.

### В Studio нет карты

Убедитесь, что запущен именно `default.project.json`, существует `src/world/PannaDistrict.model.json` и Rojo синхронизировал `Workspace/PannaDistrict`. Если модель устарела или отсутствует, выполните `./scripts/bake-editable-place.ps1` и повторите подключение.

### Матч не начинается

- нужен второй игрок;
- оба игрока должны быть вне активного матча и войти в одну комнату через `EntryPrompt` либо в общую очередь;
- проверьте Server Output на ошибки;
- убедитесь, что все шесть комнат имеют полный набор служебных объектов из [контракта мира](world-contract.md).

### Сохранения не работают

Это ожидаемо в непубликованном place или при выключенном Studio API Access. В таком запуске проверьте `DataSessionFallback = true`: профиль существует только до остановки серверной сессии. Не отключайте обработку ошибок и не подменяйте её локальной выдачей наград в рабочем коде.
