# Дополнительный адрес службы поиска

Pages Free выдаёт адрес `*.pages.dev`. `_worker.js` направляет только
`/peerjs` и `/health` через Service binding `SIGNAL` в существующий Worker
`ryadom-signaling`. Оба адреса используют один реестр Durable Object:
проверка занятости ID и поиск устройства остаются общими.

В Dashboard: Workers & Pages → Create application → Continue to Pages →
Upload assets. Загрузить содержимое `public` (или ZIP с файлами в корне).
В Settings → Bindings добавить Service binding с именем `SIGNAL`, выбрать
`ryadom-signaling` и повторно развернуть ту же папку. Пароли и API-токены
не нужны. До привязки запросы согласования возвращают 503.

Главная страница устанавливает краткое проверочное WebSocket-соединение
с новым адресом. Успех означает получение протокольного `OPEN`, а не просто
загрузку HTML. Рабочий стол, ICE и TURN эта проверка не затрагивает.

Pages Functions используют общую квоту Workers Free — 100 000 запросов
в сутки. Статические файлы обслуживаются отдельно, через `_routes.json`.
TURN 1000 ГБ к этому тарифу не относится.

На 14.11.2026 опубликован `https://ryadom-connect.pages.dev/`. После второй
публикации привязка действует: `/health` возвращает HTTP 200 и версию 1,
страница в Edge получает WebSocket `OPEN`. Проверочный сценарий сервера
прошёл все три проверки, включая конфликт ID и обмен сообщениями между
`workers.dev` и `pages.dev` через общий реестр. Для повторной проверки задать
`RYADOM_SIGNAL_TEST_URL=wss://ryadom-signaling.chichaslan.workers.dev/peerjs`
и `RYADOM_SIGNAL_SECONDARY_TEST_URL=wss://ryadom-connect.pages.dev/peerjs`,
затем запустить `node --test ../service.test.mjs` из этой папки.

Сначала проверить этот адрес на втором ноутбуке без VPN. До подтверждения
не менять `signaling.json` и не объявлять обычную сеть исправленной.

Документация: [Direct Upload](https://developers.cloudflare.com/pages/get-started/direct-upload/),
[Service bindings](https://developers.cloudflare.com/pages/functions/bindings/#service-bindings),
[квота Free](https://developers.cloudflare.com/pages/functions/pricing/).
