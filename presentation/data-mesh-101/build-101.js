// build-101.js — Data Mesh 101 deck with the data-architecture disambiguation section.
// Run from presentation/data-mesh-101/:  node build-101.js
// Requires: pptxgenjs (global or local), dpng/ with rasterized diagrams + dims.json
const pptxgen = require("pptxgenjs");
const fs = require("fs");

const DIMS = JSON.parse(fs.readFileSync("dpng/dims.json", "utf8"));
const IMG = (name) => `dpng/${name}.png`;
const ASSETS = "../data-mesh-openshift";
const ILLUS = `${ASSETS}/brand-illustration.png`;
const LOGO_DARK = `${ASSETS}/brand-logo-dark.png`;
const LOGO_LIGHT = `${ASSETS}/brand-logo-light.png`;
const LOGO_AR = 496 / 117;

const C = {
  red: "EE0000", dkred: "8A0000", ink: "151515", body: "242424",
  gray: "5A5A5A", gray2: "8A8A8A", white: "FFFFFF",
  paleR: "FFD9D9", paleR2: "F9E3E3",
};
const F = {
  head: "Overpass SemiBold", body: "Red Hat Text", mono: "Red Hat Mono",
};

const pres = new pptxgen();
pres.defineLayout({ name: "W", width: 13.333, height: 7.5 });
pres.layout = "W";
pres.author = "Robert Sedor";
pres.title = "The Data Mesh — A Primer";
const PW = 13.333, PH = 7.5;

let PAGENO = 0;

function footer(slide, { dark = false } = {}) {
  PAGENO += 1;
  slide.addText(String(PAGENO), { x: 0.5, y: PH - 0.5, w: 1, h: 0.3, fontSize: 10, color: dark ? "FFFFFF" : C.gray2, fontFace: F.body, align: "left", margin: 0, transparency: dark ? 20 : 0 });
  const lw = 1.15, lh = lw / LOGO_AR;
  slide.addImage({ path: dark ? LOGO_LIGHT : LOGO_DARK, x: PW - 0.6 - lw, y: PH - 0.28 - lh, w: lw, h: lh });
}

function head(s, eyebrow, title) {
  s.addText(eyebrow.toUpperCase(), { x: 0.7, y: 0.45, w: PW - 1.4, h: 0.32, fontSize: 12, color: C.red, fontFace: F.head, bold: true, charSpacing: 2, margin: 0 });
  s.addText(title, { x: 0.7, y: 0.78, w: PW - 1.4, h: 0.95, fontSize: 30, color: C.ink, fontFace: F.head, bold: true, valign: "top", margin: 0 });
}

function addBullets(s, bullets, { x, y, w, h = 4.6, fontSize = 16 }) {
  const runs = [];
  bullets.forEach((b, i) => {
    const lvl = b.lvl || 0;
    if (b.head) {
      runs.push({ text: b.text, options: { bold: true, color: C.ink, fontFace: F.head, fontSize: fontSize + 1, bullet: false, breakLine: true, paraSpaceBefore: i ? 8 : 0, paraSpaceAfter: 3 } });
    } else {
      runs.push({ text: b.text, options: { color: b.color || (lvl ? C.gray : C.body), fontFace: F.body, fontSize: lvl ? fontSize - 1 : fontSize, bullet: { indent: 18 }, indentLevel: lvl, breakLine: true, paraSpaceAfter: 6 } });
    }
  });
  s.addText(runs, { x, y, w, h, valign: "top", margin: 0 });
}

