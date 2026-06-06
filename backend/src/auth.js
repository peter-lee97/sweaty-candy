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

export function generateGuestUsername(fruits, colors) {
  const fruit = fruits[Math.floor(Math.random() * fruits.length)];
  const color = colors[Math.floor(Math.random() * colors.length)];
  const suffix = Math.floor(Math.random() * 1000).toString().padStart(3, "0");
  return `${fruit}${color}${suffix}`;
}
