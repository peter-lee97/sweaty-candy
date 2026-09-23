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
  const ongoingDetails = document.getElementById("ongoing-details");
  const ongoingSummary = document.getElementById("ongoing-summary");
  const ongoingRows = document.getElementById("ongoing-rows");

  let pollTimer = null;

  function render(rooms) {
    rowsEl.innerHTML = "";
    const open = (rooms || []).filter((r) => r.state === "waiting" && r.currentPlayers < r.maxPlayers);
    const ongoing = (rooms || []).filter((r) => r.state !== "waiting");
    if (open.length === 0) {
      rowsEl.innerHTML = `<tr class="empty-row"><td colspan="4">No rooms available - create one!</td></tr>`;
    }
    for (const room of open) {
      const tr = document.createElement("tr");
      const name = document.createElement("td");
      name.textContent = room.name;
      const players = document.createElement("td");
      players.textContent = `${room.currentPlayers}/${room.maxPlayers}`;
      const status = document.createElement("td");
      status.textContent = room.private ? "Private" : "Open";
      const actions = document.createElement("td");
      const join = document.createElement("button");
      join.className = "join-btn";
      join.textContent = "Join";
      join.addEventListener("click", () => app.joinRoom(room));
      actions.appendChild(join);
      tr.append(name, players, status, actions);
      rowsEl.appendChild(tr);
    }
    ongoingRows.innerHTML = "";
    if (ongoing.length === 0) {
      ongoingDetails.classList.add("hidden");
      return;
    }
    for (const room of ongoing) {
      const tr = document.createElement("tr");
      const name = document.createElement("td");
      name.textContent = room.name;
      const players = document.createElement("td");
      players.textContent = `${room.currentPlayers}/${room.maxPlayers}`;
      const status = document.createElement("td");
      status.className = "ongoing-status";
      status.textContent = "In Progress";
      tr.append(name, players, status);
      ongoingRows.appendChild(tr);
    }
    ongoingSummary.textContent = `Ongoing games (${ongoing.length})`;
    ongoingDetails.classList.remove("hidden");
  }

  async function tick() {
    if (!app.session) return;
    try {
      const rooms = await app.api.listRooms(app.session);
      render(rooms);
      statusEl.textContent = "";
    } catch (err) {
      statusEl.textContent = err.message || "Failed to load rooms";
    }
  }

  function startPolling() {
    stopPolling();
    tick();
    pollTimer = setInterval(tick, 2500);
  }
  function stopPolling() {
    if (pollTimer) {
      clearInterval(pollTimer);
      pollTimer = null;
    }
  }

  app.lobbyRender = render;
  app.lobbyStartPolling = startPolling;
  app.lobbyStopPolling = stopPolling;

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
      const room = await app.createRoom(name, pass, max);
      modal.classList.add("hidden");
      app.enterWaiting(room);
    } catch (err) {
      createStatus.textContent = err.message || "Create failed";
    }
  });

  btnRefresh.addEventListener("click", async () => {
    statusEl.textContent = "Refreshing...";
    await tick();
  });

  btnBack.addEventListener("click", () => app.showMenuScreen());
}

export function showLobby(app) {
  setScreen(app, "lobby");
  document.getElementById("lobby-user").textContent = `Playing as ${app.auth.username}`;
  app.lobbyStartPolling?.();
}