function titleSlide({ eyebrow, title, subtitle, tagline, breadcrumb, notes }) {
  const s = pres.addSlide();
  s.background = { color: C.white };
  const panelW = PW * 0.37;
  s.addImage({ path: ILLUS, x: 0, y: 0, w: panelW, h: PH, sizing: { type: "crop", w: panelW, h: PH, x: 0, y: 0 } });
  const rx = panelW + 0.7, rw = PW - rx - 0.7;
  s.addText((eyebrow || "THE DATA MESH").toUpperCase(), { x: rx, y: 1.7, w: rw, h: 0.4, fontSize: 14, color: C.red, fontFace: F.head, bold: true, charSpacing: 3, margin: 0 });
  s.addText(title, { x: rx, y: 2.2, w: rw, h: 1.7, fontSize: 42, color: C.ink, fontFace: F.head, bold: true, valign: "top", margin: 0, lineSpacingMultiple: 1.0 });
  if (subtitle) s.addText(subtitle, { x: rx, y: 4.05, w: rw, h: 1.0, fontSize: 17, color: C.gray, fontFace: F.body, italic: true, valign: "top", margin: 0 });
  if (tagline) s.addText(tagline, { x: rx, y: 5.15, w: rw, h: 0.4, fontSize: 15, color: C.ink, fontFace: F.body, bold: true, valign: "top", margin: 0 });
  if (breadcrumb) s.addText(breadcrumb, { x: rx, y: 5.55, w: rw, h: 0.4, fontSize: 13, color: C.gray2, fontFace: F.body, valign: "top", margin: 0 });
  const lw = 1.25, lh = lw / LOGO_AR;
  s.addImage({ path: LOGO_DARK, x: PW - 0.6 - lw, y: PH - 0.3 - lh, w: lw, h: lh });
  if (notes) s.addNotes(notes);
  return s;
}

function divider({ num, title, sub, notes }) {
  const s = pres.addSlide();
  s.addImage({ path: ILLUS, x: 0, y: 0, w: PW, h: PH, sizing: { type: "cover", w: PW, h: PH } });
  const rx = PW * 0.42, rw = PW - rx - 0.7;
  s.addText(num, { x: rx, y: 2.7, w: rw, h: 0.5, fontSize: 22, color: C.white, fontFace: F.mono, bold: true, margin: 0 });
  s.addText(title, { x: rx, y: 3.2, w: rw, h: 1.7, fontSize: 40, color: C.white, fontFace: F.head, bold: true, valign: "top", margin: 0, lineSpacingMultiple: 1.0 });
  if (sub) s.addText(sub, { x: rx, y: 4.95, w: rw, h: 0.8, fontSize: 16, color: C.paleR, fontFace: F.body, italic: true, valign: "top", margin: 0 });
  const lw = 1.25, lh = lw / LOGO_AR;
  s.addImage({ path: LOGO_LIGHT, x: PW - 0.6 - lw, y: PH - 0.3 - lh, w: lw, h: lh });
  PAGENO += 1;
  if (notes) s.addNotes(notes);
  return s;
}

function contentSlide({ eyebrow, title, bullets, notes }) {
  const s = pres.addSlide();
  s.background = { color: C.white };
  head(s, eyebrow, title);
  if (bullets) addBullets(s, bullets, { x: 0.7, y: 1.95, w: PW - 1.4 });
  footer(s);
  if (notes) s.addNotes(notes);
  return s;
}

function diagramSlide({ eyebrow, title, image, caption, notes }) {
  const s = pres.addSlide();
  s.background = { color: C.white };
  head(s, eyebrow, title);
  const d = DIMS[image];
  const maxH = 4.3, maxW = PW - 1.6;
  let w = maxW, h = w * (d.h / d.w);
  if (h > maxH) { h = maxH; w = h * (d.w / d.h); }
  const x = (PW - w) / 2, y = 1.8 + (maxH - h) / 2;
  s.addImage({ path: IMG(image), x, y, w, h });
  if (caption) s.addText(caption, { x: 0.8, y: PH - 1.0, w: PW - 1.6, h: 0.5, fontSize: 12.5, color: C.gray, fontFace: F.body, italic: true, align: "center", valign: "top", margin: 0 });
  footer(s);
  if (notes) s.addNotes(notes);
  return s;
}

/* ============================ TITLE ============================ */
titleSlide({
  eyebrow: "Data Mesh · Primer",
  title: "The Data Mesh",
  subtitle: "From pipelines and warehouses to decentralized, domain-owned data products — the landscape, the principles, and why the mesh is a different kind of answer.",
  tagline: "A primer on data architectures",
  breadcrumb: "Pipelines · Warehouses · Lakes · Data Mesh · Dehghani's Four Principles",
  notes: "Welcome. This deck makes the case for data mesh by first grounding the audience in the landscape of data architectures that came before it. We'll walk through four patterns — data pipelines, data warehouses, data lakes, and data mesh — and show what each solves, where each stalls, and why the mesh is a different kind of answer. Then we'll define data mesh precisely through Dehghani's four principles.",
});

