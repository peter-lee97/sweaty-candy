export class HUD {
  constructor() {
    this.el = document.getElementById("hud");
    this.healthFill = document.getElementById("hud-health");
    this.healthText = document.getElementById("hud-health-text");
    this.playersEl = document.getElementById("hud-players");
    this.center = document.getElementById("hud-top-center");
    this.pingEl = document.getElementById("hud-ping");
    this.bottom = document.getElementById("hud-bottom-center");
    this.bannerEl = null;
    this.subEl = null;
    this.gameOverEl = document.getElementById("game-over");
    this.gameOverStats = document.getElementById("gameover-stats");
  }

  show() {
    this.el.classList.remove("hidden");
  }

  hide() {
    this.el.classList.add("hidden");
  }

  setHealth(cur, max) {
    const ratio = Math.max(0, Math.min(1, cur / max));
    this.healthFill.style.width = `${ratio * 100}%`;
    this.healthText.textContent = `${Math.round(cur)}`;
  }

  setPing(rtt) {
    if (rtt <= 0) {
      this.pingEl.textContent = "--";
      return;
    }
    const ms = Math.round(rtt);
    this.pingEl.textContent = `${ms}ms`;
    this.pingEl.className = `ping ${ms <= 150 ? "good" : ms <= 300 ? "fair" : "poor"}`;
  }

  setPlayerList(roster, aliveMap) {
    let html = "";
    for (const [id, name] of roster) {
      const alive = aliveMap?.get(id) ?? true;
      html += `<div class="hud-player ${alive ? "" : "dead"}"><span class="dot" style="background:#7fb2ff"></span><span class="name">${escapeHtml(name)}</span></div>`;
    }
    this.playersEl.innerHTML = html;
  }

  setBanner(text, sub = "") {
    if (text) {
      this.center.innerHTML = `<div id="hud-banner">${escapeHtml(text)}</div>${sub ? `<div id="hud-sub-banner">${escapeHtml(sub)}</div>` : ""}`;
    } else {
      this.center.innerHTML = "";
    }
  }

  setRespawn(text) {
    this.bottom.textContent = text || "";
  }

  showGameOver(stats) {
    this.gameOverStats.textContent = stats;
    this.gameOverEl.classList.remove("hidden");
  }

  hideGameOver() {
    this.gameOverEl.classList.add("hidden");
  }
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
}
