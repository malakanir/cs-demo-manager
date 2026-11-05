// Regenerates assets/maps.json from csdm's default-maps.ts (CS2 maps only).
// Usage (from REA/csdm_mobile): node tool/gen_maps.mjs ../../src/node/database/maps/default-maps.ts > assets/maps.json
import { readFileSync } from 'node:fs';

const source = readFileSync(process.argv[2], 'utf8');
const cs2 = source.slice(source.indexOf('const cs2Maps'));
const maps = [...cs2.matchAll(/\{\s*name:\s*'([^']+)',\s*game:\s*Game\.CS2,\s*position_x:\s*(-?[\d.]+),\s*position_y:\s*(-?[\d.]+),\s*scale:\s*(-?[\d.]+),\s*threshold_z:\s*(-?[\d.]+),?\s*\}/g)].map((m) => ({
  name: m[1],
  game: 'cs2',
  position_x: Number(m[2]),
  position_y: Number(m[3]),
  scale: Number(m[4]),
  threshold_z: Number(m[5]),
}));
process.stdout.write(`${JSON.stringify(maps, null, 2)}\n`);
