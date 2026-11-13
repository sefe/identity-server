import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';
import YAML from 'yaml';

const root = path.resolve(import.meta.dirname, '../..');

test('architecture accepts two through four projects and rejects either boundary violation', () => {
  const blueprint = JSON.parse(fs.readFileSync(path.join(root, 'tests/fixtures/blueprints/bounded-blueprint.json'), 'utf8'));
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'foundry-project-boundary-'));
  const artifact = path.join(directory, 'blueprint.json');
  const template = blueprint.details.automationProjects[0];
  try {
    for (const count of [1, 2, 4, 5]) {
      blueprint.details.automationProjects = Array.from({ length: count }, (_, i) => ({
        ...structuredClone(template), name: `Example.Automation.Suite${i}`, path: `automation/Suite${i}`,
      }));
      fs.writeFileSync(artifact, JSON.stringify(blueprint));
      const result = spawnSync(process.execPath, [path.join(root, 'scripts/helpers/Validate-JsonSchema.mjs'),
        path.join(root, 'schemas/architecture/automation-blueprint.schema.json'), artifact,
        path.join(root, 'schemas')], { encoding: 'utf8', windowsHide: true });
      const validation = JSON.parse(result.stdout);
      assert.equal(validation.valid, count >= 2 && count <= 4, JSON.stringify(validation.errors));
      if (!validation.valid) {
        assert.ok(validation.errors.every(e => e.instancePath === '/details/automationProjects' &&
          ['minItems', 'maxItems'].includes(e.keyword)), JSON.stringify(validation.errors));
      }
    }
  } finally {
    fs.unlinkSync(artifact);
    fs.rmdirSync(directory);
  }
});

test('configured language choices all reference an available source and ecosystem adapter', () => {
  const config = YAML.parse(fs.readFileSync(path.join(root, 'config/project.yaml'), 'utf8'));
  assert.equal(config.automation.min_projects, 2);
  assert.equal(config.automation.max_projects, 4);
  const ecosystems = config.automation.ecosystems;
  assert.deepEqual(Object.keys(ecosystems).sort(), ['go', 'maven', 'npm', 'nuget', 'pypi']);
  for (const [id, ecosystem] of Object.entries(ecosystems)) {
    assert.ok(fs.existsSync(path.join(root, 'scripts/ecosystems', `${id}.Ecosystem.ps1`)));
    assert.equal(config.automation.dependency_sources[ecosystem.source]?.ecosystem, id);
  }
});
