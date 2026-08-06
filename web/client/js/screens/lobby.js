import { setScreen } from "./manager.js";

export function initLobby(app) {
  const rowsEl = document.getElementById("lobby-rows");
  const statusEl = document.getElementById("lobby-status");
  const userEl = document.getElementById("lobby-user");
  const btnCreate = document.getElementById("btn-create");
  const btnRefresh = document.getElementById("btn-refresh");
  const btnBack = document.getElementById("btn-lobby-back");
  const modal = document.getElementById("create-modal");
  const btnConfirm = document.getElementById("btn-create-confirm");
  const btnCancel = document.getElementById("btn-create-cancel");
  const createStatus = document.getElementById("create-status");

  function render(lobbies) {
    const waiting = (lobbies || []).filter((l) => l.state === "Waiting");
    rowsEl.innerHTML = "";
    if (waiting.length === 0) {
      rowsEl.innerHTML = `<tr class="empty-row"><td colspan="4">No rooms available - create one!</td></tr>`;
      return;
    }
    for (const lobby of waiting) {
      const tr = document.createElement("tr");
      const name = document.createElement("td");
      name.textContent = lobby.name;
      const players = document.createElement("td");
      players.textContent = `${lobby.currentPlayers}/${lobby.maxPlayers}`;
      const status = document.createElement("td");
      status.textContent = lobby.isPrivate ? "Private" : "Open";
      const actions = document.createElement("td");
      const join = document.createElement("button");
      join.className = "join-btn";
      join.textContent = "Join";
      join.addEventListener("click", () => app.joinRoom(lobby));
      actions.appendChild(join);
      tr.append(name, players, status, actions);
      rowsEl.appendChild(tr);
    }
  }

  app.lobbyRender = render;

  btnCreate.addEventListener("click", () => {
    modal.classList.remove("hidden");
    document.getElementById("create-name").focus();
  });
  btnCancel.addEventListener("click", () => modal.classList.add("hidden"));
  btnConfirm.addEventListener("click", async () => {
    const name = document.getElementById("create-name").value.trim();
    const pass = document.getElementById("create-pass").value.trim();
    const max = Number(document.getElementById("create-max").value);
    createStatus.textContent = "";
    try {
      const lobby = await app.createRoom(name, pass, max);
      modal.classList.add("hidden");
      app.enterWaiting(lobby);
    } catch (err) {
      createStatus.textContent = err.message || "Create failed";
    }
  });

  btnRefresh.addEventListener("click", async () => {
    statusEl.textContent = "Refreshing...";
    try {
      const data = await app.api.listLobbies();
      render(data.lobbies);
      statusEl.textContent = "";
    } catch (err) {
      statusEl.textContent = err.message || "Refresh failed";
    }
  });

  btnBack.addEventListener("click", () => app.showMenuScreen());
}

export function showLobby(app) {
  setScreen(app, "lobby");
  document.getElementById("lobby-user").textContent = `Playing as ${app.auth.username}`;
  const statusEl = document.getElementById("lobby-status");
  statusEl.textContent = "Loading rooms...";
  app.api
    .listLobbies()
    .then((data) => {
      app.lobbyRender(data.lobbies);
      statusEl.textContent = "";
    })
    .catch((err) => {
      statusEl.textContent = err.message || "Failed to load rooms";
    });
}
