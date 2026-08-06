export async function api(path, opts = {}) {
  const headers = { ...(opts.headers || {}) };
  if (opts.body !== undefined) headers["Content-Type"] = "application/json";
  const res = await fetch(path, {
    method: opts.method || "GET",
    headers,
    body: opts.body !== undefined ? JSON.stringify(opts.body) : undefined
  });
  let data = null;
  try {
    data = await res.json();
  } catch {
    data = null;
  }
  if (!res.ok) {
    const err = new Error(data?.error || `HTTP ${res.status}`);
    err.status = res.status;
    err.data = data;
    throw err;
  }
  return data;
}

export function guestSignIn(username) {
  return api("/v1/auth/guest", { method: "POST", body: { username: username || "" } });
}

export function authMe(token) {
  return api("/v1/auth/me", { headers: { Authorization: `Bearer ${token}` } });
}

export function listLobbies() {
  return api("/v1/lobbies");
}

export function createLobby(body, token) {
  return api("/v1/lobbies", { method: "POST", body, headers: { Authorization: `Bearer ${token}` } });
}

export function joinLobby(id, password, token) {
  return api(`/v1/lobbies/${id}/join`, {
    method: "POST",
    body: password ? { password } : {},
    headers: { Authorization: `Bearer ${token}` }
  });
}

export function leaveLobby(id, token) {
  return api(`/v1/lobbies/${id}/leave`, { method: "POST", headers: { Authorization: `Bearer ${token}` } });
}

export function startLobby(id, token) {
  return api(`/v1/lobbies/${id}/start`, { method: "POST", headers: { Authorization: `Bearer ${token}` } });
}

export function connectLobbyEvents(token, handlers) {
  const proto = location.protocol === "https:" ? "wss" : "ws";
  const ws = new WebSocket(`${proto}://${location.host}/v1/lobbies/events?token=${encodeURIComponent(token)}`);
  ws.onmessage = (ev) => {
    try {
      const msg = JSON.parse(ev.data);
      handlers.onLobbies?.(msg);
    } catch {
      /* ignore malformed */
    }
  };
  ws.onclose = () => handlers.onClose?.();
  return ws;
}
