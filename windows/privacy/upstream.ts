// Shared helpers for check-upstream.ts and update-upstream.ts.
import { readFileSync, writeSync } from "node:fs";

export const dir = import.meta.dir;
export const psd1 = `${dir}/upstream.psd1`;

export const out = (line: string): void => void writeSync(1, `${line}\n`);
export const err = (line: string): void => void writeSync(2, `${line}\n`);

export const sha256 = (data: Uint8Array): string => new Bun.CryptoHasher("sha256").update(data).digest("hex");

// Download a URL like `curl -fsSL`: follow redirects, fail on an HTTP error.
export async function download(url: string): Promise<Uint8Array> {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`${url}: HTTP ${res.status}`);
  return new Uint8Array(await res.arrayBuffer());
}

// upstream.psd1 field of a section: field("Win11Debloat", "Url").
// The section runs from `    <name> = @{` to the next `    }`.
export function field(section: string, name: string): string {
  const lines = readFileSync(psd1, "utf8").split("\n");
  const start = lines.findIndex((l) => l.startsWith(`    ${section} = @{`));
  if (start < 0) return "";
  const values: string[] = [];
  for (let i = start; i < lines.length; i++) {
    const m = new RegExp(`^ *${name} *= *'(.*)'`).exec(lines[i]);
    if (m) values.push(m[1]);
    if (i > start && lines[i].startsWith("    }")) break;
  }
  return values.join("\n");
}