/* ============================ 01 · THE LANDSCAPE ============================ */
divider({ num: "01", title: "The landscape", sub: "Four data architectures — what each pattern solves and the limitation it leaves behind.",
  notes: "Section 1 covers the data architecture landscape. The goal is to build the audience's understanding of why data mesh exists by walking through the patterns that came before it. Each pattern solved a real problem; the mesh is not a replacement for all of them but a response to a specific organizational scaling challenge. We'll spend enough time on each to make the mesh's value proposition concrete rather than abstract." });

/* ---- Data Pipelines ---- */
contentSlide({ eyebrow: "Data architectures", title: "Data pipelines — the plumbing",
  bullets: [
    { text: "The oldest data architecture problem is movement: operational systems produce data, analytical systems consume it, and something has to get it from one to the other." },
    { text: "A data pipeline is that something — a sequence of steps that extracts data from a source, transforms it, and loads it into a target store.", lvl: 1 },
    { head: true, text: "ETL vs. ELT" },
    { text: "ETL (extract-transform-load): transformation happens in transit, before the data lands. ELT (extract-load-transform): raw data lands first, transformation happens in the target." },
    { text: "Both are pipelines: linear, bespoke, point-to-point flows from a known source to a known destination.", lvl: 1 },
    { head: true, text: "The limitation: pipeline sprawl" },
    { text: "Each source-destination pair needs its own pipeline. The total grows as the product of sources and destinations, not the sum. Nobody 'owns' the data flowing through a pipeline — the pipeline is plumbing, not a product.", color: C.ink },
  ],
  notes: "Start with the oldest pattern. Define pipelines concretely: extract-transform-load, or extract-load-transform. The distinction matters (where does the business logic live?) but both are the same shape: linear, bespoke, point-to-point. The limitation is pipeline sprawl — and it's combinatorial. 15 sources times 5 destinations isn't 20 pipelines, it's closer to 75, each with its own schedule, transformation logic, and failure modes. Nobody owns the data in a pipeline — the pipeline is plumbing, not a product. That distinction becomes central when we get to data mesh. The sprawl is what the warehouse was designed to tame.",
});

diagramSlide({ eyebrow: "Data architectures", title: "Pipeline architecture — linear, bespoke, multiplying",
  image: "01-data-pipeline-architecture",
  caption: "Extract-transform-load: each source-destination pair requires its own pipeline, and the total grows as the product of sources and destinations.",
  notes: "Walk the diagram left to right. Sources on the left — CRM, ERP, logs, events — each with its own characteristics and cadence. The ETL box in the center is one pipeline, with its own transformation logic, schedule, and failure modes. Two destinations on the right. Now look at the bottom callout: pipeline sprawl. Each new source or destination doesn't just add one pipeline — it adds as many as there are things on the other side. The dashed lines show the fan-out. At organizational scale, this becomes unmanageable: nobody can see the whole picture, nobody owns the data in transit, and when something breaks at 2 a.m., the question 'whose problem is this?' rarely has a clear answer." });

/* ---- Data Warehouse ---- */
contentSlide({ eyebrow: "Data architectures", title: "Data warehouses — the single source of truth",
  bullets: [
    { text: "A data warehouse is a centralized analytical store, purpose-built for structured queries across the entire business. Where pipelines are plumbing, the warehouse is a destination." },
    { text: "Star schemas, fact tables, dimension tables — all optimized for the aggregations and joins that BI tools need.", lvl: 1 },
    { head: true, text: "Schema-on-write" },
    { text: "Data is modeled and validated before it's stored. The rigidity is a feature: it forces consistency and creates a governed single source of truth." },
    { head: true, text: "The limitation: central-team bottleneck" },
    { text: "The warehouse is owned by a central data team that owns all the data but understands none of the domains. Schema changes require central coordination. The analytical view is always hours or days behind the operational truth.", color: C.ink },
    { text: "As the organization grows, the central team processes more requests than it can understand — the queue becomes the bottleneck.", lvl: 1 },
  ],
  notes: "The warehouse solved the truth problem that pipeline sprawl created. Instead of every consumer building its own understanding from raw pipeline output, everyone queries the same curated model. Schema-on-write is the defining characteristic — and it's a feature, not a bug: when two teams query 'total revenue last quarter,' they get the same number.\n\nThe limitation is organizational, not technical. The central data team — sometimes called the BI team, the analytics engineering team, the data platform team — becomes the bottleneck in direct proportion to the organization's growth. They own all the data but understand none of the domains. When the logistics domain needs a new dimension, the request goes to the central team, who must learn enough about logistics to model it correctly, prioritize it against every other domain's requests, and coordinate the schema change without breaking downstream consumers. The analytical view is always stale because the ingestion pipelines run on a schedule, and the central team's capacity to model new data is the real constraint.",
});

