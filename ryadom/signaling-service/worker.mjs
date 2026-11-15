import { DurableObject } from 'cloudflare:workers';

const validId = id => typeof id === 'string' && /^ryadom-(?:[a-f0-9]{32}|lookup-[a-f0-9]{32}|client-[a-zA-Z0-9_-]{1,60}|code-[1-9][0-9]{8})$/.test(id);
function liveSockets(ctx, tag) {
  return ctx.getWebSockets(tag).filter(ws => {
    if (ws.readyState !== 1) return false;
    const seen = ctx.getWebSocketAutoResponseTimestamp(ws)?.getTime() ?? ws.deserializeAttachment()?.joinedAt ?? 0;
    if (Date.now() - seen < 30000) return true;
    ws.close(1001, 'Registration expired');return false;
  });
}
const reply = (ws, type, payload) => ws.send(JSON.stringify({ type, ...(payload ? {payload} : {}) }));

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === '/health') return Response.json({service:'ryadom-signaling',version:1});
    if (url.pathname !== '/peerjs' || request.headers.get('Upgrade')?.toLowerCase() !== 'websocket') {
      return new Response('Ryadom signaling service', {status:404});
    }
    if (!validId(url.searchParams.get('id'))) return new Response('Invalid device name', {status:400});
    return env.SIGNALS.getByName('family-v1').fetch(request);
  }
};

export class SignalHub extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair('{"type":"HEARTBEAT"}', '{"type":"HEARTBEAT"}'));
  }
  async fetch(request) {
    const id = new URL(request.url).searchParams.get('id');
    if (!validId(id)) return new Response('Invalid device name', {status:400});
    const [client, server] = Object.values(new WebSocketPair());
    if (liveSockets(this.ctx, id).length) {
      server.accept(); reply(server, 'ID-TAKEN'); server.close(1008, 'ID already registered');
      return new Response(null, {status:101,webSocket:client});
    }
    if (liveSockets(this.ctx).length >= 128) return new Response('Family service capacity reached', {status:503});
    this.ctx.acceptWebSocket(server, [id]);
    server.serializeAttachment({id,joinedAt:Date.now(),window:Date.now(),messages:0,bytes:0});
    reply(server, 'OPEN');
    return new Response(null, {status:101,webSocket:client});
  }
  webSocketMessage(ws, raw) {
    if (typeof raw !== 'string' || raw.length > 131072) {ws.close(1009, 'Signaling message too large');return;}
    const state = ws.deserializeAttachment();
    if (!state || !validId(state.id)) {ws.close(1008, 'Registration required');return;}
    const now = Date.now();
    if (now - state.window > 1000) {state.window=now;state.messages=0;state.bytes=0;}
    if (++state.messages > 80 || (state.bytes += raw.length) > 524288) {ws.close(1008, 'Signaling rate exceeded');return;}
    ws.serializeAttachment(state);
    let message;
    try {message=JSON.parse(raw);} catch {ws.close(1008,'Invalid JSON');return;}
    if (message?.type === 'HEARTBEAT') return;
    if (!['OFFER','ANSWER','CANDIDATE'].includes(message?.type) || !validId(message.dst) || message.dst === state.id || !message.payload || typeof message.payload !== 'object' || Array.isArray(message.payload)) {
      ws.close(1008, 'Only session negotiation is permitted');return;
    }
    const target = liveSockets(this.ctx, message.dst)[0];
    if (!target) {reply(ws, 'EXPIRE');return;}
    target.send(JSON.stringify({type:message.type,src:state.id,dst:message.dst,payload:message.payload}));
  }
  webSocketClose(ws) {ws.close(1000, 'Closed');}
  webSocketError(ws) {ws.close(1011, 'Signaling connection failed');}
}
