import { afterEach, describe, expect, it, vi } from 'vitest';
import { createServer } from 'node:net';
import { getLanIpv4, printPairingQr, advertiseService, stopAdvertise } from '../src/serve/network.js';

describe('getLanIpv4', () => {
  it('returns a non-loopback IPv4 string in test env', () => {
    const ip = getLanIpv4();
    expect(ip).not.toBeNull();
    expect(ip).not.toBe('127.0.0.1');
    expect(ip!.includes('.')).toBe(true);
  });
});

describe('printPairingQr', () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('logs the URL and resolves without throwing', async () => {
    const spy = vi.spyOn(console, 'log').mockImplementation(() => {});
    const url = 'http://192.168.1.5:7323/#/deadbeefdeadbeef';
    await expect(printPairingQr(url)).resolves.toBeUndefined();
    const logged = spy.mock.calls.map((args) => args.join(' ')).join('\n');
    expect(logged).toContain(url);
  });
});

describe('advertiseService/stopAdvertise', () => {
  it('start/stop without throwing, stop idempotent, re-advertise ok', async () => {
    // bonjour-service rejects port 0 — grab a real ephemeral port.
    const port = await new Promise<number>((resolve, reject) => {
      const srv = createServer();
      srv.listen(0, '127.0.0.1', () => {
        const addr = srv.address();
        const p = typeof addr === 'object' && addr ? addr.port : 0;
        srv.close(() => (p > 0 ? resolve(p) : reject(new Error('no port'))));
      });
      srv.on('error', reject);
    });
    advertiseService('csdm-export-test', port);
    stopAdvertise();
    stopAdvertise();
    advertiseService('csdm-export-test', port);
    stopAdvertise();
    expect(getLanIpv4()).not.toBeNull();
  });
});