diagramSlide({ eyebrow: "Data architectures", title: "Warehouse architecture — many sources, one team, one store",
  image: "01-data-warehouse-architecture",
  caption: "Many sources, one warehouse, one team — the single source of truth, and the single point of contention.",
  notes: "Walk the hub-and-spoke. Sources on the left — the same CRM, ERP, logs, events from before — all flowing into one centralized warehouse. The warehouse card in the center lists the defining characteristics: schema-on-write, star schemas, dimensional models, governed and structured. Consumers on the right: BI dashboards, reports, analysts — all querying the same governed store.\n\nNow look at the bottom: the Central Data Team card. This is the bottleneck. Every schema change, every new data source, every question funnels through this one team. The dashed arrows connecting them to the warehouse make the coupling visible. They own everything but understand none of the domains. The label says it plainly: 'the bottleneck a mesh exists to remove.' This team — not the technology — is what the mesh reorganizes.",
});

/* ---- Data Lake ---- */
contentSlide({ eyebrow: "Data architectures", title: "Data lakes — accept everything, sort it out later",
  bullets: [
    { text: "A data lake accepts data in any format — structured, semi-structured, unstructured, streaming — and defers schema decisions to the point of consumption. This is schema-on-read." },
    { head: true, text: "Zone-based organization" },
    { text: "Raw zone: data exactly as it arrived. Curated zone: cleaned, validated, enriched. Refined zone: modeled and aggregated for specific consumption patterns.", lvl: 1 },
    { head: true, text: "What it solved" },
    { text: "The warehouse's format rigidity. A warehouse can't easily accommodate a Kafka topic of JSON events, a directory of Parquet files, or a bucket of images for computer vision. The lake can." },
    { head: true, text: "The limitation: the swamp" },
    { text: "Without governance, the lake becomes a data swamp — undocumented, stale, duplicated datasets nobody trusts. The curation effort re-creates warehouse work, and a central team still owns the bucket.", color: C.ink },
  ],
  notes: "The lake solved the warehouse's most visible problem: format inflexibility. The warehouse can't handle Kafka events, Parquet files, images, sensor data. The lake can. At massive scale with cheap object storage, the lake makes it feasible to keep everything and decide later what's worth querying. That flexibility unlocked workloads — ML, unstructured analytics, exploratory data science — that warehouses were never built for.\n\nThe zone model is how well-run lakes organize the data: raw (as-is from sources), curated (cleaned, typed), refined (modeled for consumption). The progression from raw to refined represents increasing transformation and decreasing generality.\n\nThe limitation is governance. Without active curation, the lake becomes the 'data swamp' — undocumented datasets accumulate, nobody knows which version is authoritative, which datasets are stale, which duplicate each other. The curation effort needed to make a lake useful re-creates the warehouse's modeling work, just without the warehouse's enforcement mechanisms. And the organizational problem is unchanged: a central team still owns the lake.",
});

diagramSlide({ eyebrow: "Data architectures", title: "Lake architecture — zones, flexibility, and the swamp risk",
  image: "01-data-lake-architecture",
  caption: "Raw, curated, refined — flexible on the way in, but without governance the lake becomes a swamp, and the central-team bottleneck remains.",
  notes: "Walk the architecture. Heterogeneous sources on the left — structured, semi-structured, unstructured, streaming — this is the format flexibility the lake provides. The center shows the lake with its three zones in graduated shading: the raw/landing zone (data as-is), the curated zone (cleaned and typed), the refined zone (modeled and ready for consumption). Consumers on the right: analytics, ML/AI, reporting, ad-hoc queries — the diverse workloads the lake enables.\n\nNow the red callout at the bottom: 'Without governance, the lake becomes a swamp.' Data lands in the raw zone and never moves. Nobody knows what's valid, what's stale, what duplicates what. Schema-on-read means consumers discover structure at query time — if they can find the data at all. And the final line: the organizational bottleneck is unchanged. A central team still owns the bucket.",
});

