import { randomBytes } from 'node:crypto';
import { connectDatabase, destroyDatabase } from './db/connect.js';
import { exportMatch } from './export/export-match.js';
import {
  advertiseService,
  getLanIpv4,
  printPairingQr,
  stopAdvertise,
} from './serve/network.js';
import { createServer } from './serve/server.js';

const USAGE = `csdm-export — export cs-demo-manager matches as .csdmm files

Usage:
  tsx src/cli.ts export --checksum <hex> [--out DIR] [--database URL]
  tsx src/cli.ts serve [--port N] [--out DIR] [--database URL]

Options:
  --checksum   Checksum of the match to export (required for export).
  --out        Output directory (default: ./exports).
  --database   PostgreSQL URL (default: CSDM_DATABASE_URL env).
  --port       HTTP port for serve (default: 7323).
`;

function readFlag(argv: string[], flag: string): string | undefined {
  const index = argv.indexOf(flag);
  if (index === -1) return undefined;
  return argv[index + 1];
}

function readDatabaseUrl(argv: string[]): string | null {
  const url = readFlag(argv, '--database') ?? process.env['CSDM_DATABASE_URL'];
  if (url === undefined) {
    console.error('Missing database URL: pass --database or set CSDM_DATABASE_URL');
    return null;
  }
  return url;
}

function parsePort(value: string): number | null {
  const port = Number.parseInt(value, 10);
  return Number.isInteger(port) && port > 0 && port <= 65535 ? port : null;
}

async function runExport(argv: string[]): Promise<number> {
  const checksum = readFlag(argv, '--checksum');
  if (checksum === undefined) {
    console.error('Missing --checksum <hex>');
    return 1;
  }
  const databaseUrl = readDatabaseUrl(argv);
  if (databaseUrl === null) return 1;
  const outDir = readFlag(argv, '--out') ?? './exports';

  const db = connectDatabase(databaseUrl);
  try {
    const { filePath, hasPositions } = await exportMatch(db, checksum, outDir);
    console.log(`Exported: ${filePath}`);
    console.log(`has_positions: ${hasPositions}`);
    return 0;
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    return 1;
  } finally {
    await destroyDatabase(db);
  }
}

async function runServe(argv: string[]): Promise<number> {
  const databaseUrl = readDatabaseUrl(argv);
  if (databaseUrl === null) return 1;
  const outDir = readFlag(argv, '--out') ?? './exports';
  const portFlag = readFlag(argv, '--port');
  let requestedPort = 7323;
  if (portFlag !== undefined) {
    const parsed = parsePort(portFlag);
    if (parsed === null) {
      console.error(`Invalid port: ${portFlag}`);
      return 1;
    }
    requestedPort = parsed;
  }

  const db = connectDatabase(databaseUrl);
  // Token rotates on every start; pairing happens through the printed QR only.
  const token = randomBytes(24).toString('base64url');
  const server = await createServer({ db, token, outDir });

  const lanIp = getLanIpv4();
  const host = lanIp ?? '127.0.0.1';
  if (lanIp === null) {
    console.warn('No private LAN IPv4 found — serving on 127.0.0.1 (local only)');
  }

  try {
    await server.listen({ port: requestedPort, host });
  } catch (error) {
    console.error(`Listen failed: ${error instanceof Error ? error.message : String(error)}`);
    await server.close();
    await destroyDatabase(db);
    return 1;
  }

  const address = server.server.address();
  if (address === null || typeof address === 'string') {
    console.error('Unexpected server address (not a TCP socket)');
    await server.close();
    await destroyDatabase(db);
    return 1;
  }
  // bonjour-service rejects port 0; always advertise the BOUND port.
  const boundPort = address.port;

  await printPairingQr(`http://${address.address}:${boundPort}/#${token}`);
  advertiseService('csdm-export', boundPort);

  const shutdown = (): void => {
    stopAdvertise();
    void server.close().then(() => destroyDatabase(db)).then(() => process.exit(0));
  };
  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);

  return 0;
}

export async function main(argv: string[]): Promise<number> {
  switch (argv[0]) {
    case 'export':
      return runExport(argv.slice(1));
    case 'serve':
      return runServe(argv.slice(1));
    case '--help':
    case '-h':
      console.log(USAGE);
      return 0;
    default:
      console.log(USAGE);
      return 1;
  }
}

main(process.argv.slice(2))
  .then((code) => {
    process.exitCode = code;
  })
  .catch((error: unknown) => {
    console.error(error instanceof Error ? error.message : String(error));
    process.exitCode = 1;
  });
