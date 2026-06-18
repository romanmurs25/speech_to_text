import type { RawData } from "ws";

export function rawDataByteLength(data: RawData): number {
  if (Buffer.isBuffer(data)) {
    return data.length;
  }

  if (Array.isArray(data)) {
    return data.reduce((total, chunk) => total + chunk.length, 0);
  }

  return data.byteLength;
}

export function rawDataToBuffer(data: RawData): Buffer {
  if (Buffer.isBuffer(data)) {
    return data;
  }

  if (Array.isArray(data)) {
    return Buffer.concat(data);
  }

  return Buffer.from(data);
}
