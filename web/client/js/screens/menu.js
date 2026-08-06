import { setScreen } from "./manager.js";

export function initMenu(app) {
  const nameEl = document.getElementById("menu-name");
  const statusEl = document.getElementById("menu-status");
  const btnPlay = document.getElementById("btn-play");

  nameEl.value = app.auth?.username || "";

  btnPlay.addEventListener("click", async () => {
    statusEl.textContent = "Signing in...";
    statusEl.classList.remove("error");
    try {
      await app.ensureIdentity(nameEl.value.trim() || app.auth?.username || "");
      app.showLobbyScreen();
    } catch (err) {
      statusEl.textContent = err.message || "Sign in failed";
      statusEl.classList.add("error");
    }
  });

  nameEl.addEventListener("keydown", (e) => {
    if (e.key === "Enter") btnPlay.click();
  });
}

export function showMenu(app) {
  setScreen(app, "menu");
  document.getElementById("menu-name").value = app.auth?.username || "";
  const statusEl = document.getElementById("menu-status");
  statusEl.textContent = app.auth ? `Signed in as ${app.auth.username}` : "";
  statusEl.classList.remove("error");
}