/* ---- How Data Mesh Differs ---- */
contentSlide({ eyebrow: "Data architectures", title: "Data mesh — a different kind of answer",
  bullets: [
    { text: "All three patterns — pipelines, warehouses, lakes — centralize data and hand ownership to a single team. The technology improves; the organizational shape stays the same: one team at the center." },
    { head: true, text: "The mesh changes the organizational shape" },
    { text: "Instead of building a better center, decentralize ownership to the domain teams that produce the data. Each domain owns its data as a product — discoverable, addressable, trustworthy, self-describing." },
    { text: "A shared self-serve platform provides the infrastructure. Federated computational governance keeps the independently-owned products interoperable.", lvl: 1 },
    { head: true, text: "Not a replacement" },
    { text: "A domain may still use a warehouse or a lake internally. The reorganization is about who owns the data, not which storage technology to use.", color: C.ink },
    { text: "The mesh earns its complexity in organizations with many domains, many consumers, and the maturity to operate federated ownership.", lvl: 1 },
  ],
  notes: "This is the pivot slide — from what came before to what the mesh proposes. The key insight: all three prior patterns centralize data and hand ownership to a single team. The technology improves generation by generation — from bespoke pipelines, to a governed warehouse, to a flexible lake — but the organizational shape stays the same. One team at the center, receiving requests from every domain, owning data it did not produce, modeling concepts it does not deeply understand, scaling linearly while demands grow combinatorially.\n\nThe mesh changes the axis: instead of a better center, decentralize ownership. Each domain owns its data as a product. A shared platform provides streaming, storage, registries, observability — so domains don't each build their own. Federated governance keeps the products interoperable — through platform-enforced standards, not review boards.\n\nCritical clarification: the mesh is not a replacement for warehouses or lakes. A domain may use a warehouse internally. The reorganization is about who owns the data — not which database to pick. And the honest caveat: the mesh earns its complexity in organizations with many domains, many consumers, and the maturity to operate federated ownership. For smaller teams, a well-run warehouse may be exactly right.",
});

diagramSlide({ eyebrow: "Data architectures", title: "The mesh — decentralized, domain-owned data products",
  image: "01-data-mesh-decentralized",
  caption: "Each domain owns its data as a product, on a shared platform under federated governance — the organizational answer.",
  notes: "Walk the diagram. Top band: federated computational governance — standards enforced by the platform, automatically. The 2x2 grid shows four domain data products — Orders, Inventory, Payment, Shipping — each a red card because this is the target pattern. Each card shows: the domain name, what it owns, 'owns its data,' three API port pills (REST, gRPC, Events), and 'team-owned' at the bottom. The bidirectional red arrows between domains show inter-domain communication — products talking to products.\n\nBottom band: the self-serve data platform — shared infrastructure every domain consumes: streaming, storage, mesh, observability. This is the organizational shape that's different: no central data team owning everything. Each domain owns its own data; the platform and governance make them interoperable. The contrast with the warehouse slide should be visceral: there's no 'Central Data Team' card here.",
});

/* ---- Evolution ---- */
diagramSlide({ eyebrow: "Data architectures", title: "The evolution — from pipelines to mesh",
  image: "01-architecture-evolution",
  caption: "Each pattern solved the problem the previous one left; the mesh solves the organizational scaling problem they all share.",
  notes: "The synthesis slide. Walk left to right through the four columns. Pipelines (blue): solved the movement problem, but the limitation is pipeline sprawl and no ownership model. Warehouses (orange): solved the truth problem — a single governed view — but the limitation is the central team bottleneck. Lakes (green): solved the flexibility problem — any format, any workload — but the limitation is swamp risk and the same organizational bottleneck. Mesh (red): solves the organizational scaling problem — decentralized ownership — but requires organizational maturity.\n\nThe bottom band makes the organizational dimension explicit: point-to-point → centralized team → centralized team (bigger) → decentralized ownership. The progression isn't 'each is better than the last' — it's 'each solves a different problem.' A pipeline is still right when movement is the problem. A warehouse is still right when truth is the problem. A lake is still right when flexibility is the problem. The mesh is right when the bottleneck is organizational.",
});

