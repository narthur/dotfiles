// Upload images to GitHub via Playwright CDP connection.
// Called by the gh-image-upload shell wrapper.

const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

async function main() {
  const cdpPort = process.argv[2];
  const imagePaths = process.argv.slice(3);

  if (!cdpPort || imagePaths.length === 0) {
    console.error('Usage: gh-image-upload <cdp-port> <image-path> [<image-path2> ...]');
    process.exit(1);
  }

  for (const p of imagePaths) {
    if (!fs.existsSync(p)) {
      console.error(`File not found: ${p}`);
      process.exit(1);
    }
  }

  const browser = await chromium.connectOverCDP(`http://127.0.0.1:${cdpPort}`);
  const contexts = browser.contexts();
  const page = contexts[0]?.pages()[0];

  if (!page) {
    console.error('No page found in browser');
    process.exit(1);
  }

  const results = [];

  for (const imagePath of imagePaths) {
    const fileName = path.basename(imagePath);
    const fileData = fs.readFileSync(imagePath);
    const b64 = fileData.toString('base64');
    const ext = path.extname(fileName).slice(1).toLowerCase();
    const mimeMap = { png: 'image/png', jpg: 'image/jpeg', jpeg: 'image/jpeg', gif: 'image/gif', webp: 'image/webp', svg: 'image/svg+xml' };
    const mime = mimeMap[ext] || 'image/png';

    const textarea = await page.$('#new_comment_field');
    if (!textarea) {
      console.error('Comment textarea not found. Is a GitHub PR/issue page open?');
      process.exit(1);
    }
    await textarea.fill('');

    await page.evaluate(({ b64, fileName, mime }) => {
      const byteChars = atob(b64);
      const byteArray = new Uint8Array(byteChars.length);
      for (let i = 0; i < byteChars.length; i++) {
        byteArray[i] = byteChars.charCodeAt(i);
      }
      const blob = new Blob([byteArray], { type: mime });
      const file = new File([blob], fileName, { type: mime });

      const input = document.querySelector('#fc-new_comment_field');
      const dt = new DataTransfer();
      dt.items.add(file);
      input.files = dt.files;
      input.dispatchEvent(new Event('change', { bubbles: true }));
    }, { b64, fileName, mime });

    let url = '';
    for (let i = 0; i < 30; i++) {
      await new Promise(r => setTimeout(r, 500));
      const value = await textarea.inputValue();
      if (value && value.includes('github.com/user-attachments/assets/')) {
        const mdMatch = value.match(/\((https:\/\/github\.com\/user-attachments\/assets\/[^\)]+)\)/);
        const htmlMatch = value.match(/src="(https:\/\/github\.com\/user-attachments\/assets\/[^"]+)"/);
        url = mdMatch?.[1] || htmlMatch?.[1] || '';
        break;
      }
    }

    if (url) {
      results.push({ file: fileName, url });
      console.log(url);
    } else {
      const val = await textarea.inputValue();
      console.error(`Failed to get URL for ${fileName}. Textarea: ${val}`);
    }
  }

  const textarea = await page.$('#new_comment_field');
  if (textarea) await textarea.fill('');

  await browser.close();

  if (results.length !== imagePaths.length) {
    process.exit(1);
  }
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
