// Builds two single-file pages:
//   dist/index.html    – fully self-contained (three.js bundled), works offline from disk
//   dist/artifact.html – loads three.js from jsDelivr through an import map (for hosted pages)
import * as esbuild from 'esbuild';
import { readFile, writeFile, mkdir } from 'node:fs/promises';

const THREE_VERSION = JSON.parse(await readFile('node_modules/three/package.json', 'utf8')).version;
const TITLE = 'Gridiron Saturday 26';
const FONTS = '<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin><link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Archivo:wght@400;500;600;700;800&family=Big+Shoulders+Display:wght@600;700;800;900&display=swap">';

const css = await readFile('src/style.css', 'utf8');
const shell = await readFile('src/shell.html', 'utf8');
await mkdir('dist', { recursive: true });

const standalone = await esbuild.build({
  entryPoints: ['src/main.js'], bundle: true, format: 'iife', minify: true, write: false, target: 'es2020', legalComments: 'none',
});
const js = standalone.outputFiles[0].text.replace(/<\/script/gi, '<\\/script');
await writeFile('dist/index.html', `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>${TITLE}</title>
${FONTS}
<style>${css}</style>
</head>
<body>
${shell}
<script>${js}</script>
</body>
</html>
`);

const hosted = await esbuild.build({
  entryPoints: ['src/main.js'], bundle: true, format: 'esm', minify: true, write: false, target: 'es2020', legalComments: 'none',
  external: ['three', 'three/addons/*'],
});
const ejs = hosted.outputFiles[0].text.replace(/<\/script/gi, '<\\/script');
const importMap = {
  imports: {
    three: `https://cdn.jsdelivr.net/npm/three@${THREE_VERSION}/build/three.module.min.js`,
    'three/addons/': `https://cdn.jsdelivr.net/npm/three@${THREE_VERSION}/examples/jsm/`,
  },
};
await writeFile('dist/artifact.html', `<title>${TITLE}</title>
${FONTS}
<style>${css}</style>
${shell}
<script type="importmap">${JSON.stringify(importMap)}</script>
<script type="module">${ejs}</script>
`);

const kb = (s) => `${(Buffer.byteLength(s) / 1024).toFixed(0)} KB`;
console.log(`dist/index.html    ${kb(js)} script`);
console.log(`dist/artifact.html ${kb(ejs)} script (three@${THREE_VERSION} from jsDelivr)`);
