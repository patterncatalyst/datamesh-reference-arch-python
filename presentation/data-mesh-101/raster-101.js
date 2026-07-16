// raster-101.js — convert the 01-* SVGs from newsvg/ to PNGs in dpng/
// and write dims.json for the deck builder. Uses sharp at 200 DPI.
const sharp = require("sharp");
const fs = require("fs");
const dir = "newsvg", out = "dpng";
if (!fs.existsSync(out)) fs.mkdirSync(out);
(async () => {
  const dims = {};
  for (const f of fs.readdirSync(dir).filter(f => f.endsWith(".svg"))) {
    const base = f.replace(".svg", "");
    const buf = await sharp(fs.readFileSync(dir + "/" + f), { density: 200 })
      .flatten({ background: "#ffffff" }).png().toBuffer();
    fs.writeFileSync(out + "/" + base + ".png", buf);
    const m = await sharp(buf).metadata();
    dims[base] = { w: m.width, h: m.height };
    console.log(base, m.width + "x" + m.height);
  }
  fs.writeFileSync(out + "/dims.json", JSON.stringify(dims, null, 2));
  console.log("wrote dims.json");
})();
