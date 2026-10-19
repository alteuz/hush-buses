// Copies the web information system (../app) into Cordova's www/ folder so the
// mobile app and the web app share exactly the same code.
const fs = require('fs');
const path = require('path');

const src = path.resolve(__dirname, '..', '..', 'app');
const dest = path.resolve(__dirname, '..', 'www');

fs.rmSync(dest, { recursive: true, force: true });
fs.cpSync(src, dest, { recursive: true });

const indexPath = path.join(dest, 'index.html');
let html = fs.readFileSync(indexPath, 'utf8');
html = html
  // cordova.js is provided by each platform at build time
  .replace('<script src="https://cdn.jsdelivr.net', '<script src="cordova.js"></script>\n  <script src="https://cdn.jsdelivr.net')
  // the landing page is not bundled inside the app
  .replace('href="../index.html" target="_top"', 'href="#"')
  .replace('<body>', '<body class="is-cordova">');
fs.writeFileSync(indexPath, html);

console.log('www/ synced from ' + src);
