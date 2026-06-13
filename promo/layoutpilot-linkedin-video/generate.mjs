import {mkdir, writeFile} from "node:fs/promises";
import {execFileSync} from "node:child_process";
import path from "node:path";
import {fileURLToPath} from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const outDir = path.join(__dirname, "frames");
const pngDir = path.join(__dirname, "png-frames");
const stillDir = path.join(__dirname, "still");
const width = 1080;
const height = 1350;
const fps = 30;
const durationSeconds = 29;
const totalFrames = fps * durationSeconds;

const font = "-apple-system, BlinkMacSystemFont, 'SF Pro Display', 'Inter', 'Helvetica Neue', Arial, sans-serif";
const mono = "'SF Mono', ui-monospace, Menlo, Monaco, Consolas, monospace";

const escapeXml = (value) =>
  String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");

const clamp = (v, min = 0, max = 1) => Math.min(max, Math.max(min, v));
const smooth = (t) => {
  const x = clamp(t);
  return x * x * (3 - 2 * x);
};
const lerp = (a, b, t) => a + (b - a) * t;
const ease = (start, end, frame) => smooth((frame - start) / (end - start));
const appear = (start, end, frame) => smooth((frame - start) / (end - start));

const rawText = "K'benhavn. R'dgr'd med fl'de.\nDet f;les bedre.";
const prefix = "I keep the US keyboard layout.\n";
const chars = [...rawText];

function typedLine(frame) {
  const start = 118;
  const charsPerFrame = 0.52;
  const count = clamp(Math.floor((frame - start) * charsPerFrame), 0, chars.length);
  let line = chars.slice(0, count).join("");
  if (frame >= 245) line = line.replace("K'benhavn", "København");
  if (frame >= 340) line = line.replace("R'dgr'd", "Rødgrød").replace("r'dgr'd", "rødgrød");
  if (frame >= 410) line = line.replace("fl'de", "fløde");
  if (frame >= 500) line = line.replace("f;les", "føles");
  return line;
}

function visibleText(frame) {
  if (frame < 96) return "";
  if (frame < 118) return prefix.slice(0, Math.floor((frame - 96) * 1.8));
  return prefix + typedLine(frame);
}

function textLines(text) {
  return text.split("\n");
}

function pill(x, y, label, active = true, color = "#f0b35a") {
  const fill = active ? "#18202c" : "#101722";
  const stroke = active ? color : "#344052";
  return `
    <g>
      <rect x="${x}" y="${y}" width="${label.length * 13 + 42}" height="44" rx="22" fill="${fill}" stroke="${stroke}" stroke-width="1.5"/>
      <text x="${x + 21}" y="${y + 28}" fill="${active ? "#f8fafc" : "#8b98aa"}" font-family="${mono}" font-size="18" font-weight="650">${escapeXml(label)}</text>
    </g>`;
}

function caption(frame) {
  if (frame < 72) return ["Danish on a US keyboard?", "Keep the layout. Fix the friction."];
  if (frame < 255) return ["US keyboard layout stays active", "Type naturally in every app you choose."];
  if (frame < 520) return ["Smart Danish Input", "; ' [ become æ ø å while you type."];
  if (frame < 680) return ["App-aware layout control", "Auto-switch rules and quick menu bar toggles."];
  return ["LayoutPilot for macOS", "Keep your layout. Type Danish faster."];
}

