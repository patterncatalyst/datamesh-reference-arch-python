// makediagrams-101.js — generate the 5 data-architecture disambiguation diagrams
// for the Data Mesh 101 educational content.  Each diagram contrasts a pattern
// (pipelines, warehouse, lake, mesh) and the final diagram shows the evolution.
//
// Color assignments:
//   pipelines → blue   warehouse → orange   lake → green   mesh → red

const { SVG, FAM } = require("../data-mesh-openshift/svglib.js");
const fs = require("fs");
const path = require("path");

const OUT = "newsvg";
const SITE = path.resolve(__dirname, "../../assets/diagrams");
if (!fs.existsSync(OUT)) fs.mkdirSync(OUT);

const save = (name, svg) => {
  fs.writeFileSync(`${OUT}/${name}.svg`, svg.render());
  fs.writeFileSync(`${OUT}/${name}.excalidraw`, svg.excalidraw());
  // also copy to site diagrams
  fs.writeFileSync(`${SITE}/${name}.svg`, svg.render());
  fs.writeFileSync(`${SITE}/${name}.excalidraw`, svg.excalidraw());
  console.log("wrote", name, "(svg + excalidraw)");
};

/* ========================================================================
   1.  DATA PIPELINE ARCHITECTURE — linear ETL with pipeline-sprawl callout
   ======================================================================== */
(() => {
  const s = new SVG(1180, 480);
  s.title("Data pipelines — bespoke point-to-point movement",
          "Extract-Transform-Load: move data from A to B, one pairing at a time");

  // ---- left: source systems (blue) ----
  const sources = ["CRM", "ERP", "Logs", "Events"];
  const srcX = 60, srcW = 120, srcH = 56, srcGap = 12;
  const srcY0 = 88;
  sources.forEach((name, i) => {
    const y = srcY0 + i * (srcH + srcGap);
    s.rect(srcX, y, srcW, srcH, "blue");
    s.text(srcX + srcW / 2, y + 33, name, { size: 12, anchor: "middle", weight: 700, fill: FAM.blue.head });
  });

  // ---- center: ETL processing stage ----
  const etlX = 340, etlY = 120, etlW = 280, etlH = 100;
  s.rect(etlX, etlY, etlW, etlH, "blue");
  s.text(etlX + etlW / 2, etlY + 30, "ETL Pipeline", { size: 14, anchor: "middle", weight: 700, fill: FAM.blue.head });
  s.text(etlX + etlW / 2, etlY + 58, "Extract  →  Transform  →  Load", { size: 13, anchor: "middle", fill: "#3a3a3a" });
  s.text(etlX + etlW / 2, etlY + 80, "one bespoke pipeline per pairing", { size: 10, anchor: "middle", italic: true, fill: "#666666" });

  // ---- right: destinations ----
  const destX = 780, destW = 200, destH = 65;
  s.rect(destX, 110, destW, destH, "orange");
  s.text(destX + destW / 2, 135, "Data Warehouse", { size: 12, anchor: "middle", weight: 700, fill: FAM.orange.head });
  s.text(destX + destW / 2, 155, "structured, queryable", { size: 10, anchor: "middle", fill: "#3a3a3a" });

  s.rect(destX, 195, destW, destH, "orange");
  s.text(destX + destW / 2, 220, "Dashboard / BI", { size: 12, anchor: "middle", weight: 700, fill: FAM.orange.head });
  s.text(destX + destW / 2, 240, "visual analytics", { size: 10, anchor: "middle", fill: "#3a3a3a" });

  // ---- arrows: sources → ETL ----
  sources.forEach((_, i) => {
    const sy = srcY0 + i * (srcH + srcGap) + srcH / 2;
    s.arrow(srcX + srcW + 4, sy, etlX - 4, etlY + etlH / 2, { color: "#2c5aa0", marker: "arrB", w: 1.4 });
  });

  // ---- arrows: ETL → destinations ----
  s.arrow(etlX + etlW + 4, etlY + 30, destX - 4, 142, { color: "#5a5a5a", w: 1.4 });
  s.arrow(etlX + etlW + 4, etlY + 70, destX - 4, 228, { color: "#5a5a5a", w: 1.4 });

  // ---- bottom callout: pipeline sprawl (tan) ----
  s.rect(60, 310, 1060, 120, "tan");
  s.text(80, 340, "Pipeline sprawl — the n × m problem", { size: 13, weight: 700, fill: FAM.tan.head });
  s.lines(80, 365, [
    "Each source × destination pairing needs its own bespoke pipeline.",
    "4 sources × 3 destinations = 12 pipelines; add one source and you add 3 more.",
    "Ownership fragments; no single team can see the whole picture.",
  ], { size: 11, fill: "#3a3a3a", lh: 18 });

  // dashed lines illustrating sprawl (n x m fan-out)
  const dSrcY = [325, 345, 365, 385];
  const dDestY = [325, 355, 385];
  dSrcY.forEach(sy => {
    dDestY.forEach(dy => {
      s.arrow(760, sy, 1080, dy, { color: "#c19a6b", w: 0.8, dash: "4 3" });
    });
  });

  s.footer("Each pipeline is bespoke; as sources and destinations multiply, the sprawl becomes the problem.");
  save("01-data-pipeline-architecture", s);
})();

