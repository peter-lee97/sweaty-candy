import Phaser from 'phaser';

export class ParticleManager {
  constructor(scene) {
    this.scene = scene;
    this.particles = [];
    this.g = scene.add.graphics().setDepth(9500);
  }

  burst(pos, color, count, speed) {
    const c = Phaser.Display.Color.HexStringToColor(color).color;
    for (let i = 0; i < count; i++) {
      const ang = Math.random() * Math.PI * 2;
      const sp = speed * (0.4 + Math.random() * 0.6);
      this.particles.push({
        x: pos[0],
        y: pos[1],
        vx: Math.cos(ang) * sp,
        vy: Math.sin(ang) * sp,
        radius: 2 + Math.random() * 4,
        life: 0.3 + Math.random() * 0.25,
        t: 0,
        color: c
      });
    }
  }

  update(dt) {
    this.g.clear();
    this.particles = this.particles.filter((p) => {
      p.t += dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      if (p.t >= p.life) return false;
      const s = this.scene.isoRenderer.worldToScreen(p.x, p.y);
      const alpha = Phaser.Math.Clamp(1 - p.t / p.life, 0, 1);
      const r = p.radius * (0.5 + p.t / p.life);
      this.g.fillStyle(p.color, alpha);
      this.g.fillCircle(s.x, s.y, r);
      return true;
    });
  }
}
