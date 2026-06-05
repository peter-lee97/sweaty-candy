# AGENTS.md — Sweaty Candy

Boxhead-inspired 2.5D arcade horde shooter. Godot 4 (GDScript), angled top-down camera, pixel art sprites on a 3D plane. Single-player first, 4-player co-op multiplayer later.

## Architecture

Three components (Phase 3 scaffolding + Phase 4 backend scaffold started):

- **`client/`** — Godot 4 project. Currently single-player, will export to HTML5/WebAssembly later.
- **`server/`** — Godot 4 headless server build. Authoritative multiplayer host (Phase 3).
- **`backend/`** — Standalone server for auth, matchmaking, persistence (Phase 4).

Key rule: **clients are never authoritative**. Code is structured so input → intent → state change, making the multiplayer retrofit clean.

## Project Layout

```
client/
  project.godot              Godot 4.3, GL Compatibility renderer
  scenes/
    game/        game.tscn (root), arena.tscn
    player/      player.tscn
    enemies/     enemy_base.tscn, enemy_fast.tscn, enemy_tank.tscn
    projectiles/ projectile.tscn, projectile_lobber.tscn, projectile_sprayer.tscn, projectile_freezer.tscn
    weapons/     weapon_blaster.tscn, weapon_lobber.tscn, weapon_sprayer.tscn, weapon_freezer.tscn
    pickups/     health_pickup.tscn
    ui/          main_menu.tscn, hud.tscn, game_over.tscn
  scripts/
    game/        game_manager.gd, entity_manager.gd, wave_manager.gd, score_manager.gd
    player/      player.gd, camera_follow.gd
    enemies/     enemy_base.gd, enemy_fast.gd, enemy_tank.gd
    weapons/     weapon.gd (base class), weapon_blaster.gd, weapon_lobber.gd, weapon_sprayer.gd, weapon_freezer.gd
    projectiles/ projectile.gd, projectile_lobber.gd, projectile_sprayer.gd, projectile_freezer.gd
    components/  health_component.gd, hitbox_component.gd, hit_flash_component.gd
    effects/     death_particles.gd
    pickups/     health_pickup.gd, weapon_pickup.gd
    ui/          hud.gd, main_menu.gd, game_over.gd
    autoload/    game_events.gd (signals), game_data.gd (cross-scene state)
  assets/        sprites/, audio/, fonts/, tilesets/ (placeholder — add real assets)
  resources/     wave_data/, weapon_data/ (for .tres configs later)
```

## Game Scene Tree

```
Game (Node3D) [game_manager.gd]
├── Camera3D [camera_follow.gd] — angled top-down, follows player
├── DirectionalLight3D
├── Arena (instanced) — 30×30 ground + walls
├── EntityManager (Node3D)
│   ├── Players/
│   ├── Enemies/
│   ├── Projectiles/
│   └── Pickups/
├── WaveManager — wave configs, spawns enemies at arena edges
├── ScoreManager — score + combo system
└── HUD (CanvasLayer) — health bar, score, wave, combo, weapon
```

## Collision Layers

| Layer | Value | Used by |
|---|---|---|
| 1 Player | 1 | Player CharacterBody3D |
| 2 Enemy | 2 | Enemy CharacterBody3D, enemy hitbox Area3D |
| 3 Projectile | 4 | Projectile Area3D (detects enemies + world) |
| 4 Pickup | 8 | Pickup Area3D (detects player) |
| 5 World | 16 | Ground, walls (StaticBody3D) |

**Key interactions:**
- Player mask = 18 (enemies + world). Player collides with enemies and walls.
- Enemy mask = 17 (player + world). Enemies don't collide with each other.
- Projectile mask = 18 (enemies + world). Projectiles detect and damage enemies, despawn on walls.
- Enemy hitbox mask = 1 (player). Deals contact damage with a cooldown.

## Autoloads

