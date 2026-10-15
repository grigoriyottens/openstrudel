// Unpacks the pinned Grok Build binary from its npm platform package to <runtime>/bin/grok.
// Installs run with --ignore-scripts, so the package's own postinstall, which writes into ~/.grok, never runs.
// Usage: node scripts/extract-grok.mjs <runtime> [<os>-<arch>]
import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { brotliDecompressSync } from "node:zlib";

const [runtime = ".", target = `${process.platform}-${process.arch}`] = process.argv.slice(2);
const pkg = resolve(runtime, "node_modules/@xai-official/grok-" + target), packed = join(pkg, "bin/grok.br"), plain = join(pkg, "bin/grok");
if (!existsSync(packed) && !existsSync(plain)) { console.error(`Grok Build for ${target} is not installed in ${resolve(runtime)}.`); process.exit(1); }
const bin = resolve(runtime, "bin");
mkdirSync(bin, { recursive: true });
writeFileSync(join(bin, "grok.partial"), existsSync(packed) ? brotliDecompressSync(readFileSync(packed)) : readFileSync(plain), { mode: 0o755 });
renameSync(join(bin, "grok.partial"), join(bin, "grok"));
console.log(`Grok Build ${JSON.parse(readFileSync(join(pkg, "package.json"), "utf8")).version} for ${target} unpacked to ${join(bin, "grok")}.`);
