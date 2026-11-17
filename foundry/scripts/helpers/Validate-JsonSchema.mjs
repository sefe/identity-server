import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import Ajv2020 from "ajv/dist/2020.js";
import addFormats from "ajv-formats";

const [schemaPathArg, dataPathArg, schemaRootArg] = process.argv.slice(2);
if (!schemaPathArg || !dataPathArg) {
  console.error(
    "Usage: node Validate-JsonSchema.mjs <schema> <data> [schema-root]",
  );
  process.exit(2);
}

function collectJsonFiles(directory) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const absolute = path.join(directory, entry.name);
    if (entry.isDirectory()) return collectJsonFiles(absolute);
    return entry.name.endsWith(".json") ? [absolute] : [];
  });
}

try {
  const schemaPath = path.resolve(schemaPathArg);
  const dataPath = path.resolve(dataPathArg);
  const schemaRoot = path.resolve(schemaRootArg || path.dirname(schemaPath));
  const ajv = new Ajv2020({
    allErrors: true,
    strict: false,
    validateFormats: true,
  });
  addFormats(ajv);

  for (const file of collectJsonFiles(schemaRoot)) {
    const schema = JSON.parse(fs.readFileSync(file, "utf8"));
    const fileId = pathToFileURL(file).href;
    if (!ajv.getSchema(fileId)) ajv.addSchema(schema, fileId);
  }

  const schemaId = pathToFileURL(schemaPath).href;
  const validate = ajv.getSchema(schemaId);
  if (!validate) throw new Error(`Schema was not loaded: ${schemaPath}`);
  const data = JSON.parse(fs.readFileSync(dataPath, "utf8"));
  const valid = validate(data);
  const result = {
    valid: Boolean(valid),
    errors: valid
      ? []
      : (validate.errors || []).map((error) => ({
          instancePath: error.instancePath,
          schemaPath: error.schemaPath,
          keyword: error.keyword,
          message: error.message,
          params: error.params,
        })),
  };
  process.stdout.write(JSON.stringify(result));
  process.exit(valid ? 0 : 1);
} catch (error) {
  console.error(`SCHEMA_VALIDATION_ERROR: ${error.message}`);
  process.exit(2);
}

