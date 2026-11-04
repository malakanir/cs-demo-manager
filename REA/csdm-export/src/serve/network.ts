import { networkInterfaces, type NetworkInterfaceInfo } from 'node:os';
import QRCode from 'qrcode';
import Bonjour from 'bonjour-service';

const PRIVATE_RANGES = [/^192\.168\./, /^10\./, /^172\.(1[6-9]|2\d|3[01])\./] as const;

function isPrivateIpv4(address: string): boolean {
  return PRIVATE_RANGES.some((re) => re.test(address));
}

/**
 * First non-internal IPv4 address, private ranges preferred
 * (192.168.* then 10.* then 172.16–31.*). Null when offline.
 */
export function getLanIpv4(): string | null {
  const candidates: NetworkInterfaceInfo[] = Object.values(networkInterfaces()).flat().filter((info): info is NetworkInterfaceInfo => {
    return info !== undefined && info.family === 'IPv4' && !info.internal;
  });

  for (const re of PRIVATE_RANGES) {
    const hit = candidates.find((info) => re.test(info.address));
    if (hit) return hit.address;
  }
  return candidates[0]?.address ?? null;
}

/**
 * Prints a scannable terminal QR of the pairing URL plus the plain URL
 * (for machines without a good terminal). Never throws.
 */
export async function printPairingQr(url: string): Promise<void> {
  try {
    const qr = await QRCode.toString(url, { type: 'terminal', small: true });
    console.log(qr);
  } catch {
    // QR rendering failure must not break pairing — URL below is the fallback.
  }
  console.log(`Open on your laptop: ${url}`);
}

let bonjour: InstanceType<typeof Bonjour.Bonjour> | null = null;

/** Publishes a `_csdmm._tcp` mDNS service; a second call replaces the first. */
export function advertiseService(name: string, port: number): void {
  stopAdvertise();
  bonjour = new Bonjour.Bonjour();
  bonjour.publish({ name, type: 'csdmm', port, txt: { v: '1' } });
}

/** Unpublishes and stops the mDNS stack; no-op when not advertising. */
export function stopAdvertise(): void {
  if (!bonjour) return;
  bonjour.unpublishAll(() => bonjour?.destroy());
  bonjour = null;
}
