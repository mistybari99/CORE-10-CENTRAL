import test from 'node:test';
import assert from 'node:assert/strict';
import { serverVersion } from '../lib/db.mjs';

test('environment: server major matches the expected major in CI (PG17), reports the real version locally', () => {
  const v = serverVersion();
  const major = Number(v.split('.')[0]);
  assert.ok(major >= 16, `PostgreSQL >= 16 required, got ${v}`);
  if (process.env.G3_EXPECT_PG_MAJOR) assert.equal(String(major), process.env.G3_EXPECT_PG_MAJOR);
});
