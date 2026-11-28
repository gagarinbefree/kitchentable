# KitchenTable

Текстовый чат для Android. Flutter-клиент использует стандартные компоненты Material 3, Riverpod и SignalR. ASP.NET Core принимает команды через MediatR и сохраняет сообщения в PostgreSQL. Идентификатор отправителя хранится на устройстве. При первом подключении сервер выдаёт установке личный номер. На главном экране откройте «Добавить абонента» и покажите свой QR-код собеседнику. На втором телефоне откройте «Добавить абонента», нажмите «Сканировать QR» и подтвердите добавление. Код действует пять минут. После подтверждения контакт появляется у обоих, даже если переписка ещё пуста. Нажмите на абонента в списке, чтобы написать ему.

На экране «Абоненты» нажмите карандаш рядом со своим номером или контактом, чтобы изменить имя. Имя видно только на этом устройстве. Чтобы вернуть исходную подпись, очистите поле и сохраните.

На экране «Абоненты» откройте настройки кнопкой с шестерёнкой. Выберите светлое или чёрное оформление в стиле ZX Spectrum. Выбор сохраняется на устройстве.

## Сервер на Linux

Рабочий каталог на `192.168.31.84` — `~/kitchentable`. В нём находятся `compose.yaml`, `server/` и `client/`. Для первой установки создайте в корне файл `.env` с правами `600`. Укажите `CHAT_BIND=192.168.31.84` и `POSTGRES_PASSWORD` со случайным шестнадцатеричным паролем. Последующие запуски используют тот же файл.

```sh
cd ~/kitchentable
docker --context default compose -p kitchentable up -d --build db server
curl -fsS -o /dev/null -w '%{http_code}\n' http://192.168.31.84:8787/health
```

Проверка готовности возвращает HTTP 200. Личные сообщения используют SignalR-хаб `/direct`. Сервер определяет отправителя личного сообщения по секрету установки и хранит хеш секрета в PostgreSQL. Номер служит для отображения в списке. Добавление контакта требует действующего QR-приглашения. Очистка данных приложения создаёт нового абонента. Текущий стенд доступен по HTTP внутри локальной сети. Порт PostgreSQL доступен внутри сети Compose. Именованный том `kitchentable_messages` сохраняет переписку при пересоздании контейнеров. Телеметрия Hawk в текущем запуске выключена.

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

Перед первым запуском свяжите две установки приложения через QR и убедитесь, что каждая показывает второго абонента. В этом SSH-сеансе выполните тест. Он отправляет личное сообщение, проверяет ответ и догрузку после закрытия приложения получателя. Для двух отдельных Android-устройств замените `--peer-user 10` серийным номером второго устройства из `adb devices`.

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

Разрабатываем на Windows. До решения об отправке изменений сервер и интеграционные тесты с PostgreSQL и SignalR запускаем на Linux 192.168.31.84. Локальный Android-клиент собираем на Windows. Сквозной сценарий для двух абонентов и тесты интерфейса запускаем локально. PVS-Studio используем при локальной проверке C#.

После отправки коммита GitHub Actions на временных Ubuntu-машинах выполняет юнит-тесты сервера (`Category=Unit`) и клиента (`client/test/unit`), анализ Dart и сборку серверного Docker-образа. Для pull request доступен отладочный APK. Интеграционные тесты и эмулятор остаются в локальном процессе разработки.

Для `main` Actions собирает подписанный APK, отправляет проверенный серверный образ в GHCR и разворачивает его по digest на 157.22.180.167. Nginx обслуживает HTTPS и WebSocket на `https://gagarinbefree.clodocd.com:9443`. После проверки `/health` APK публикуется в GitHub Releases. При ошибке проверки нового образа контроллер восстанавливает предыдущий активный образ, если он существует. Данные PostgreSQL хранятся в томе `kitchentable_messages` на production-хосте.

Файлы production Compose, контроллера и nginx находятся в `deploy/`. Они устанавливаются администратором. SSH-ключ Actions ограничен запуском контроллера. Пароль PostgreSQL хранится на сервере. Секреты деплоя и подписи находятся в окружениях GitHub `production` и `android-signing`, разрешённых для ветки `main`.
