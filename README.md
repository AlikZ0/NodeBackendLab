# Node Backend Lab

Приложение на SwiftUI для iPhone и iPad с iOS 16+. Короткая теория по-русски, восемь заданий с редактором кода, подсказки и автоматическая проверка. Код и отметки о прохождении хранятся на устройстве. Для уроков интернет не нужен.

На iPhone проверяется JavaScript в WebKit. Node.js, его встроенные модули и реальные HTTP-запросы используются в папке `Practice` на Ubuntu.

## Сборка с Ubuntu через GitHub

1. Распакуй архив. Создай на GitHub пустой репозиторий `NodeBackendLab` без README. В терминале Ubuntu открой распакованную папку `NodeBackendLab`.
2. Замени `USERNAME` именем своего аккаунта и отправь исходники на GitHub. Если Git запросит вход по HTTPS, используй авторизацию GitHub CLI или настроенный менеджер учётных данных.

   ```bash
   git init -b main
   git add .
   git commit -m "Add Node Backend Lab"
   git remote add origin https://github.com/USERNAME/NodeBackendLab.git
   git push -u origin main
   ```

3. Открой **Actions → iOS IPA**. Сборка стартует при первом push. Запуск вручную доступен через **Run workflow**. GitHub собирает приложение на macOS-раннере. Если сборка падает, открой лог шага **Build for iPhone**.
4. В успешном запуске скачай **NodeBackendLab-iOS** из **Artifacts** и распакуй ZIP. Внутри будет `NodeBackendLab.ipa`.

## Установка на iPhone

IPA из GitHub без подписи. Подпись выполняется при установке через SideStore. Apple ID и сертификаты в GitHub добавлять не нужно.

1. Установи SideStore на iPhone с Ubuntu по [официальной инструкции](https://docs.sidestore.io/docs/installation/install). Понадобятся USB-кабель, Apple Account, iLoader и LocalDevVPN. Если iOS запросит режим разработчика, включи его по инструкции.
2. Перенеси `NodeBackendLab.ipa` в «Файлы» на iPhone. Подключись к Wi-Fi, включи LocalDevVPN, открой SideStore → **My Apps → +** и выбери IPA.
3. При бесплатной подписи обновляй её в SideStore до истечения семи дней. Если SideStore уже установлен, начни с шага 2.

## Практика на Ubuntu

Для практики подойдёт Node.js 20 или новее. npm-пакеты устанавливать не нужно. В `tasks.mjs` находятся заготовки. Команды для каждого этапа есть в уроках.

```bash
cd Practice
node -v
node --test --test-name-pattern=validation tasks.test.mjs
```

Первый тест ожидаемо падает, пока `normalizeTitle` возвращает `null` для всех входных данных. Выполни задание «Валидация запроса», затем запусти тест повторно. После реализации всех шести функций выполни `node --test`: тесты проверят функции и сделают настоящие HTTP-запросы.

Запусти `node server.mjs` в одном терминале. В другом создай задачу и запроси список.

```bash
curl -i -X POST http://127.0.0.1:3000/tasks \
  -H 'Content-Type: application/json' \
  -d '{"title":"Пройти урок Node.js"}'
curl -i 'http://127.0.0.1:3000/tasks?offset=0&limit=10'
```

Ожидаемые статусы — 201 и 200. Учебный сервер слушает только локальный адрес. Задачи живут в памяти до перезапуска.

После этого можешь развить API в портфолио: подключить PostgreSQL вместо массива, добавить PATCH и DELETE и написать для них интеграционные тесты.
