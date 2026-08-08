# Fix: Game Content Off-Center (Camera Centering Bug)

## Problem

The game content is not centered on the player. The camera appears offset from where the player actually is.

## Root Cause

In `web/client/js/game/GameScene.js:191-194`, the `updateCamera` method computes `currentCenter` with an incorrect zoom adjustment:

```js
const currentCenter = {
  x: cam.scrollX + cam.width / 2 / cam.zoom,  // BUG
  y: cam.scrollY + cam.height / 2 / cam.zoom   // BUG
};
```

Phaser's `centerOn(x, y)` sets `scrollX = x - width/2` (confirmed in `BaseCamera.js:682-686`) -- it does NOT account for zoom. The camera's actual world-space center is `scrollX + width/2`.

The lerp feedback loop reads the wrong "current center", so it converges to an incorrect camera position. With zoom=0.55 on a 1920x1080 screen, the error is ~785px in X and ~442px in Y.

## Fix

### Change 1: Fix `currentCenter` calculation (`GameScene.js:191-194`)

Remove the `/ cam.zoom` division:

```js
const currentCenter = {
  x: cam.scrollX + cam.width / 2,
  y: cam.scrollY + cam.height / 2
};
```

### Change 2: Snap camera on first frame (`GameScene.js`, in `create()`)

After setting zoom, immediately center the camera on the player instead of starting at (0,0) and slowly lerping:

```js
this.cameras.main.setZoom(0.55);
const initScreen = this.isoRenderer.worldToScreen(this.predictedPos.x, this.predictedPos.y);
this.cameras.main.centerOn(initScreen.x, initScreen.y);
```

---

# Fix 2: Player Invisible Behind Floor

## Problem

The player becomes invisible when moving to certain areas of the map. The player appears to be hidden behind the floor or other map elements.

## Root Cause

The depth sorting uses `x + y` (world coordinates) for entities (players, enemies, obstacles). This gives depth values ranging from approximately -2772 to +2772.

However, the floor has a fixed depth of -10 and the grid has depth -9. When a player is at positions where `x + y < -10` (the upper-left portion of the isometric diamond), the player's depth is LESS than the floor's depth. Since lower depth renders first (behind), the floor renders ON TOP of the player, hiding it.

## Fix

Change the floor and grid depths to very low values that are always below any entity depth:

### In `IsometricRenderer.js`:

1. Floor: change `g.setDepth(-10)` to `g.setDepth(-10000)`
2. Grid: change `g.setDepth(-9)` to `g.setDepth(-9999)`

This ensures the floor and grid always render behind all entities, regardless of their position on the map.

---

## Verification

1. Start the dev server (`./dev.sh`)
2. Create a room and start a game
3. **Camera centering test**: Verify the player appears centered in the viewport
4. **Movement test**: Move around and verify the camera smoothly follows with the player staying centered
5. **Zoom test**: Zoom in/out with mouse wheel and verify centering holds at all zoom levels
6. **Depth test**: Move the player to all corners of the map, especially the upper-left area where `x + y` is most negative. Verify the player remains visible and is not hidden behind the floor
