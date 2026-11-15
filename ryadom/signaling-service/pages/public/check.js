const status = document.getElementById('status');
const detail = document.getElementById('detail');
const retry = document.getElementById('retry');

function check() {
  retry.disabled = true;
  status.textContent = 'Проверяем службу поиска…';
  detail.textContent = 'Подождите несколько секунд.';
  let finished = false;
  let ws;
  const timer = setTimeout(() => finish(false), 12000);
  function finish(ok) {
    if (finished) return;
    finished = true;
    clearTimeout(timer);
    if (ws && ws.readyState < WebSocket.CLOSING) ws.close();
    status.textContent = ok ? 'Служба поиска доступна' : 'Не удалось связаться со службой';
    detail.textContent = ok
      ? 'Соединение WebSocket установлено. Сообщите, работает ли эта проверка без VPN на удалённом ПК.'
      : 'Соединение WebSocket не установлено. Сообщите, видите ли вы эту страницу без VPN на удалённом ПК.';
    retry.disabled = false;
  }
  try {
    const url = new URL('/peerjs', location.href);
    url.protocol = location.protocol === 'https:' ? 'wss:' : 'ws:';
    url.search = new URLSearchParams({key:'peerjs', id:'ryadom-client-check-'+crypto.randomUUID(), token:crypto.randomUUID()});
    ws = new WebSocket(url);
    ws.onmessage = event => {
      try { finish(JSON.parse(event.data).type === 'OPEN'); }
      catch { finish(false); }
    };
    ws.onerror = () => finish(false);
    ws.onclose = () => finish(false);
  } catch { finish(false); }
}

retry.addEventListener('click', check);
check();