function keyboardScene(frame) {
  const text = visibleText(frame);
  const lines = textLines(text);
  const cursorBlink = Math.floor(frame / 14) % 2 === 0;
  const zoom = 1;
  const pan = 0;
  const convertPulse =
    (frame >= 245 && frame < 270) ||
    (frame >= 340 && frame < 365) ||
    (frame >= 410 && frame < 435) ||
    (frame >= 500 && frame < 525);
  const pulse = convertPulse ? 1 : 0;
  const sceneOpacity = frame < 660 ? 1 : 1 - appear(660, 700, frame);

  const lineSvg = lines
    .map((line, index) => {
      const y = 598 + index * 72;
      const cursor = index === lines.length - 1 && cursorBlink ? `<rect x="${168 + line.length * 27}" y="${y - 45}" width="4" height="54" rx="2" fill="#8fd3ff"/>` : "";
      return `<text x="168" y="${y}" fill="#f8fbff" font-family="${font}" font-size="44" font-weight="680" letter-spacing="0">${escapeXml(line)}</text>${cursor}`;
    })
    .join("");

  return `
    <g opacity="${sceneOpacity}">
      <g transform="translate(${pan} ${-10 * ease(90, 530, frame)}) scale(${zoom})">
        <rect x="86" y="332" width="908" height="542" rx="34" fill="#101722" stroke="#273244" stroke-width="2"/>
        <rect x="86" y="332" width="908" height="74" rx="34" fill="#151f2d"/>
        <circle cx="136" cy="369" r="10" fill="#ff5f57"/>
        <circle cx="168" cy="369" r="10" fill="#ffbd2e"/>
        <circle cx="200" cy="369" r="10" fill="#28c840"/>
        <text x="540" y="377" text-anchor="middle" fill="#8d9bb0" font-family="${mono}" font-size="17">LinkedIn draft</text>
        <rect x="136" y="448" width="808" height="334" rx="22" fill="#0b111b" stroke="${pulse ? "#f0b35a" : "#243045"}" stroke-width="${pulse ? 3 : 1.5}"/>
        ${lineSvg}
      </g>
      <g opacity="${appear(72, 112, frame)}">
        ${pill(122, 914, "U.S. layout active", true, "#8fd3ff")}
        ${pill(122, 972, ";  '  [", true, "#f0b35a")}
        ${pill(262, 972, "æ  ø  å", true, "#6ee7b7")}
      </g>
    </g>`;
}

function appFlowScene(frame) {
  const o = appear(555, 610, frame) * (frame < 755 ? 1 : 1 - appear(755, 790, frame));
  const step = frame < 615 ? 0 : frame < 665 ? 1 : 2;
  return `
    <g opacity="${o}">
      <rect x="110" y="390" width="860" height="430" rx="32" fill="#101722" stroke="#2a3548" stroke-width="2"/>
      <text x="154" y="462" fill="#f8fafc" font-family="${font}" font-size="35" font-weight="760">Recent app settings</text>
      <text x="154" y="506" fill="#91a0b5" font-family="${font}" font-size="24">Rules follow the app you are using.</text>
      ${flowItem(154, 568, "Notion", "Auto-Switch: Last Used", step >= 0)}
      ${flowItem(154, 644, "Slack", "Smart Danish: ON", step >= 1)}
      ${flowItem(154, 720, "Terminal", "Auto-Switch: U.S.", step >= 2)}
    </g>`;
}

function flowItem(x, y, app, value, active) {
  return `
    <g opacity="${active ? 1 : 0.38}">
      <rect x="${x}" y="${y}" width="772" height="56" rx="16" fill="${active ? "#172233" : "#111927"}"/>
      <circle cx="${x + 30}" cy="${y + 28}" r="16" fill="${active ? "#8fd3ff" : "#3b4657"}"/>
      <text x="${x + 62}" y="${y + 36}" fill="#f8fafc" font-family="${font}" font-size="24" font-weight="690">${escapeXml(app)}</text>
      <text x="${x + 744}" y="${y + 36}" text-anchor="end" fill="${active ? "#6ee7b7" : "#8996a9"}" font-family="${font}" font-size="22" font-weight="650">${escapeXml(value)}</text>
    </g>`;
}

