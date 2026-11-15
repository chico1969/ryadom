export function parseTurnServers(raw: string): RTCIceServer[] {
  if (raw.length > 16384) throw new Error('Конфигурация TURN слишком велика');
  if (!raw.trim()) return [];
  const servers: unknown = JSON.parse(raw);
  if (!Array.isArray(servers) || servers.length > 8) throw new Error('Некорректная конфигурация TURN');
  return servers.map(server => {
    if (!server || Object.keys(server).some(key => !['urls','username','credential'].includes(key)) ||
        !Array.isArray(server.urls) || !server.urls.length || server.urls.length > 8 ||
        typeof server.username !== 'string' || !server.username || server.username.length > 256 ||
        typeof server.credential !== 'string' || !server.credential || server.credential.length > 1024 ||
        server.urls.some((url: unknown) => typeof url !== 'string' || url.length > 1024 || !/^turns?:[^\s/?#@]+(?:\?transport=(?:udp|tcp))?$/.test(url))) {
      throw new Error('Некорректные параметры TURN');
    }
    return {urls:server.urls,username:server.username,credential:server.credential};
  });
}

export const TURN_SERVERS:RTCIceServer[]=[];
export const RELAY_ALLOWED = true;
