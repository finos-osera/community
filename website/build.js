const fs = require('node:fs');
const path = require('node:path');

const htmlFiles = [
  'index.html',
  'how-it-works.html',
  'alliance.html',
  'workstreams.html',
  'principles.html',
  'news.html',
  'guiding-principles.html',
  'board.html',
  'roi.html',
  'press-release.html',
];

const buildDir = path.join(__dirname, 'build');
const gaMeasurementId = process.env.GA_MEASUREMENT_ID;

if (!gaMeasurementId) {
  console.error('GA_MEASUREMENT_ID is required for build to prevent publishing unreplaced analytics placeholders.');
  process.exit(1);
}

fs.rmSync(buildDir, {recursive: true, force: true});
fs.mkdirSync(buildDir, {recursive: true});

for (const file of htmlFiles) {
  const sourcePath = path.join(__dirname, file);
  const targetPath = path.join(buildDir, file);
  const content = fs
    .readFileSync(sourcePath, 'utf8')
    .split('__GA_MEASUREMENT_ID__')
    .join(gaMeasurementId);
  fs.writeFileSync(targetPath, content);
}

fs.cpSync(path.join(__dirname, 'img'), path.join(buildDir, 'img'), {recursive: true});
