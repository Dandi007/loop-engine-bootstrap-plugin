#!/usr/bin/env node
import { readFileSync, writeFileSync } from "node:fs";

const [inputPath, outputPath] = process.argv.slice(2);

if (!inputPath || !outputPath) {
  console.error("usage: render-template <input> <output>");
  process.exit(2);
}

const raw = readFileSync(inputPath, "utf8");
const missing = new Set();
const rendered = raw.replace(/\$\{([A-Z0-9_]+)\}/g, (_match, name) => {
  const value = process.env[name];
  if (value === undefined) {
    missing.add(name);
    return "";
  }
  return value;
});

if (missing.size > 0) {
  console.error(`render-template: missing env vars: ${[...missing].sort().join(", ")}`);
  process.exit(2);
}

if (/\$\{[A-Z0-9_]+\}/.test(rendered)) {
  console.error("render-template: unresolved placeholders remain after rendering");
  process.exit(2);
}

writeFileSync(outputPath, rendered, "utf8");
