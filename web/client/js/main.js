import { loadAuth, saveAuth, clearAuth } from "./auth.js";
import * as api from "./api.js";
import { setScreen } from "./screens/manager.js";
import { initMenu, showMenu } from "./screens/menu.js";
import { initLobby, showLobby } from "./screens/lobby.js";
import { initWaiting, showWaiting } from "./screens/waiting.js";
import { Net } from "./game/net.js";
import { HUD } from "./game/hud.js";
import { GameScene } from "./game/GameScene.js";

const Phaser = window.Phaser;
let phaserGame = null;

const app = {
  auth: loadAuth(),
  api,
  currentLobby: null,
  lobbyWs: null,
  game: null
};

async function ensureIdentity(username) {
  if (app.auth?.token) {
    try {
      const me = await api.authMe(app.auth.token);
      if (me) {
        app.auth.username = me.username;
        saveAuth(app.auth);
        return app.auth;
      }
    } catch {
      clearAuth();
      app.auth = null;
    }
  }
  const result = await api.guestSignIn(username);
  const auth = {
    userId: result.id,
    username: result.username,
    token: result.token
  };
  saveAuth(auth);
  app.auth = auth;
  return auth;
}

app.ensureIdentity = ensureIdentity;

function connectLobbyEvents() {
  if (app.lobbyWs) return;
  app.lobbyWs = api.connectLobbyEvents(app.auth.token, {
    onLobbies: (msg) => handleLobbies(msg.lobbies),
    onClose: () => {
      app.lobbyWs = null;
    }
  });
}

function handleLobbies(lobbies) {
  if (app.currentLobby) {
    const updated = lobbies.find((l) => l.id === app.currentLobby.id);
    if (updated) {
      app.currentLobby = updated;
      if (updated.state === "Started" && app.screen === "waiting") {
        startGame();
        return;
      }
      if (app.screen === "waiting") app.waitingRender(updated);
    } else {
      app.currentLobby = null;
      showLobbyScreen();
      return;
    }
  }
  if (app.screen === "lobby") app.lobbyRender(lobbies);
}

app.showMenuScreen = () => {
  app.currentLobby = null;
  hideGameCanvas();
  showMenu(app);
};

app.showLobbyScreen = () => {
  connectLobbyEvents();
  hideGameCanvas();
  showLobby(app);
};

app.enterWaiting = (lobby) => {
  app.currentLobby = lobby;
  showWaiting(app);
};

app.joinRoom = async (lobby) => {
  let password = "";
  if (lobby.isPrivate) {
    password = window.prompt(`Enter password for "${lobby.name}":`) || "";
  }
  try {
    const joined = await api.joinLobby(lobby.id, password, app.auth.token);
    app.enterWaiting(joined);
  } catch (err) {
    if (err.status === 403) {
      window.alert("Wrong password");
    } else {
      window.alert(err.message || "Join failed");
    }
  }
};

app.createRoom = async (roomName, password, maxPlayers) => {
  return api.createLobby({ roomName, password, maxPlayers }, app.auth.token);
};

function showGameCanvas() {
  const c = document.getElementById("game-container");
  if (c) c.classList.remove("hidden");
}
function hideGameCanvas() {
  const c = document.getElementById("game-container");
  if (c) c.classList.add("hidden");
}

async function startGame() {
  const lobby = app.currentLobby;
  if (!lobby || !lobby.serverHost) return;

  showGameCanvas();
  setScreen(app, "game");

  const wsUrl = lobby.serverPort === 443 ? `wss://${lobby.serverHost}` : `ws://${lobby.serverHost}:${lobby.serverPort}`;
  const net = new Net(`${wsUrl}/ws`, app.auth.token, lobby.id);

  try {
    await net.connect();
  } catch (err) {
    window.alert(`Could not join game: ${err.message}`);
    hideGameCanvas();
    app.showLobbyScreen();
    return;
  }

  if (!window.gameHUD) {
    window.gameHUD = new HUD();
  }
  window.gameHUD.show();
  window.gameHUD.hideGameOver();

  if (!phaserGame) {
    phaserGame = new Phaser.Game({
      type: Phaser.WEBGL,
      parent: "game-container",
      width: window.innerWidth,
      height: window.innerHeight,
      backgroundColor: "#0b0b10",
      scale: {
        mode: Phaser.Scale.RESIZE,
        autoCenter: Phaser.Scale.CENTER_BOTH
      },
      scene: [GameScene],
      input: {
        keyboard: true,
        mouse: true,
        touch: true,
        wheel: true
      }
    });
  }

  if (phaserGame.scene.isActive("GameScene")) {
    phaserGame.scene.stop("GameScene");
  }

  phaserGame.scene.start("GameScene", {
    net,
    myUsername: app.auth.username
  });

  app.game = {
    stop: () => {
      if (phaserGame && phaserGame.scene.isActive("GameScene")) {
        phaserGame.scene.stop("GameScene");
      }
      net.close();
    }
  };

  const onEnd = () => {
    if (app.game) {
      app.game.stop();
      app.game = null;
    }
    hideGameCanvas();
    window.gameHUD?.hide();
    window.gameHUD?.hideGameOver();
    app.currentLobby = null;
    app.showLobbyScreen();
  };

  const scene = phaserGame.scene.getScene("GameScene");
  if (scene) {
    scene.onEnd = onEnd;
  }
}

document.getElementById("btn-gameover-back").addEventListener("click", () => {
  if (app.game) {
    app.game.stop();
    app.game = null;
  }
  app.currentLobby = null;
  hideGameCanvas();
  window.gameHUD?.hide();
  window.gameHUD?.hideGameOver();
  app.showLobbyScreen();
});

window.addEventListener("resize", () => {
  if (phaserGame) {
    phaserGame.scale.resize(window.innerWidth, window.innerHeight);
  }
});

initMenu(app);
initLobby(app);
initWaiting(app);
hideGameCanvas();
showMenu(app);

window.__app = app;
