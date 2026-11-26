# KitchenTable

Текстовый чат для Android. Flutter-клиент использует Forui, Riverpod и SignalR. ASP.NET Core принимает команды через MediatR и сохраняет сообщения в PostgreSQL. Идентификатор отправителя хранится на устройстве. При первом подключении сервер выдаёт установке личный номер. На главном экране показаны свой номер и входящие диалоги. Чтобы написать, введите номер получателя и нажмите «Открыть». Для ответа нажмите на входящий диалог. Кнопка «Общий чат» открывает отдельную публичную переписку.

## Сервер на Linux

Рабочий каталог на `192.168.31.84` — `~/kitchentable`. В нём находятся `compose.yaml`, `server/` и `client/`. Для первой установки создайте в корне файл `.env` с правами `600`. Укажите `CHAT_BIND=192.168.31.84` и `POSTGRES_PASSWORD` со случайным шестнадцатеричным паролем. Последующие запуски используют тот же файл.

```sh
cd ~/kitchentable
docker --context default compose -p kitchentable up -d --build db server
curl -fsS -o /dev/null -w '%{http_code}\n' http://192.168.31.84:8787/health
```

Проверка готовности возвращает HTTP 200. Личные сообщения используют SignalR-хаб `/direct`, общий чат — `/chat`. Сервер определяет отправителя личного сообщения по секрету установки и хранит хеш секрета в PostgreSQL. Номер можно передать собеседнику. Очистка данных приложения создаёт нового абонента. Текущий стенд доступен по HTTP внутри локальной сети. Порт PostgreSQL доступен внутри сети Compose. Именованный том `kitchentable_messages` сохраняет переписку при пересоздании контейнеров. Телеметрия Hawk в текущем запуске выключена.

## Android на Windows

```powershell
cd C:\vs\kitchentable\client
$env:GRADLE_USER_HOME = 'D:\windows\Gradle'
flutter pub get
flutter run -d emulator-5554
```

На рабочем Windows-компьютере для KitchenTable настроен эмулятор `KitchenTablePeer_API35` с аппаратной графикой Radeon. Для холодного запуска одного экземпляра выполните `.\emulator.exe -avd KitchenTablePeer_API35 -no-snapshot` из каталога Android SDK `emulator/`. Android-устройству нужен доступ к адресу Linux-сервера. Второй экземпляр приложения можно запустить на другом эмуляторе или телефоне в той же сети. Для отдельной сборки используйте `flutter build apk --debug`. APK появится в `client/build/app/outputs/flutter-apk/app-debug.apk`.

## Тесты на Linux

Проверки Flutter используют SDK 3.50.1. На указанном хосте он установлен в `~/kitchentable/.tools/flutter`.

```sh
cd ~/kitchentable/client
../.tools/flutter/bin/flutter pub get
../.tools/flutter/bin/flutter analyze
../.tools/flutter/bin/flutter test
```

Доменным и интеграционным тестам выделен Compose-проект `kitchentable-verify` со своим томом PostgreSQL. Выполняйте команды из корня проекта в отдельной оболочке:

```sh
cd ~/kitchentable
export CHAT_BIND=127.0.0.1 CHAT_PORT=28787
docker --context default compose -p kitchentable-verify build server tests
docker --context default compose -p kitchentable-verify up -d db server
until curl -fsS http://127.0.0.1:28787/health; do sleep 1; done
docker --context default compose -p kitchentable-verify run --rm tests
docker --context default compose -p kitchentable-verify down
```

Сквозной тест запускается на Linux. На Windows работает один эмулятор. Основной и тестовый профили Android используют один APK и получают разные номера абонентов. Для подготовки второго профиля на новом эмуляторе выполните на Windows следующие команды. Вместо <ID> подставьте число, которое вернула первая команда.

```powershell
adb -s emulator-5554 shell pm create-user --profileOf 0 --managed KitchenTablePeer
adb -s emulator-5554 shell am start-user -w <ID>
adb -s emulator-5554 shell cmd package install-existing --user <ID> com.example.kitchentable
```

На имеющемся эмуляторе профиль уже создан с ID 10. Оставьте Windows ADB запущенным. Из PowerShell откройте SSH-сеанс с обратным туннелем, доступным только на loopback.

```powershell
ssh -o ExitOnForwardFailure=yes -R 127.0.0.1:15037:127.0.0.1:5037 -i "$env:USERPROFILE\.ssh\linux_192_168_31_84" gagarin@192.168.31.84
```

В этом SSH-сеансе выполните тест. Он отправляет личное сообщение, проверяет ответ и догрузку после закрытия приложения получателя. Для двух отдельных Android-устройств замените `--peer-user 10` серийным номером второго устройства из `adb devices`.

```sh
cd ~/kitchentable
export ADB_SERVER_SOCKET=tcp:127.0.0.1:15037 ADB="$PWD/.tools/platform-tools/adb"
python3 client/test/android_chat_smoke.py emulator-5554 --peer-user 10
```

После перезапуска серверного сервиса добавьте к команде `--expect МАРКЕР`, подставив маркер из вывода предыдущего запуска. Тест перезапустит оба клиента и найдёт сохранённое сообщение в обеих историях.

## Статический анализ C#

На Windows используйте локальную установку PVS-Studio:

```powershell
cd C:\vs\kitchentable
dotnet restore server/src/KitchenTable.Server.csproj
& 'D:\windows\PVS-Studio\PVS-Studio_Cmd.exe' -t server/src/KitchenTable.Server.csproj -c Release -o server/KitchenTable.plog
```

## GitHub Actions и production

Workflow `Test, build and deploy` запускается при push в `main`, при pull request и вручную. На исполнителе `kt-linux` (192.168.31.84) выполняются анализ Dart, тесты Flutter, сборка Docker и интеграционные тесты ASP.NET Core с отдельной PostgreSQL. Для временного стенда используется Compose-проект `kitchentable-actions` и порт 28788.

Исполнитель `kt-windows` запускает PVS-Studio, собирает тестовый APK с отдельным идентификатором приложения и устанавливает его в профили 0 и 10 эмулятора KitchenTablePeer_API35. Эмулятор должен быть запущен на Windows на порту 5554. Сквозной тест переписки выполняется на Linux через временный SSH-туннель. Для PR из внешнего форка GitHub требует одобрения запуска. Сквозной тест с секретом стенда доступен веткам основного репозитория.

Для `main` Windows собирает и подписывает APK для телефонов. Проверенный серверный образ публикуется в GHCR и разворачивается по digest на 157.22.180.167. Nginx обслуживает `https://gagarinbefree.clodocd.com:9443`, включая WebSocket. После проверки `/health` APK публикуется в GitHub Releases. При неудачной проверке нового образа контроллер восстанавливает предыдущий активный образ, если он существует. Данные PostgreSQL хранятся в томе `kitchentable_messages` на production-хосте.

Production Compose, контроллер и конфигурация nginx находятся в `deploy/`. На сервере они устанавливаются администратором. Ключ Actions ограничен запуском контроллера, паролем PostgreSQL управляет сервер. Ключи подписи APK и ключ деплоя хранятся в отдельных окружениях GitHub, доступных для ветки `main`.
