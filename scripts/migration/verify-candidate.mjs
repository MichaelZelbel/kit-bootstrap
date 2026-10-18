import fs from 'node:fs';
const [file, product, bootstrap] = process.argv.slice(2);
const manifest = JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, ''));
if (manifest.kitCommit !== product || manifest.bootstrapCommit !== bootstrap || manifest.version !== '2.0.0-beta.1') {
  throw new Error('Candidate manifest does not name the exact requested beta product and bootstrap commits.');
}
console.log(`Verified beta manifest: product ${product}, bootstrap ${bootstrap}`);
