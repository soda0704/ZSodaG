// Bake the supplied SMIL SVG into a native Godot SpriteFrames resource.
// Development tool only: node tools/bake_save_indicator.cjs <loading.svg>
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require('playwright');
const sharp = require('sharp');

(async () => {
  const root = path.resolve(__dirname, '..');
  const original = fs.readFileSync(process.argv[2], 'utf8');
  const output = path.join(root, 'assets/ui/save_indicator');
  fs.mkdirSync(path.join(output, 'source'), { recursive: true });
  fs.writeFileSync(path.join(output, 'source/loading.svg'), original);
  fs.writeFileSync(path.join(output, 'source/.gdignore'), '');
  const browser = await chromium.launch({ headless: true, channel: process.argv[3] || 'msedge' });
  try {
    const page = await browser.newPage({ viewport: { width: 128, height: 128 } });
    const svg = original.replace(/<\?xml[^>]*>/, '')
      .replace('viewBox="0 0 800 600"', 'viewBox="240 140 320 320"');
    await page.setContent('<style>html,body{margin:0;width:128px;height:128px;background:transparent}svg{display:block}</style>' + svg);
    const frames = [];
    for (let frame = 0; frame < 180; frame++) {
      await page.evaluate(time => {
        const svg = document.querySelector('svg');
        svg.pauseAnimations();
        svg.setCurrentTime(time);
      }, frame / 30);
      frames.push({ input: await page.screenshot({ omitBackground: true }), left: (frame % 12) * 128, top: Math.floor(frame / 12) * 128 });
    }
    await sharp({ create: { width: 1536, height: 1920, channels: 4, background: '#00000000' } })
      .composite(frames).png().toFile(path.join(output, 'loading_atlas.png'));
    const resource = ['[gd_resource type="SpriteFrames" load_steps=182 format=3]', '',
      '[ext_resource type="Texture2D" path="res://assets/ui/save_indicator/loading_atlas.png" id="atlas"]', ''];
    for (let frame = 0; frame < 180; frame++) {
      resource.push(`[sub_resource type="AtlasTexture" id="frame_${frame}"]`, 'atlas = ExtResource("atlas")',
        `region = Rect2(${(frame % 12) * 128}, ${Math.floor(frame / 12) * 128}, 128, 128)`, '');
    }
    resource.push('[resource]', 'animations = [{', '"frames": [' + Array.from({ length: 180 }, (_, frame) =>
      `{"duration": 1.0, "texture": SubResource("frame_${frame}")}`).join(',\n') + '],',
      '"loop": true, "name": &"save", "speed": 30.0', '}]');
    fs.writeFileSync(path.join(output, 'loading_frames.tres'), resource.join('\n') + '\n');
    console.log('Baked original 6-second SVG animation: 180 frames at 30 fps.');
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
