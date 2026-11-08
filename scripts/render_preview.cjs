// Optional PNG companion to Julia's canonical SVG. Requires the sharp npm package.
// Usage: NODE_PATH=/path/to/node_modules node scripts/render_preview.cjs
const path = require('node:path');
const sharp = require('sharp');
const root = path.resolve(__dirname, '..');
sharp(path.join(root, 'output/layout_preview.svg'), {density: 150})
  .png().toFile(path.join(root, 'output/layout_preview.png'))
  .then(() => console.log('Rendered output/layout_preview.png'))
  .catch(error => {console.error(error); process.exitCode = 1;});
