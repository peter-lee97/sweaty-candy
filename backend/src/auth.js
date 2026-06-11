import crypto from "node:crypto";

const ITERATIONS = 120000;
const KEYLEN = 64;
const DIGEST = "sha512";

export function hashPassword(password) {
  const salt = crypto.randomBytes(16).toString("hex");
  const hash = crypto.pbkdf2Sync(password, salt, ITERATIONS, KEYLEN, DIGEST).toString("hex");
  return `${salt}:${hash}`;
}

export function verifyPassword(password, stored) {
  const [salt, expectedHash] = stored.split(":");
  if (!salt || !expectedHash) {
    return false;
  }
  const actualHash = crypto.pbkdf2Sync(password, salt, ITERATIONS, KEYLEN, DIGEST).toString("hex");
  return crypto.timingSafeEqual(Buffer.from(actualHash, "hex"), Buffer.from(expectedHash, "hex"));
}

export function issueToken() {
  return crypto.randomBytes(32).toString("hex");
}

export function generateGuestId() {
  const timestamp = Date.now();
  const random = Math.random().toString(36).substring(2, 6);
  return `guest_${timestamp}_${random}`;
}

export function generateGuestUsername(fruits, colors, store) {
  for (let attempt = 0; attempt < 50; attempt++) {
    const fruit = fruits[Math.floor(Math.random() * fruits.length)];
    const color = colors[Math.floor(Math.random() * colors.length)];
    const suffix = Math.floor(Math.random() * 900 + 100).toString();
    const username = fruit + color + suffix;
    const collidesRegistered = store.users.some((u) => u.username.toLowerCase() === username.toLowerCase());
    const collidesGuest = Object.values(store.guestSessions).some((s) => s.username.toLowerCase() === username.toLowerCase());
    if (!collidesRegistered && !collidesGuest) {
      return username;
    }
  }
  return fruits[Math.floor(Math.random() * fruits.length)] + colors[Math.floor(Math.random() * colors.length)] + Date.now().toString().slice(-3);
}
