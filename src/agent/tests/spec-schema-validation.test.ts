import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import Ajv2020 from "ajv/dist/2020";
import yaml from "js-yaml";

const REPO_ROOT = join(__dirname, "..", "..", "..");
const SCHEMA_PATH = join(REPO_ROOT, "schemas", "system-spec.v1.json");
const SPECS_DIR = join(REPO_ROOT, "specs");

const schema = JSON.parse(readFileSync(SCHEMA_PATH, "utf8"));
const ajv = new Ajv2020({ allErrors: true });
const validate = ajv.compile(schema);

function specFiles(): string[] {
  return readdirSync(SPECS_DIR).filter((f) => f.endsWith(".yaml") || f.endsWith(".yml"));
}

describe("spec schema validation (system-spec.v1.json)", () => {
  test("specs/ directory contains at least one spec file", () => {
    expect(specFiles().length).toBeGreaterThan(0);
  });

  describe("each spec in specs/ validates against system-spec.v1.json", () => {
    for (const file of specFiles()) {
      test(file, () => {
        const raw = readFileSync(join(SPECS_DIR, file), "utf8");
        const parsed = yaml.load(raw);
        const valid = validate(parsed);
        if (!valid) {
          throw new Error(
            `${file} failed schema validation:\n${JSON.stringify(validate.errors, null, 2)}`,
          );
        }
      });
    }
  });
});
