// Builds SharksVsMinnows.rbxlx — a Roblox place file you can open straight in Roblox Studio —
// from default.project.json, following Rojo's file conventions:
//   *.server.luau -> Script, *.client.luau -> LocalScript, *.luau -> ModuleScript, folders -> Folder.
// Also writes sourcemap.json so luau-lsp can type-check the project.
// No dependencies: `node build.mjs`.
import { readFileSync, readdirSync, statSync, writeFileSync } from 'node:fs';
import { join, relative } from 'node:path';

const root = new URL('.', import.meta.url).pathname;
const project = JSON.parse(readFileSync(join(root, 'default.project.json'), 'utf8'));

function scriptInfo(file) {
  const m = file.match(/^(.*?)(\.server|\.client)?\.luau?$/);
  if (!m) return null;
  const className = m[2] === '.server' ? 'Script' : m[2] === '.client' ? 'LocalScript' : 'ModuleScript';
  return { name: m[1], className };
}

// Turn a project node into a tree of { name, className, source?, filePaths, children }.
function fromPath(name, absPath) {
  if (statSync(absPath).isDirectory()) {
    const children = readdirSync(absPath).sort()
      .map((f) => fromPath(f, join(absPath, f)))
      .filter(Boolean);
    return { name, className: 'Folder', filePaths: [relative(root, absPath)], children };
  }
  const info = scriptInfo(absPath.split('/').pop());
  if (!info) return null;
  return { name: info.name, className: info.className, source: readFileSync(absPath, 'utf8'), filePaths: [relative(root, absPath)], children: [] };
}

function fromNode(name, node) {
  if (node.$path) {
    const inst = fromPath(name, join(root, node.$path));
    inst.name = name;
    return inst;
  }
  const children = Object.entries(node)
    .filter(([k]) => !k.startsWith('$'))
    .map(([k, v]) => fromNode(k, v));
  return { name, className: node.$className, children };
}

const tree = fromNode(project.name, project.tree);

// rbxlx -----------------------------------------------------------------------------------
let ref = 0;
const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const cdata = (s) => `<![CDATA[${s.split(']]>').join(']]]]><![CDATA[>')}]]>`;

function item(inst, depth) {
  const pad = '  '.repeat(depth);
  let props = `${pad}  <string name="Name">${esc(inst.name)}</string>\n`;
  if (inst.source !== undefined) props += `${pad}  <ProtectedString name="Source">${cdata(inst.source)}</ProtectedString>\n`;
  const kids = inst.children.map((c) => item(c, depth + 1)).join('');
  return `${pad}<Item class="${inst.className}" referent="RBX${ref++}">\n${pad} <Properties>\n${props}${pad} </Properties>\n${kids}${pad}</Item>\n`;
}

const xml = `<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">\n${tree.children.map((c) => item(c, 1)).join('')}</roblox>\n`;
writeFileSync(join(root, 'SharksVsMinnows.rbxlx'), xml);

// sourcemap.json (Rojo's format) for luau-lsp ------------------------------------------------
function sm(inst) {
  const out = { name: inst.name, className: inst.className };
  if (inst.filePaths) out.filePaths = inst.filePaths.filter((p) => p.endsWith('.luau'));
  if (out.filePaths && out.filePaths.length === 0) delete out.filePaths;
  if (inst.children.length) out.children = inst.children.map(sm);
  return out;
}
writeFileSync(join(root, 'sourcemap.json'), JSON.stringify(sm(tree), null, 1));

let scripts = 0;
(function count(i) { if (i.source !== undefined) scripts++; i.children.forEach(count); })(tree);
console.log(`SharksVsMinnows.rbxlx: ${scripts} scripts, ${(Buffer.byteLength(xml) / 1024).toFixed(0)} KB`);
