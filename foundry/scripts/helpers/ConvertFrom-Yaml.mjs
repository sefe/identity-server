import fs from "node:fs";
import { parse } from "yaml";

const inputPath = process.argv[2];
if (!inputPath) {
  console.error("Usage: node ConvertFrom-Yaml.mjs <path>");
  process.exit(2);
}

try {
  const source = fs.readFileSync(inputPath, "utf8");
  const value = parse(source, { prettyErrors: true, uniqueKeys: true });
  process.stdout.write(JSON.stringify(value));
} catch (error) {
  console.error(`YAML_ERROR: ${error.message}`);
  process.exit(1);
}

