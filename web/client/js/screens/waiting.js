import { setScreen } from "./manager.js";

export function initWaiting(app) {
  const nameEl = document.getElementById("waiting-name");
  const idEl = document.getElementById("waiting-id");
  const playersEl = document.getElementById("waiting-players");
  const stateEl = document.getElementById("waiting-state");
  const btnStart = document.getElementById("btn-start");
  const btnLeave = document.getElementById("btn-leave");

  function render(lobby) {
    if (!lobby) return;
    nameEl.textContent = lobby.name;
    idEl.textContent = `ID: ${lobby.id}`;
    playersEl.innerHTML = "";
    const players = lobby.players && lobby.players.length ? lobby.players : [];
    for (const p of players) {
      const row = document.createElement("div");
      row.className = "waiting-player";
      const span = document.createElement("span");
      span.textContent = p.username || p.id;
      row.appendChild(span);
      if (p.id === lobby.ownerUserId) {
        const owner = document.createElement("span");
        owner.className = "owner";
        owner.textContent = "owner";
        row.appendChild(owner);
      }
      playersEl.appendChild(row);
    }
    const isOwner = lobby.ownerUserId === app.auth.userId;
    btnStart.classList.toggle("hidden", !isOwner);
    if (lobby.state === "Started") {
      stateEl.textContent = "Starting game...";
    } else if (lobby.state === "Waiting") {
      stateEl.textContent = isOwner ? "Waiting for players - you can start" : "Waiting for host to start...";
    }
  }

  app.waitingRender = render;

  btnStart.addEventListener("click", async () => {
    stateEl.textContent = "Starting...";
    try {
      await app.api.startLobby(app.currentLobby.id, app.auth.token);
    } catch (err) {
      stateEl.textContent = err.message || "Start failed";
    }
  });

  btnLeave.addEventListener("click", async () => {
    try {
      await app.api.leaveLobby(app.currentLobby.id, app.auth.token);
    } catch {
      /* ignore */
    }
    app.currentLobby = null;
    app.showLobbyScreen();
  });
}

export function showWaiting(app) {
  setScreen(app, "waiting");
  const lobby = app.currentLobby;
  if (lobby) app.waitingRender(lobby);
}
