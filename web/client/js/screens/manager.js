export function setScreen(app, name) {
  app.screen = name;
  const ids = { menu: "screen-menu", lobby: "screen-lobby", waiting: "screen-waiting" };
  for (const [key, id] of Object.entries(ids)) {
    document.getElementById(id).classList.toggle("hidden", key !== name);
  }
}
