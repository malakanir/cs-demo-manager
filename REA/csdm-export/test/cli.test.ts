import { access } from 'node:fs/promises';
import { join } from 'node:path';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';
import { createFixture, FIXTURE_CHECKSUM, TEST_DATABASE_URL } from './fixture.js';

const execFileAsync = promisify(execFile);
const CLI_PATH = fileURLToPath(new URL('../src/cli.ts', import.meta.url));

describe('cli export', () => {
  let teardown: () => Promise<void>;
  let outDir: string;

  beforeAll(async () => {
    teardown = (await createFixture()).teardown;
    outDir = join('/tmp', `csdmm-cli-${process.pid}-${Date.now()}`);
  });

  afterAll(async () => {
    await teardown();
  });

  it('exports a match via argv and exits 0 with the file on disk', async () => {
    const { stdout, stderr } = await execFileAsync('npx', [
      'tsx',
      CLI_PATH,
      'export',
      '--checksum',
      FIXTURE_CHECKSUM,
      '--out',
      outDir,
      '--database',
      TEST_DATABASE_URL,
    ], { cwd: fileURLToPath(new URL('..', import.meta.url)) });

    expect(stderr).toBe('');
    expect(stdout).toContain(FIXTURE_CHECKSUM);
    await expect(access(join(outDir, `${FIXTURE_CHECKSUM}.csdmm`))).resolves.toBeUndefined();
  }, 60_000);

  it('exits non-zero for an unknown checksum', async () => {
    await expect(
      execFileAsync('npx', [
        'tsx',
        CLI_PATH,
        'export',
        '--checksum',
        '00000000deadbeef',
        '--out',
        outDir,
        '--database',
        TEST_DATABASE_URL,
      ], { cwd: fileURLToPath(new URL('..', import.meta.url)) }),
    ).rejects.toMatchObject({ code: 1 });
  }, 60_000);
});
