export class InputManager {
  constructor(scene) {
    this.scene = scene;
    this.isTouch = detectTouch();

    this.keys = {};
    const keyCodes = {
      up: ['W', 'UP'],
      down: ['S', 'DOWN'],
      left: ['A', 'LEFT'],
      right: ['D', 'RIGHT']
    };
    for (const [name, codes] of Object.entries(keyCodes)) {
      this.keys[name] = codes.map((k) => scene.input.keyboard.addKey(Phaser.Input.Keyboard.KeyCodes[k]));
    }

    this.mouse = { down: false, x: 0, y: 0 };
    this.sticks = this.isTouch ? createSticks() : null;
    if (this.sticks) {
      document.getElementById('touch-controls').classList.remove('hidden');
    }
  }

  create() {
    const scene = this.scene;

    scene.input.on('pointerdown', (pointer) => {
      if (pointer.leftButtonDown()) this.mouse.down = true;
    });
    scene.input.on('pointerup', (pointer) => {
      if (!pointer.leftButtonDown()) this.mouse.down = false;
    });
    scene.input.on('pointermove', (pointer) => {
      this.mouse.x = pointer.x;
      this.mouse.y = pointer.y;
    });

    if (!this.isTouch) {
      scene.input.mouse?.disableContextMenu?.();
    }
  }

  isKeyDown(keys) {
    return keys.some((k) => k.isDown);
  }

  getKeyboardScreenMove() {
    let x = 0;
    let y = 0;
    if (this.isKeyDown(this.keys.left)) x -= 1;
    if (this.isKeyDown(this.keys.right)) x += 1;
    if (this.isKeyDown(this.keys.up)) y -= 1;
    if (this.isKeyDown(this.keys.down)) y += 1;
    const len = Math.hypot(x, y);
    return len > 0 ? { x: x / len, y: y / len } : { x: 0, y: 0 };
  }

  getStickScreenMove() {
    if (!this.isTouch || !this.sticks) return { x: 0, y: 0 };
    return { ...this.sticks.left.vector };
  }

  getMovement() {
    const screen = this.isTouch ? this.getStickScreenMove() : this.getKeyboardScreenMove();

    if (screen.x === 0 && screen.y === 0) {
      return { x: 0, y: 0 };
    }

    // Convert screen-space direction to world-space (inverse isometric projection).
    // Isometric (2:1): screenX = (worldX - worldY) * H, screenY = (worldX + worldY) * V
    // With H=1, V=0.5: worldDx = screenDx/2 + screenDy, worldDy = screenDy - screenDx/2
    const worldX = screen.x / 2 + screen.y;
    const worldY = screen.y - screen.x / 2;
    const len = Math.hypot(worldX, worldY);
    return len > 0 ? { x: worldX / len, y: worldY / len } : { x: 0, y: 0 };
  }

  getStickShoot() {
    return this.isTouch && this.sticks ? this.sticks.right.active : false;
  }

  isShooting() {
    if (this.isTouch) {
      return this.getStickShoot();
    }
    return this.mouse.down;
  }
}

export function detectTouch() {
  try {
    return 'ontouchstart' in window || (navigator.maxTouchPoints > 0 && window.matchMedia('(pointer: coarse)').matches);
  } catch {
    return 'ontouchstart' in window;
  }
}

function createSticks() {
  return { left: createStick('stick-left'), right: createStick('stick-right') };
}

function createStick(elId) {
  const base = document.getElementById(elId);
  const handle = base.querySelector('.stick-handle');
  const ring = base.querySelector('.stick-ring');
  const stick = {
    base,
    handle,
    ring,
    active: false,
    pointerId: null,
    origin: { x: 0, y: 0 },
    radius: 55,
    vector: { x: 0, y: 0 }
  };

  const setHandle = (dx, dy) => {
    stick.handle.style.transform = `translate(${dx}px, ${dy}px)`;
  };

  base.addEventListener('pointerdown', (e) => {
    e.preventDefault();
    stick.active = true;
    stick.pointerId = e.pointerId;
    const r = base.getBoundingClientRect();
    stick.origin = { x: r.left + r.width / 2, y: r.top + r.height / 2 };
    base.setPointerCapture(e.pointerId);
    ring.style.transform = 'scale(1.15)';
    updateVector(stick, e.clientX, e.clientY, setHandle);
  });

  base.addEventListener('pointermove', (e) => {
    if (e.pointerId !== stick.pointerId) return;
    e.preventDefault();
    updateVector(stick, e.clientX, e.clientY, setHandle);
  });

  const release = (e) => {
    if (e.pointerId !== stick.pointerId) return;
    stick.active = false;
    stick.pointerId = null;
    stick.vector = { x: 0, y: 0 };
    ring.style.transform = '';
    setHandle(0, 0);
  };
  base.addEventListener('pointerup', release);
  base.addEventListener('pointercancel', release);

  return stick;
}

function updateVector(stick, cx, cy, setHandle) {
  let dx = cx - stick.origin.x;
  let dy = cy - stick.origin.y;
  const len = Math.hypot(dx, dy);
  const max = stick.radius;
  if (len > max) {
    dx = (dx / len) * max;
    dy = (dy / len) * max;
  }
  setHandle(dx, dy);
  const nx = dx / max;
  const ny = dy / max;
  const dl = Math.hypot(nx, ny);
  const dead = 0.15;
  if (dl < dead) {
    stick.vector = { x: 0, y: 0 };
  } else {
    const scale = (dl - dead) / (1 - dead);
    stick.vector = { x: (nx / dl) * scale, y: (ny / dl) * scale };
  }
}
