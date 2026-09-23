import { loadAuth } from "./auth.js";
import * as nakama from "./nakama.js";
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
  session: null,
  socket: null,
  currentRoom: null,
  latestRoomInfo: null,
  game: null,
  api: nakama
};

app.ensureIdentity = (username) => nakama.ensureIdentity(app, username);

function wireSocket() {
  if (!app.socket) return;
  app.socket.onmatchdata = (md) => {
    if (md.op_code === nakama.OP.START) {
      if (app.screen === "waiting" && app.currentRoom) {
        startGame();
      }
      return;
    }
    if (md.op_code === nakama.OP.ROOMINFO) {
      try {
        const info = JSON.parse(nakama.decodeData(md.data));
        app.latestRoomInfo = info;
        if (app.currentRoom) {
          app.currentRoom.name = info.name || app.currentRoom.name;
          app.currentRoom.ownerId = info.ownerId || app.currentRoom.ownerId;
          app.currentRoom.maxPlayers = info.maxPlayers || app.currentRoom.maxPlayers;
          app.currentRoom.players = info.players || [];
        }
        if (app.screen === "waiting") {
          app.waitingRender(info);
        }
      } catch {
        /* ignore malformed */
      }
      return;
    }
    if (app.game && app.game.net) {
      app.game.net.handleMatchData(md);
    }
  };
}

app.showMenuScreen = () => {
  app.currentRoom = null;
  app.lobbyStopPolling?.();
  hideGameCanvas();
  showMenu(app);
};

app.showLobbyScreen = async () => {
  hideGameCanvas();
  setScreen(app, "lobby");
  try {
    if (!app.socket) {
      app.socket = await nakama.connectSocket(app.session);
      wireSocket();
    }
  } catch (err) {
    const status = document.getElementById("lobby-status");
    if (status) status.textContent = err.message || "Failed to connect";
  }
  showLobby(app);
};

app.enterWaiting = (room) => {
  app.currentRoom = room;
  if (app.latestRoomInfo) {
    room.players = app.latestRoomInfo.players || [];
    room.ownerId = app.latestRoomInfo.ownerId || room.ownerId;
    room.maxPlayers = app.latestRoomInfo.maxPlayers || room.maxPlayers;
  }
  app.lobbyStopPolling?.();
  showWaiting(app);
};

app.joinRoom = async (room) => {
  let password = "";
  if (room.private) {
    password = window.prompt(`Enter password for "${room.name}":`) || "";
  }
  try {
    const match = await app.socket.joinMatch(room.id, undefined, password ? { password } : {});
    const label = nakama.roomFromLabel(match.label);
    app.enterWaiting({
      matchId: room.id,
      name: (label && label.name) || room.name,
      ownerId: label && label.owner,
      private: room.private,
      maxPlayers: room.maxPlayers,
      players: []
    });
  } catch (err) {
    const msg = String((err && (err.message || err.statusText)) || err);
    if (/password/i.test(msg)) {
      window.alert("Wrong password");
    } else if (/full/i.test(msg)) {
      window.alert("Room is full");
    } else {
      window.alert(msg || "Join failed");
    }
  }
};

app.createRoom = async (roomName, password, maxPlayers) => {
  const matchId = await nakama.createRoom(app.session, { name: roomName, password, maxPlayers });
  const match = await app.socket.joinMatch(matchId, undefined, password ? { password } : {});
  const label = nakama.roomFromLabel(match.label);
  return {
    matchId,
    name: (label && label.name) || roomName || `Room ${matchId.slice(0, 4)}`,
    ownerId: label && label.owner,
    private: !!password,
    maxPlayers: (label && label.maxPlayers) || maxPlayers,
    players: []
  };
};

function showGameCanvas() {
  const c = document.getElementById("game-container");
  if (c) c.classList.remove("hidden");
}
function hideGameCanvas() {
  const c = document.getElementById("game-container");
  if (c) c.classList.add("hidden");
}

async function exitToLobby() {
  if (app.game) {
    await app.game.stop();
    app.game = null;
  }
  app.currentRoom = null;
  hideGameCanvas();
  window.gameHUD?.hide();
  window.gameHUD?.hideGameOver();
  app.showLobbyScreen();
}

async function startGame() {
  const room = app.currentRoom;
  if (!room) return;

  showGameCanvas();
  setScreen(app, "game");

  const net = new Net({ socket: app.socket, matchId: room.matchId, session: app.session });
  net.onEnd = () => exitToLobby();
  app.game = {
    net,
    stop: async () => {
      net.close();
      try {
        await app.socket.leaveMatch(room.matchId);
      } catch {
        /* ignore */
      }
    }
  };

  try {
    await Promise.race([
      net.ready,
      new Promise((resolve) => setTimeout(resolve, 4000))
    ]);
  } catch {
    /* ignore timeout */
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

  const scene = phaserGame.scene.getScene("GameScene");
  if (scene) {
    scene.onEnd = () => exitToLobby();
  }
}

document.getElementById("btn-gameover-back").addEventListener("click", () => {
  exitToLobby();
});

document.getElementById("btn-exit-game")?.addEventListener("click", () => {
  exitToLobby();
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