/* ---- When Each Fits ---- */
contentSlide({ eyebrow: "Data architectures", title: "When each pattern fits",
  bullets: [
    { text: "The choice depends on scale, data landscape, and where the bottleneck sits — not on which pattern is newest." },
    { head: true, text: "Pipelines" },
    { text: "Small number of well-understood integrations, stable data flows, no pressing need for centralized cross-domain analytics. The sprawl hasn't started.", lvl: 1 },
    { head: true, text: "Warehouse" },
    { text: "The organization needs a governed analytical view — BI, reporting, structured decisions — and a central team has the capacity to curate it. The bottleneck is the absence of a single source of truth.", lvl: 1 },
    { head: true, text: "Lake" },
    { text: "Heterogeneous data, ML/AI workloads, scale that exceeds what a warehouse handles. The bottleneck is format rigidity, not organizational ownership.", lvl: 1 },
    { head: true, text: "Mesh" },
    { text: "Many domains, many consumers, and the central team has become the constraint. The bottleneck is organizational — who owns what — not technical.", color: C.ink },
  ],
  notes: "The honest slide. Not every organization needs a mesh. The question is whether the bottleneck is technical (better tools solve it) or organizational (who owns what). Walk each:\n\n• Pipelines fit when the plumbing is simple enough that sprawl hasn't started. A handful of integrations, stable flows, known sources and destinations. Don't add complexity before the problem demands it.\n\n• Warehouses fit when the organization needs a single source of truth for BI and reporting, and a central team has the capacity to curate the data. If the bottleneck is 'we don't know the truth,' the warehouse is the answer.\n\n• Lakes fit when the data is heterogeneous — logs, events, images, ML training sets — and the scale or workload patterns exceed what a warehouse handles. The bottleneck is format rigidity, not organizational ownership.\n\n• Mesh fits when the organization has outgrown centralized ownership. Many domains, many consumers, and the central team is the constraint. The bottleneck is organizational — not which tool to buy. The organization also needs the maturity to operate federated ownership: domain teams that can treat data as a product, a platform team that can provide self-serve infrastructure, and governance that works through automation.\n\nTelling people when NOT to use a mesh builds credibility for when you say they should.",
});

/* ============================ CLOSING ============================ */
(() => {
  const s = pres.addSlide();
  s.addImage({ path: ILLUS, x: 0, y: 0, w: PW, h: PH, sizing: { type: "cover", w: PW, h: PH } });
  const rx = PW * 0.42, rw = PW - rx - 0.7;
  s.addText("The mesh is the network of products —", { x: rx, y: 2.5, w: rw, h: 0.9, fontSize: 28, color: "FFFFFF", fontFace: F.head, bold: true, valign: "top", margin: 0 });
  s.addText("plus the platform and standards\nthat let them interoperate.", { x: rx, y: 3.35, w: rw, h: 1.2, fontSize: 28, color: "FFD9D9", fontFace: F.head, bold: true, valign: "top", margin: 0 });
  s.addText("Each pattern solved a real problem; the mesh solves the organizational one they all left behind.", { x: rx, y: 4.85, w: rw, h: 0.6, fontSize: 15, color: "FFFFFF", fontFace: F.body, italic: true, valign: "top", margin: 0 });
  const lw = 1.25, lh = lw / LOGO_AR;
  s.addImage({ path: LOGO_LIGHT, x: PW - 0.6 - lw, y: PH - 0.3 - lh, w: lw, h: lh });
  PAGENO += 1;
  s.addNotes("Closing slide. The one-sentence definition: a mesh is the network of products plus the platform and standards that let them interoperate. And the grounding from today: each pattern we walked through solved a real problem — the mesh solves the organizational one they all left behind. Open for questions.");
})();

/* ============================ WRITE ============================ */
pres.writeFile({ fileName: "The_Data_Mesh_101.pptx" }).then((f) => console.log("WROTE", f));
