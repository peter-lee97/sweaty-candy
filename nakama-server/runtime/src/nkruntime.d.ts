/// <reference types="nakama-runtime" />

declare var TextDecoder: {
  new (): { decode(buffer: Uint8Array): string };
} | undefined;

