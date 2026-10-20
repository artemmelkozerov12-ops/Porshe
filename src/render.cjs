// Frame-accurate renderer: drives scene.html with seek(t), pipes PNG frames into ffmpeg.
// Usage:
//   node src/render.cjs video <W> <H> <out.mp4> [fps]
//   node src/render.cjs stills <W> <H> <outDir> t1 t2 ...
// Needs NODE_PATH pointing at the global node_modules that contains playwright.
const { chromium } = require('playwright');
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

const SRC = __dirname;
const ROOT = path.dirname(SRC);
const [mode, Ws, Hs, out, ...rest] = process.argv.slice(2);
const W = +Ws, H = +Hs;
const beats = JSON.parse(fs.readFileSync(path.join(SRC, 'beats.json'), 'utf8'));
const config = JSON.parse(fs.readFileSync(path.join(SRC, 'config.json'), 'utf8'));

(async () => {
  const browser = await chromium.launch({ args: ['--allow-file-access-from-files'] });
  const page = await browser.newPage({ viewport: { width: W, height: H }, deviceScaleFactor: 1 });
  await page.addInitScript(cfg => { window.CFG = cfg; }, { ...config, W, H, beats });
  await page.goto('file://' + path.join(SRC, 'scene.html'));
  await page.evaluate(() => window.ready);
  const canvas = await page.$('#c');

  if (mode === 'stills') {
    fs.mkdirSync(out, { recursive: true });
    for (const t of rest.map(Number)) {
      await page.evaluate(t => window.seek(t), t);
      await canvas.screenshot({ path: path.join(out, `t${t.toFixed(2).padStart(5, '0')}.png`) });
    }
  } else {
    const fps = +(rest[0] || 24);
    const n = Math.round(beats.length * fps);
    const ff = spawn('ffmpeg', ['-y', '-hide_banner', '-loglevel', 'error',
      '-f', 'image2pipe', '-framerate', String(fps), '-i', '-',
      '-i', path.join(ROOT, 'output', 'audio', 'track.wav'),
      '-c:v', 'libx264', '-preset', 'slow', '-crf', '16', '-pix_fmt', 'yuv420p',
      '-profile:v', 'high', '-movflags', '+faststart',
      '-c:a', 'aac', '-b:a', '256k', '-shortest', out], { stdio: ['pipe', 'inherit', 'inherit'] });
    const t0 = Date.now();
    for (let i = 0; i < n; i++) {
      await page.evaluate(t => window.seek(t), i / fps);
      const buf = await canvas.screenshot({ type: 'png' });
      if (!ff.stdin.write(buf)) await new Promise(r => ff.stdin.once('drain', r));
      if (i % 96 === 0) process.stdout.write(`frame ${i}/${n}  ${((Date.now() - t0) / 1000).toFixed(0)}s\n`);
    }
    ff.stdin.end();
    await new Promise(r => ff.on('close', r));
    console.log('done', out);
  }
  await browser.close();
})();