function finalScene(frame) {
  const o = appear(800, 845, frame);
  const lift = lerp(24, 0, o);
  return `
    <g opacity="${o}" transform="translate(0 ${lift})">
      <rect x="242" y="382" width="596" height="168" rx="42" fill="#101722" stroke="#324055" stroke-width="2"/>
      <text x="540" y="485" text-anchor="middle" fill="#f8fafc" font-family="${font}" font-size="62" font-weight="820">LayoutPilot</text>
      <text x="540" y="632" text-anchor="middle" fill="#f8fafc" font-family="${font}" font-size="48" font-weight="760">Keep your layout.</text>
      <text x="540" y="696" text-anchor="middle" fill="#8fd3ff" font-family="${font}" font-size="48" font-weight="760">Type Danish faster.</text>
      <text x="540" y="792" text-anchor="middle" fill="#91a0b5" font-family="${font}" font-size="26">macOS utility for keyboard-layout friction</text>
    </g>`;
}

function renderFrame(frame) {
  const [headline, subhead] = caption(frame);
  const headlineOpacity = frame < 780 ? 1 - appear(745, 780, frame) : 0;
  return `<?xml version="1.0" encoding="UTF-8"?>
<svg width="${width}" height="${height}" viewBox="0 0 ${width} ${height}" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#07111f"/>
      <stop offset="0.54" stop-color="#111827"/>
      <stop offset="1" stop-color="#1b1f2a"/>
    </linearGradient>
    <radialGradient id="glow" cx="50%" cy="22%" r="70%">
      <stop offset="0" stop-color="#2b6e85" stop-opacity="0.52"/>
      <stop offset="1" stop-color="#07111f" stop-opacity="0"/>
    </radialGradient>
    <filter id="shadow" x="-20%" y="-20%" width="140%" height="140%">
      <feDropShadow dx="0" dy="22" stdDeviation="24" flood-color="#000" flood-opacity="0.34"/>
    </filter>
  </defs>
  <rect width="${width}" height="${height}" fill="url(#bg)"/>
  <rect width="${width}" height="${height}" fill="url(#glow)"/>
  <g opacity="${headlineOpacity}">
    <text x="92" y="138" fill="#f8fafc" font-family="${font}" font-size="54" font-weight="820" letter-spacing="0">${escapeXml(headline)}</text>
    <text x="94" y="188" fill="#9fb0c6" font-family="${font}" font-size="28" font-weight="520" letter-spacing="0">${escapeXml(subhead)}</text>
  </g>
  <g filter="url(#shadow)">
    ${keyboardScene(frame)}
    ${appFlowScene(frame)}
    ${finalScene(frame)}
  </g>
  <text x="92" y="1246" fill="#5f6f85" font-family="${mono}" font-size="19">LayoutPilot for macOS</text>
  <text x="988" y="1246" text-anchor="end" fill="#5f6f85" font-family="${mono}" font-size="19">US layout + Danish typing</text>
</svg>`;
}

await mkdir(outDir, {recursive: true});
await mkdir(pngDir, {recursive: true});
await mkdir(stillDir, {recursive: true});

for (let frame = 0; frame < totalFrames; frame += 1) {
  const name = `frame-${String(frame).padStart(4, "0")}.svg`;
  await writeFile(path.join(outDir, name), renderFrame(frame), "utf8");
  const pngName = `frame-${String(frame).padStart(4, "0")}.png`;
  execFileSync("sips", [
    "-s", "format", "png",
    path.join(outDir, name),
    "--out", path.join(pngDir, pngName),
  ], {stdio: "ignore"});
  if (frame % 90 === 0) {
    console.log(`Rendered frame ${frame}/${totalFrames}`);
  }
}

await writeFile(path.join(stillDir, "poster.svg"), renderFrame(310), "utf8");

const output = path.join(__dirname, "layoutpilot-linkedin-promo.mp4");
const poster = path.join(__dirname, "layoutpilot-linkedin-poster.png");

execFileSync("ffmpeg", [
  "-y",
  "-framerate", String(fps),
  "-i", path.join(pngDir, "frame-%04d.png"),
  "-vf", "format=yuv420p",
  "-c:v", "libx264",
  "-pix_fmt", "yuv420p",
  "-movflags", "+faststart",
  output,
], {stdio: "inherit"});

execFileSync("sips", [
  "-s", "format", "png",
  path.join(stillDir, "poster.svg"),
  "--out", poster,
], {stdio: "ignore"});

console.log(output);
console.log(poster);
