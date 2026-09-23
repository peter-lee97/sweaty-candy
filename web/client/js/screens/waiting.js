import { setScreen } from "./manager.js";

export function initWaiting(app) {
  const nameEl = document.getElementById("waiting-name");
  const idEl = document.getElementById("waiting-id");
  const playersEl = document.getElementById("waiting-players");
  const stateEl = document.getElementById("waiting-state");
  const btnStart = document.getElementById("btn-start");
  const btnLeave = document.getElementById("btn-leave");

  function render(info) {
    const room = app.currentRoom;
    if (!room) return;
    room.name = info.name || room.name;
    room.ownerId = info.ownerId || room.ownerId;
    room.maxPlayers = info.maxPlayers || room.maxPlayers;
    room.players = info.players || [];

    nameEl.textContent = room.name;
    idEl.textContent = `ID: ${room.matchId}`;
    playersEl.innerHTML = "";
    for (const p of room.players) {
      const row = document.createElement("div");
      row.className = "waiting-player";
      const span = document.createElement("span");
      span.textContent = p.username || p.userId;
      row.appendChild(span);
      if (p.userId === room.ownerId) {
        const owner = document.createElement("span");
        owner.className = "owner";
        owner.textContent = "owner";
        row.appendChild(owner);
      }
      playersEl.appendChild(row);
    }
    const isOwner = room.ownerId === app.auth.userId;
    btnStart.classList.toggle("hidden", !isOwner);
    stateEl.textContent = isOwner ? "Waiting for players - you can start" : "Waiting for host to start...";
  }

  app.waitingRender = render;

  btnStart.addEventListener("click", () => {
    stateEl.textContent = "Starting...";
    app.socket.sendMatchState(app.currentRoom.matchId, app.api.OP.START, JSON.stringify({})).catch(() => {});
  });

  btnLeave.addEventListener("click", async () => {
    const room = app.currentRoom;
    app.currentRoom = null;
    if (room) {
      try {
        await app.socket.leaveMatch(room.matchId);
      } catch {
        /* ignore */
      }
    }
    app.showLobbyScreen();
  });
}

export function showWaiting(app) {
  setScreen(app, "waiting");
  const room = app.currentRoom;
  if (!room) return;
  app.waitingRender({
    name: room.name,
    ownerId: room.ownerId,
    maxPlayers: room.maxPlayers,
    players: room.players || []
  });
}
