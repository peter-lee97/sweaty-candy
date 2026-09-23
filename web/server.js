import fs from "node:fs";
import http from "node:http";
import path from "node:path";
import { URL } from "node:url";
import { fileURLToPath } from "node:url";

const CLIENT_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "client");
const SHARED_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "shared");

const STATIC_MIME = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".png": "image/png",
  ".svg": "image/svg+xml",
  ".ico": "image/x-icon"
};

function serveStaticFile(res, pathname) {
  if (!pathname || pathname.includes("..")) {
    return false;
  }
  let filePath;
  if (pathname === "/") {
    filePath = path.join(CLIENT_DIR, "index.html");
  } else if (pathname.startsWith("/shared/")) {
    filePath = path.resolve(path.join(SHARED_DIR, pathname.slice("/shared/".length)));
    if (!filePath.startsWith(SHARED_DIR)) {
      return false;
    }
  } else {
    filePath = path.resolve(path.join(CLIENT_DIR, pathname));
    if (!filePath.startsWith(CLIENT_DIR)) {
      return false;
    }
  }
  if (!fs.existsSync(filePath) || !fs.statSync(filePath).isFile()) {
    return false;
  }
  const ext = path.extname(filePath).toLowerCase();
  res.writeHead(200, { "Content-Type": STATIC_MIME[ext] || "application/octet-stream", "Cache-Control": "no-cache" });
  fs.createReadStream(filePath).pipe(res);
  return true;
}

const DEFAULT_PORT = Number(process.env.PORT || 8787);
const DEFAULT_HOST = process.env.HOST || "0.0.0.0";

const server = http.createServer((req, res) => {
  const url = new URL(req.url || "/", `http://${req.headers.host || "localhost"}`);
  const { pathname } = url;
  if (pathname === "/health") {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ ok: true, service: "static" }));
    return;
  }
  if (!serveStaticFile(res, pathname)) {
    res.writeHead(404, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "not found" }));
  }
});

server.listen(DEFAULT_PORT, DEFAULT_HOST, () => {
  console.log(`Static server listening on http://${DEFAULT_HOST}:${DEFAULT_PORT}`);
});
