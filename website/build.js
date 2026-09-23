const fs = require('node:fs');
const path = require('node:path');

const buildDir = path.join(__dirname, 'build');
const gaMeasurementId = process.env.GA_MEASUREMENT_ID;
const gaPlaceholder = '__GA_MEASUREMENT_ID__';
const sourceHtmlFiles = fs.readdirSync(__dirname).filter((file) => file.endsWith('.html'));
const gaBlockPattern = /<!-- Google tag \(gtag\.js\) -->\s*<script async src="https:\/\/www\.googletagmanager\.com\/gtag\/js\?id=__GA_MEASUREMENT_ID__"><\/script>\s*<script>[\s\S]*?<\/script>\s*/;

fs.rmSync(buildDir, {recursive: true, force: true});
fs.mkdirSync(buildDir, {recursive: true});

for (const file of sourceHtmlFiles) {
  const sourcePath = path.join(__dirname, file);
  const targetPath = path.join(buildDir, file);
  let content = fs.readFileSync(sourcePath, 'utf8');

  if (gaMeasurementId) {
    content = content.split(gaPlaceholder).join(gaMeasurementId);
  } else {
    content = content.replace(gaBlockPattern, '');
  }

  if (content.includes(gaPlaceholder)) {
    console.error(`Unreplaced analytics placeholder found in ${file}.`);
    process.exit(1);
  }

  fs.writeFileSync(targetPath, content);
}

fs.cpSync(path.join(__dirname, 'img'), path.join(buildDir, 'img'), {recursive: true});