/* ========================================================================
   2.  DATA WAREHOUSE ARCHITECTURE — hub-and-spoke, central team bottleneck
   ======================================================================== */
(() => {
  const s = new SVG(1180, 520);
  s.title("Data warehouse — a single source of truth, one team to rule it all",
          "Schema-on-write, star schemas, dimensional models — everything funneled through a central gate");

  // ---- left column: source systems (blue) ----
  const sources = ["CRM", "ERP", "Logs", "Events"];
  const srcX = 60, srcW = 130, srcH = 52, srcGap = 10;
  const srcY0 = 82;
  sources.forEach((name, i) => {
    const y = srcY0 + i * (srcH + srcGap);
    s.rect(srcX, y, srcW, srcH, "blue");
    s.text(srcX + srcW / 2, y + 31, name, { size: 12, anchor: "middle", weight: 700, fill: FAM.blue.head });
  });

  // ---- center: large warehouse card (orange) ----
  const whX = 340, whY = 82, whW = 340, whH = 200;
  s.rect(whX, whY, whW, whH, "orange");
  s.text(whX + whW / 2, whY + 30, "Centralized Data Warehouse", { size: 14, anchor: "middle", weight: 700, fill: FAM.orange.head });
  s.lines(whX + 30, whY + 62, [
    "Schema-on-write",
    "Star schemas / snowflake",
    "Dimensional models",
    "Governed, structured, slow to change",
  ], { size: 11, fill: "#3a3a3a", lh: 18 });
  s.text(whX + whW / 2, whY + 160, "everything lands here first", { size: 10, anchor: "middle", italic: true, fill: "#666666" });
  s.text(whX + whW / 2, whY + 180, "and is modeled by one team", { size: 10, anchor: "middle", italic: true, fill: "#666666" });

  // ---- right column: consumers (green) ----
  const consumers = ["BI Dashboards", "Reports", "Analysts"];
  const conX = 840, conW = 150, conH = 52;
  const conY0 = 95;
  consumers.forEach((name, i) => {
    const y = conY0 + i * (conH + srcGap);
    s.rect(conX, y, conW, conH, "green");
    s.text(conX + conW / 2, y + 31, name, { size: 12, anchor: "middle", weight: 700, fill: FAM.green.head });
  });

  // ---- arrows: sources → warehouse ----
  sources.forEach((_, i) => {
    const sy = srcY0 + i * (srcH + srcGap) + srcH / 2;
    s.arrow(srcX + srcW + 4, sy, whX - 4, whY + whH / 2, { color: "#2c5aa0", marker: "arrB", w: 1.4 });
  });

  // ---- arrows: warehouse → consumers ----
  consumers.forEach((_, i) => {
    const cy = conY0 + i * (conH + srcGap) + conH / 2;
    s.arrow(whX + whW + 4, whY + whH / 2, conX - 4, cy, { color: "#5a8a3a", marker: "arrG", w: 1.4 });
  });

  // ---- bottom-center: central data team bottleneck (tan) ----
  const ctX = 300, ctY = 340, ctW = 580, ctH = 100;
  s.rect(ctX, ctY, ctW, ctH, "tan");
  s.text(ctX + ctW / 2, ctY + 28, "Central Data Team", { size: 14, anchor: "middle", weight: 700, fill: FAM.tan.head });
  s.lines(ctX + 30, ctY + 52, [
    "Owns all the data, understands none of the domains.",
    "Every schema change, every new data source, every question funnels here.",
    "The bottleneck a mesh exists to remove.",
  ], { size: 11, fill: "#3a3a3a", lh: 18 });

  // arrows from central team → warehouse (showing bottleneck)
  s.arrow(ctX + ctW / 2 - 60, ctY, whX + whW / 2 - 40, whY + whH + 4, { color: "#c19a6b", w: 1.8, dash: "5 3" });
  s.arrow(ctX + ctW / 2 + 60, ctY, whX + whW / 2 + 40, whY + whH + 4, { color: "#c19a6b", w: 1.8, dash: "5 3" });
  s.label(ctX + ctW / 2, ctY - 10, "bottleneck");

  s.footer("One team owns all the data but understands none of the domains — the bottleneck a mesh exists to remove.");
  save("01-data-warehouse-architecture", s);
})();