- **GameEvents** — thin signal bus for cross-system events (`enemy_killed`, `score_updated`, `wave_started`, `player_health_changed`, `player_died`, `weapon_changed`). No logic, just signals.
- **GameData** — persists data across scene changes (`last_score`, `last_wave`).

## Godot Conventions

- **Engine version**: Godot 4.3+ (use `@export`, `await`, `physical_keycode`).
- **Rendering**: GL Compatibility (required for web export).
- **Scene structure**: feature subfolders under `scenes/` and `scripts/`.
- **Node access**: use `%` unique names for frequently accessed children (HealthComponent, WeaponAnchor, Camera3D, etc.). Avoid deep `get_node()` chains.
- **Signals**: past-tense verbs (`health_changed`, `died`, `enemy_killed`).
- **Components**: reusable nodes attached as children (HealthComponent, HitboxComponent, HitFlashComponent).
- **Multiplayer-ready patterns**: input never directly mutates state. Input → intent → authority validates → state change. All spawning goes through EntityManager.
- **No comments in code** unless explicitly requested.

## Gameplay Systems

- **Player**: WASD movement on XZ plane, aim direction = last movement direction. Hold left-click to auto-fire. E/Q cycles weapons.
- **Weapons**: 4 categories, all extend base `Weapon` class via `@export` properties:
  - **Blaster** — single shot, 4/s, 25 dmg, infinite ammo
  - **Lobber** — splash damage, 1.5/s, 40 dmg, 3-unit AoE explosion on impact
  - **Sprayer** — rapid fire, 12/s, 8 dmg, slight spread
  - **Freezer** — crowd control, 3/s, 10 dmg, slows enemies 50% for 2s
- **Enemies**: chase nearest player, deal contact damage via HitboxComponent. Knockback on hit. Three variants:
  - **Base** (red) — 50 HP, speed 1.25, 10 dmg, 100 pts
  - **Fast** (orange) — 25 HP, speed 2.5, 8 dmg, 150 pts (wave 3+)
  - **Tank** (purple) — 150 HP, speed 0.7, 20 dmg, 200 pts (wave 5+)
- **Slow mechanic**: `apply_slow(multiplier, duration)` on enemy_base. `_speed_multiplier` multiplies move_speed. Decays automatically.
- **Pickups**: health pickups drop from killed enemies (15% chance). Restores 25 HP.
- **Waves**: data-driven configs (5 waves defined, scales after). Mixed enemy types from wave 3+. 3s cooldown between waves.
- **Score**: base points × combo multiplier (x1→x4). Combo increments on kills within 2s, resets after timeout.
- **Camera**: Camera3D at offset (0, 18, 12) with smooth follow. ~56° downward angle.
- **Juice**: hit flash on enemy damage (white flash 0.1s), death particles (expanding spheres).

## Commands

```bash
godot --path client/                          # Open in editor
godot --headless --path client/ --export-release "Web" build/web/  # Export for web
godot --headless --path server/              # Run authoritative multiplayer server (Phase 3 scaffold)
cd backend && npm start                      # Run backend auth/matchmaking/persistence scaffold (Phase 4)
```

## Common Pitfalls

- **Web + ENet**: raw ENet UDP does not work in browsers. Use `WebSocketMultiplayerPeer` for web clients (multiplayer phase).
- **State sync**: never let clients set their own position/health. Server validates and broadcasts.
- **Enemy-enemy collision**: enemies don't collide with each other (mask doesn't include layer 2).
- **Projectile tunneling**: at very high speeds, Area3D projectiles can skip over enemies. Sprayer at 30 u/s is safe at 60 FPS.
- **Export templates**: must match the exact Godot version.
- **Weapon cycling**: `weapon_scenes` array order in game.tscn determines cycle order. Blaster must be first (index 0 = starting weapon).
- **Lobber explosion**: uses `PhysicsDirectSpaceState3D.intersect_shape()` with a sphere query. Runs on the physics layer mask 2 (enemies only).
