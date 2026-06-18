import type { RawData } from "ws";
import { rawDataByteLength } from "./rawData.js";

export const MAX_JSON_CONTROL_BYTES = 64 * 1024;
export const MAX_AUDIO_FRAME_BYTES = 256 * 1024;

export function isOversizedControlMessage(data: RawData): boolean {
  return rawDataByteLength(data) > MAX_JSON_CONTROL_BYTES;
}

export function isOversizedAudioFrame(data: RawData): boolean {
  return rawDataByteLength(data) > MAX_AUDIO_FRAME_BYTES;
}