/* ========================================================================
   3.  DATA LAKE ARCHITECTURE — zone-based with swamp warning
   ======================================================================== */
(() => {
  const s = new SVG(1180, 520);
  s.title("Data lake — accept everything, sort it out later",
          "Schema-on-read, zone-based, format-agnostic — flexible until it becomes a swamp");

  // ---- left: heterogeneous sources (blue) ----
  const sources = ["Structured", "Semi-structured", "Unstructured", "Streaming"];
  const srcX = 50, srcW = 140, srcH = 50, srcGap = 10;
  const srcY0 = 82;
  sources.forEach((name, i) => {
    const y = srcY0 + i * (srcH + srcGap);
    s.rect(srcX, y, srcW, srcH, "blue");
    s.text(srcX + srcW / 2, y + 30, name, { size: 11.5, anchor: "middle", weight: 700, fill: FAM.blue.head });
  });

  // ---- center: data lake with three zones ----
  const lakeX = 340, lakeY = 78, lakeW = 360, lakeH = 220;
  // outer green container
  s.rect(lakeX, lakeY, lakeW, lakeH, "green");
  s.text(lakeX + lakeW / 2, lakeY + 22, "Data Lake", { size: 15, anchor: "middle", weight: 700, fill: FAM.green.head });

  // three zone sub-rects with varying green shades
  const zoneH = 48, zoneGap = 10, zoneX = lakeX + 16, zoneW = lakeW - 32;
  const zones = [
    { label: "Raw / Landing zone",  fill: "#d4e8c6", stroke: "#5a8a3a", desc: "ingest as-is" },
    { label: "Curated zone",        fill: "#c5ddb6", stroke: "#4a7a2a", desc: "cleaned, typed" },
    { label: "Refined zone",        fill: "#b6d2a6", stroke: "#3a6a1a", desc: "modeled, ready" },
  ];
  zones.forEach((z, i) => {
    const zy = lakeY + 38 + i * (zoneH + zoneGap);
    s.plainRect(zoneX, zy, zoneW, zoneH, z.fill, z.stroke);
    s.text(zoneX + 16, zy + 24, z.label, { size: 12, weight: 700, fill: "#2a5a1a" });
    s.text(zoneX + zoneW - 16, zy + 24, z.desc, { size: 10, anchor: "end", italic: true, fill: "#4a6a3a" });
  });

  // ---- right: consumers (orange) ----
  const consumers = ["Analytics", "ML / AI", "Reporting", "Ad-hoc queries"];
  const conX = 850, conW = 150, conH = 50;
  const conY0 = 82;
  consumers.forEach((name, i) => {
    const y = conY0 + i * (conH + srcGap);
    s.rect(conX, y, conW, conH, "orange");
    s.text(conX + conW / 2, y + 30, name, { size: 11.5, anchor: "middle", weight: 700, fill: FAM.orange.head });
  });

  // ---- arrows: sources → lake ----
  sources.forEach((_, i) => {
    const sy = srcY0 + i * (srcH + srcGap) + srcH / 2;
    s.arrow(srcX + srcW + 4, sy, lakeX - 4, lakeY + lakeH / 2, { color: "#2c5aa0", marker: "arrB", w: 1.4 });
  });

  // ---- arrows: lake → consumers ----
  consumers.forEach((_, i) => {
    const cy = conY0 + i * (conH + srcGap) + conH / 2;
    s.arrow(lakeX + lakeW + 4, lakeY + lakeH / 2, conX - 4, cy, { color: "#5a5a5a", w: 1.4 });
  });

  // ---- bottom callout: swamp warning (red) ----
  s.rect(60, 340, 1060, 100, "red");
  s.text(80, 368, "Without governance, the lake becomes a swamp", { size: 13, weight: 700, fill: FAM.red.head });
  s.lines(80, 392, [
    "Data lands in the raw zone and never moves — nobody knows what it is or whether it's still valid.",
    "A central team still owns the bucket; the organizational bottleneck is unchanged.",
    "Schema-on-read means consumers discover structure at query time — if they can find the data at all.",
  ], { size: 11, fill: "#3a3a3a", lh: 18 });

  s.footer("Accept everything, sort it out later — but sorting it out still requires the same central team.");
  save("01-data-lake-architecture", s);
})();

