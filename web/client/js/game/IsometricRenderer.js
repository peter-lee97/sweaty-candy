import { MAP } from '/shared/game.js';

const H = 1.0;
const V = 0.5;

export class IsometricRenderer {
  constructor(scene) {
    this.scene = scene;
  }

  worldToScreen(x, y) {
    return { x: (x - y) * H, y: (x + y) * V };
  }

  drawMap() {
    this.drawFloor();
    this.drawGrid();
    this.drawObstacles();
  }

  drawFloor() {
    const half = MAP.halfSize;
    const corners = [
      this.worldToScreen(-half, -half),
      this.worldToScreen(half, -half),
      this.worldToScreen(half, half),
      this.worldToScreen(-half, half)
    ];
    const g = this.scene.add.graphics().setScrollFactor(1);
    g.fillStyle(0x1c1c24, 1);
    g.beginPath();
    g.moveTo(corners[0].x, corners[0].y);
    for (let i = 1; i < corners.length; i++) g.lineTo(corners[i].x, corners[i].y);
    g.closePath();
    g.fillPath();
    g.lineStyle(4, 0x3a3a48, 1);
    g.strokePath();
    g.setDepth(-10000);
  }

  drawGrid() {
    const half = MAP.halfSize;
    const g = this.scene.add.graphics().setScrollFactor(1);
    g.lineStyle(1, 0xffffff, 0.04);
    for (let gr = -half; gr <= half; gr += 200) {
      const a = this.worldToScreen(gr, -half);
      const b = this.worldToScreen(gr, half);
      g.lineBetween(a.x, a.y, b.x, b.y);
      const c = this.worldToScreen(-half, gr);
      const d = this.worldToScreen(half, gr);
      g.lineBetween(c.x, c.y, d.x, d.y);
    }
    g.setDepth(-9999);
  }

  drawObstacles() {
    for (const box of MAP.obstacles) {
      this.drawObstacle(box);
    }
  }

  drawObstacle(box) {
    const scene = this.scene;
    const g = scene.add.graphics().setScrollFactor(1);
    const { x, y, w, h } = box;
    const hw = w / 2;
    const hh = h / 2;
    const z = MAP.obstacleHeight;
    const drop = z * V;

    const corners = [
      this.worldToScreen(x - hw, y - hh),
      this.worldToScreen(x + hw, y - hh),
      this.worldToScreen(x + hw, y + hh),
      this.worldToScreen(x - hw, y + hh)
    ];
    const [A, B, C, D] = corners;

    const depth = x + y;

    // side faces
    g.fillStyle(0x6b3417, 1);
    g.beginPath();
    g.moveTo(C.x, C.y);
    g.lineTo(B.x, B.y);
    g.lineTo(B.x, B.y + drop);
    g.lineTo(C.x, C.y + drop);
    g.closePath();
    g.fillPath();

    g.beginPath();
    g.moveTo(C.x, C.y);
    g.lineTo(D.x, D.y);
    g.lineTo(D.x, D.y + drop);
    g.lineTo(C.x, C.y + drop);
    g.closePath();
    g.fillPath();

    // top face
    g.fillStyle(0x8a4a22, 1);
    g.beginPath();
    g.moveTo(A.x, A.y);
    g.lineTo(B.x, B.y);
    g.lineTo(C.x, C.y);
    g.lineTo(D.x, D.y);
    g.closePath();
    g.fillPath();
    g.lineStyle(2, 0x000000, 0.4);
    g.strokePath();

    g.setDepth(depth);
  }
}
