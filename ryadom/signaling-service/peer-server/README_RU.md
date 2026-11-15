# Переносимая служба поиска «Рядом»

Это отдельный сервер согласования на открытом PeerServer 1.0.2 (MIT), а не
публичный узел `0.peerjs.com`. Его можно разместить на площадке с Node.js
или Docker и поддержкой WebSocket. База данных, TURN-пароли, ключ Cloudflare,
пароль удалённого ПК и домен владельца для работы сервера не нужны.

Контейнер использует официальный Node 24 Alpine, закреплённый digest; npm
зависимости закреплены `package-lock.json`. Процесс запускается без root.
Публичный каталог ID выключен, лимит — 128 служебных соединений.
Файлы, звук, экран и команды клиент Рядом передаёт по WebRTC.

Локальный запуск:

```powershell
npm ci --ignore-scripts
npm start
```

В другом терминале `npm test` проверяет занятое имя, поиск по девяти цифрам,
настоящего отправителя и выключенный каталог ID. Запуск Node проверен на
Windows; Dockerfile подготовлен, сборка контейнера пока не запускалась.

Для облачного размещения:

1. Выбрать бесплатный контейнер и ровно один экземпляр.
2. Указать эту папку как build context и `Dockerfile` как файл сборки.
3. Направить публичный HTTPS/WSS на HTTP-порт 9000 контейнера. Переменная PORT
   поддерживается; если площадка задаёт другой порт, настройка должна совпадать.
4. Проверить HTTP `/`: должен вернуться JSON PeerJS Server.
5. Проверить `wss://имя-площадки/peerjs?key=peerjs` с рабочего и удалённого ПК.
6. Только после успешной проверки записать адрес в `../../signaling.json`,
   пересобрать Windows/web и обновить обе стороны.

TLS завершается на платформе. Проверка сертификатов в клиентах сохраняется.
Не запускать несколько экземпляров: реестр имён находится в памяти процесса.
После рестарта регистрации восстанавливаются клиентами. Доступ к ПК всё равно
требует отдельной парольной авторизации или разрешения владельца.

### alwaysdata Free

Для личного хостинга проверены опубликованные условия Free: 0 €, 1 ГБ диска,
256 МБ RAM и 0.25 CPU; регистрация без карты, без срока окончания. Без карты
применяются более строгие HTTP-фильтры — реальный WebSocket пока нужно проверить.

1. Выбрать Free и создать хостинг, не покупать домен.
2. Загрузить эту папку в `/home/<account>/ryadom-signaling/`.
3. Использовать Node 24 (`NODEJS_VERSION=24`), выполнить в папке
   `npm ci --omit=dev --ignore-scripts`.
4. Создать сайт типа Node.js с командой
   `node /home/<account>/ryadom-signaling/server.mjs` и адресом
   `<account>.alwaysdata.net`. `IP`/`HOST` и `PORT` берутся из среды площадки.
5. Для долгих WebSocket-соединений установить Max idle time в 0, как указано
   в инструкции площадки. Не включать дополнительное проксирование Cloudflare.
6. Проверить HTTPS и `wss://<account>.alwaysdata.net/peerjs` с обоих ПК без VPN.
   Лишь после успешной проверки менять адрес в приложении.

`/health` отвечает JSON с именем службы, `/check` открывает браузерную
проверку реального WebSocket `OPEN`. Эти ответы отправляются с `no-store`,
чтобы загрузка из кэша не принималась за доступность службы.

Проверка сайта и кабинета из сети второго ноутбука прошла со слов владельца.
Это не подтверждает доступность будущего адреса приложения и WebSocket.

## Проверка площадок на 14.11.2026

- Northflank: пользователь сообщил, что сайт доступен без VPN, но регистрация
  закрыта (`Signup is currently disabled`). Ничего не размещено. Тарифная
  страница обещает отсутствие карты, документация billing требует её для всех
  планов; запуск без карты не подтверждён.
- Hugging Face: актуальные документы требуют платную подписку для создания
  Docker/Gradio Spaces, включая CPU Basic. Этот вариант исключён при бюджете 0 ₽.
- Back4app Containers: официальный тариф Free заявляет $0, 256 МБ RAM,
  0.25 CPU и отсутствие требования карты. В кабинете принята папка из девяти
  подготовленных файлов, приложение не создано. Актуальная документация и
  кабинет указывают срок публичного URL Free — 60 минут. Поэтому этот тариф
  исключён для постоянной службы поиска; платный тариф не подключался.
- Render: входящий трафик Web Services проходит через Cloudflare; не выбран
  следующим основным кандидатом из-за уже наблюдаемой сетевой проблемы.
- alwaysdata: выбран для следующей практической проверки; до развёртывания
  и теста WebSocket не объявляется рабочей заменой.

Приложение пока использует прежний адрес из `signaling.json`. Наличие этого
контейнера не означает, что проблема доступа без VPN уже исправлена.

Источники: [PeerServer](https://github.com/peers/peerjs-server),
[Northflank billing](https://northflank.com/docs/v1/application/billing/pricing-on-northflank),
[Hugging Face Spaces](https://huggingface.co/docs/hub/spaces-overview),
[Back4app Containers Free](https://www.back4app.com/pricing/container-as-a-service),
[Back4app: срок URL Free](https://www.back4app.com/blog/host-a-static-website-in-a-container),
[Back4app WebSocket](https://blog.back4app.com/containers-update-metrics-custom-domain-websockets-and-more/).

alwaysdata: [Free](https://www.alwaysdata.com/en/offers/),
[регистрация без карты](https://www.alwaysdata.com/en/),
[режим без карты](https://help.alwaysdata.com/en/docs/admin-billing/profile/restricted-mode/),
[Node.js](https://help.alwaysdata.com/en/docs/web-hosting/languages/nodejs/configuration/),
[WebSocket](https://help.alwaysdata.com/en/blog/2023-03-14-hold-on-to-your-socks-high-speed-data-stream-hosting-with-websockets/).
Render: [входящий трафик](https://render.com/articles/how-render-handles-ddos-attacks).