/* ========================================================================
   4.  DATA MESH — DECENTRALIZED DOMAIN OWNERSHIP
   ======================================================================== */
(() => {
  const s = new SVG(1180, 520);
  s.title("Data mesh — decentralized, domain-owned data products",
          "Each domain owns its data as a product; the platform and governance make them interoperable");

  // ---- top band: federated governance ----
  const govY = 70, govH = 50;
  s.rect(60, govY, 1060, govH, "gray");
  s.text(590, govY + 22, "Federated computational governance", { size: 13, anchor: "middle", weight: 700, fill: FAM.gray.head });
  s.text(590, govY + 40, "standards enforced by the platform, automatically", { size: 10.5, anchor: "middle", italic: true, fill: "#666666" });

  // ---- center: 2x2 grid of domain data products (red) ----
  const domains = [
    { name: "Orders domain",    desc: "order lifecycle data" },
    { name: "Inventory domain", desc: "stock levels + catalog" },
    { name: "Payment domain",   desc: "transactions + ledger" },
    { name: "Shipping domain",  desc: "fulfillment + tracking" },
  ];
  const cardW = 250, cardH = 150, gapX = 30, gapY = 20;
  const gridX0 = 170, gridY0 = 140;
  const positions = [
    { col: 0, row: 0 }, { col: 1, row: 0 },
    { col: 0, row: 1 }, { col: 1, row: 1 },
  ];

  domains.forEach((d, i) => {
    const cx = gridX0 + positions[i].col * (cardW + gapX + 200);
    const cy = gridY0 + positions[i].row * (cardH + gapY);
    s.rect(cx, cy, cardW, cardH, "red");
    s.text(cx + cardW / 2, cy + 24, d.name, { size: 13, anchor: "middle", weight: 700, fill: FAM.red.head });
    s.text(cx + cardW / 2, cy + 44, d.desc, { size: 10.5, anchor: "middle", fill: "#3a3a3a" });
    s.text(cx + cardW / 2, cy + 64, "owns its data", { size: 10, anchor: "middle", italic: true, fill: "#666666" });

    // API pills
    s.pill(cx + 14, cy + 80, 64, "REST", "blue", { h: 22 });
    s.pill(cx + 88, cy + 80, 64, "gRPC", "green", { h: 22 });
    s.pill(cx + 162, cy + 80, 74, "Events", "orange", { h: 22 });

    // team-owned label
    s.label(cx + cardW / 2, cy + cardH - 14, "team-owned");
  });

  // ---- inter-domain arrows ----
  // Row 1: Orders ↔ Inventory
  const r1Left = gridX0 + cardW, r1Right = gridX0 + cardW + gapX + 200;
  const r1Y = gridY0 + cardH / 2;
  s.arrow(r1Left + 4, r1Y - 6, r1Right - 4, r1Y - 6, { color: "#c14a3a", marker: "arrR", w: 1.6 });
  s.arrow(r1Right - 4, r1Y + 6, r1Left + 4, r1Y + 6, { color: "#c14a3a", marker: "arrR", w: 1.6 });

  // Row 2: Payment ↔ Shipping
  const r2Y = gridY0 + (cardH + gapY) + cardH / 2;
  s.arrow(r1Left + 4, r2Y - 6, r1Right - 4, r2Y - 6, { color: "#c14a3a", marker: "arrR", w: 1.6 });
  s.arrow(r1Right - 4, r2Y + 6, r1Left + 4, r2Y + 6, { color: "#c14a3a", marker: "arrR", w: 1.6 });

  // Vertical: Orders → Payment
  const colLX = gridX0 + cardW / 2;
  s.arrow(colLX, gridY0 + cardH + 4, colLX, gridY0 + cardH + gapY - 4, { color: "#c14a3a", marker: "arrR", w: 1.4 });

  // Vertical: Inventory → Shipping
  const colRX = gridX0 + cardW + gapX + 200 + cardW / 2;
  s.arrow(colRX, gridY0 + cardH + 4, colRX, gridY0 + cardH + gapY - 4, { color: "#c14a3a", marker: "arrR", w: 1.4 });

  // ---- bottom band: self-serve data platform ----
  const platY = 460, platH = 44;
  s.rect(60, platY, 1060, platH, "tan");
  s.text(590, platY + 20, "Self-serve data platform", { size: 13, anchor: "middle", weight: 700, fill: FAM.tan.head });
  s.text(590, platY + 38, "shared infrastructure every domain consumes — streaming, storage, mesh, observability", { size: 10.5, anchor: "middle", italic: true, fill: "#666666" });

  s.footer("Each domain owns its data as a product; the platform and governance make them interoperable.");
  save("01-data-mesh-decentralized", s);
})();

