export default {
  fetch(request, env) {
    const path = new URL(request.url).pathname;
    if (path === '/peerjs' || path.startsWith('/peerjs/') || path === '/health') {
      if (!env.SIGNAL) return new Response('Signaling binding is not configured', {status:503});
      return env.SIGNAL.fetch(request);
    }
    return env.ASSETS.fetch(request);
  }
};