/* ========================================================================
   5.  ARCHITECTURE EVOLUTION — four-column timeline
   ======================================================================== */
(() => {
  const s = new SVG(1180, 560);
  s.title("The evolution of data architecture",
          "Each pattern solved the problem the previous one left behind");

  // ---- four columns ----
  const cols = [
    {
      fam:     "blue",
      label:   "Data Pipelines",
      era:     "1990s –",
      solved:  "Moving data\nfrom A to B",
      limit:   "Pipeline sprawl;\nno ownership",
    },
    {
      fam:     "orange",
      label:   "Data Warehouse",
      era:     "2000s –",
      solved:  "Single source\nof truth",
      limit:   "Central team\nbottleneck",
    },
    {
      fam:     "green",
      label:   "Data Lake",
      era:     "2010s –",
      solved:  "Format flexibility\nat scale",
      limit:   "Swamp risk;\nsame bottleneck",
    },
    {
      fam:     "red",
      label:   "Data Mesh",
      era:     "2019 –",
      solved:  "Organizational\nscaling",
      limit:   "Requires\nmaturity",
    },
  ];

  const colW = 220, colH = 300, gap = 30, x0 = 70, y0 = 70;

  cols.forEach((c, i) => {
    const x = x0 + i * (colW + gap);
    const f = FAM[c.fam];

    // main column rect
    s.rect(x, y0, colW, colH, c.fam);

    // title
    s.text(x + colW / 2, y0 + 28, c.label, { size: 14, anchor: "middle", weight: 700, fill: f.head });
    s.text(x + colW / 2, y0 + 46, c.era, { size: 10, anchor: "middle", italic: true, fill: "#666666" });

    // problem solved section
    s.text(x + 16, y0 + 78, "PROBLEM SOLVED", { size: 9, weight: 600, fill: "#8a7a5a" });
    s.plainRect(x + 14, y0 + 86, colW - 28, 56, "#ffffff", f.stroke, { rx: 6 });
    const solvedLines = c.solved.split("\n");
    s.lines(x + colW / 2, y0 + 108, solvedLines, { size: 12, anchor: "middle", fill: f.head, weight: 700, lh: 18 });

    // limitation section
    s.text(x + 16, y0 + 162, "LIMITATION", { size: 9, weight: 600, fill: "#8a7a5a" });
    s.plainRect(x + 14, y0 + 170, colW - 28, 56, "#ffffff", f.stroke, { rx: 6, dash: "4 3" });
    const limitLines = c.limit.split("\n");
    s.lines(x + colW / 2, y0 + 192, limitLines, { size: 11.5, anchor: "middle", fill: "#3a3a3a", lh: 17 });

    // key pattern descriptor at bottom of column
    const patterns = ["Point-to-point", "Hub-and-spoke", "Zone-based", "Domain-owned"];
    s.text(x + colW / 2, y0 + colH - 20, patterns[i], { size: 11, anchor: "middle", weight: 700, fill: f.head });

    // evolution arrows between columns
    if (i < 3) {
      const ax = x + colW + 4;
      const bx = ax + gap - 8;
      s.arrow(ax, y0 + colH / 2, bx, y0 + colH / 2, { color: "#5a5a5a", w: 2 });
    }
  });

  // ---- bottom band: organizational dimension ----
  const bandY = y0 + colH + 30;
  s.rect(x0, bandY, 4 * colW + 3 * gap, 70, "tan");
  s.text(x0 + 16, bandY + 22, "ORGANIZATIONAL DIMENSION", { size: 10, weight: 600, fill: "#8a7a5a" });

  const orgLabels = ["Point-to-point", "Centralized team", "Centralized team (bigger)", "Decentralized ownership"];
  cols.forEach((c, i) => {
    const x = x0 + i * (colW + gap) + colW / 2;
    s.text(x, bandY + 48, orgLabels[i], { size: 11, anchor: "middle", weight: 700, fill: FAM[c.fam].head });
    // small connecting arrows
    if (i < 3) {
      const ax1 = x + 60;
      const ax2 = x0 + (i + 1) * (colW + gap) + colW / 2 - 60;
      s.arrow(ax1, bandY + 44, ax2, bandY + 44, { color: "#5a5a5a", w: 1.2 });
    }
  });

  s.footer("Each pattern solved the problem the previous one left; the mesh solves the organizational scaling problem they all share.");
  save("01-architecture-evolution", s);
})();

console.log("DONE");
