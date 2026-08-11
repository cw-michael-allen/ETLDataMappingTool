// Target-database metadata comes from /api/target-databases, not a hardcoded
// map. Availability used to be `targetDatabase !== "CaseWorthy"`, which meant
// adding a schema file could never actually enable a database in the UI. The
// server now reports whether a schema loaded, plus each database's modules.
// This literal is only a fallback for the first paint, before the fetch lands.
const FALLBACK_DB_META = {
  CaseWorthy: { label: "CaseWorthy", logo: "/assets/logos/caseworthy-corporate.png" },
  ServTracker: { label: "ServTracker", logo: "/assets/logos/servtracker.png" },
};

function dbMeta(name) {
  const fetched = (state.targetDbs || []).find(d => d.name === name);
  return fetched || FALLBACK_DB_META[name] || FALLBACK_DB_META.CaseWorthy;
}

function activeDb() {
  return dbMeta(state.targetDatabase);
}

function dbLabel() {
  return activeDb().label || state.targetDatabase;
}

// Base modules are always in scope, whether or not the customer ticked them.
function effectiveModules() {
  const meta = activeDb();
  if (!meta.hasModules) return [];
  const base = meta.baseModules || [];
  return [...new Set([...base, ...state.modules])];
}

const THEME_STORAGE_KEY = "cw-etl-fieldmap-theme";
// Learned mappings are stored per target database (db.py's target_db column),
// so a fresh page load defaulting back to CaseWorthy made a ServTracker
// session's confirmed mappings look like they'd vanished -- they hadn't, the
// footer counter was just showing a different database's count. Persisting
// the last-used database (same pattern as the theme toggle) means reopening
// the tool lands back where those confirmations are actually visible.
const TARGET_DB_STORAGE_KEY = "cw-etl-fieldmap-target-db";

function getTheme() {
  return document.documentElement.dataset.theme
    || (window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light");
}

function setTheme(theme) {
  document.documentElement.dataset.theme = theme;
  localStorage.setItem(THEME_STORAGE_KEY, theme);
}

function initTheme() {
  const stored = localStorage.getItem(THEME_STORAGE_KEY);
  if (stored) document.documentElement.dataset.theme = stored;
}

function renderThemeToggle() {
  const nextLabel = getTheme() === "dark" ? "Light Mode" : "Dark Mode";
  return `<button class="theme-toggle" id="theme-toggle-btn">${nextLabel}</button>`;
}

// Delegated on document (survives every innerHTML re-render) rather than
// rewired after each render call.
document.addEventListener("click", (e) => {
  if (e.target && e.target.id === "theme-toggle-btn") {
    setTheme(getTheme() === "dark" ? "light" : "dark");
    e.target.textContent = getTheme() === "dark" ? "Light Mode" : "Dark Mode";
  }
});

initTheme();

// Transient one-shot banner shown under the Step 2 import control after an
// upload. Not part of `state` -- it's a render-only concern that should
// clear itself the next time renderStep2 runs, not persist across steps.
let lastImportNotice = null;

let state = {
  step: 1,
  targetDatabase: localStorage.getItem(TARGET_DB_STORAGE_KEY) || "CaseWorthy",
  targetDbs: null,
  modules: [],
  modulesInitializedFor: null,
  advancedMode: false,
  dialect: "SQL Server",
  dialects: null,
  sourceSystem: "",
  fields: [{ name: "", desc: "", sourceTable: "", sourceValues: "" }],
  suggestions: [],
  schema: null,
  schemaKey: null,
};

async function api(path, opts) {
  const res = await fetch(path, opts);
  return res.json();
}

const app = document.getElementById("app");

// Full welcome/help panel (below) replaces what used to be a one-line "Phase
// 0 POC" subtitle. Shown in full on Step 1 only -- that's the one place
// "Welcome!" actually makes sense, and every other step already has its own
// contextual instructions, so repeating this whole block there would just be
// noise. The data-safety line is the one thing that has to persist on every
// step regardless (see .safety-note below) -- it's a hard product boundary
// (never real client data), not just onboarding copy.
function renderHeader() {
  const meta = activeDb();
  const helpBlock = state.step === 1 ? `
    <div class="welcome-panel">
      <p>Welcome! This tool helps you figure out where your data belongs. As you migrate to ${meta.label}, it maps fields from your old source system to the right destination fields in your new one.</p>
      <h4>How It Works</h4>
      <ol>
        <li>Enter a field name from your existing source system.</li>
        <li>Review the suggested destination fields.</li>
        <li>Use the recommendations as a starting point for your ETL mapping documentation.</li>
        <li>Validate every mapping against your own organization's needs before moving forward.</li>
      </ol>
      <h4>Important Notes</h4>
      <ul>
        <li>Suggestions are based on common field-mapping patterns and may need adjustment for your organization.</li>
        <li>Only enter <strong>field names and formats</strong> here — never real client names, SSNs, or other personal data.</li>
        <li>Always verify mappings before loading data into your production environment.</li>
      </ul>
      <h4>Need Assistance?</h4>
      <p>Questions about a suggestion, an unrecognized field, or your ETL strategy in general — reach out to your Technical Consultant.</p>
    </div>
  ` : `
    <div class="safety-note">
      ⚠️ Only enter <strong>field names and formats</strong> below — never real client names, SSNs, or other personal data.
    </div>
  `;
  return `
    ${renderThemeToggle()}
    <div class="header-row">
      <div>
        <img class="brand-logo" src="${meta.logo}" alt="${meta.label}">
        <div class="eyebrow">${meta.label} • ETL Onboarding</div>
        <h1>Field Mapping Assistant</h1>
      </div>
    </div>
    ${helpBlock}
  `;
}

// Learned-mappings counter moved here deliberately: still visible on every
// step, but small and out of the way at the bottom rather than a prominent
// box next to the H1. refreshLibStat() targets the same #lib-stat id
// regardless of where it lives in the markup.
function renderFooter(extra) {
  return `
    <footer>
      ${extra || "Internal POC · CaseWorthy Technical Consulting"}
      <div class="lib-stat" id="lib-stat"><span class="num">…</span> <span class="lbl">learned mappings</span></div>
    </footer>`;
}

async function refreshLibStat() {
  const stats = await api(`/api/stats?targetDatabase=${encodeURIComponent(state.targetDatabase)}`);
  const el = document.getElementById("lib-stat");
  if (el) {
    // Names which database this count is scoped to (db.py's target_db column
    // keeps CaseWorthy and ServTracker mappings separate) -- without this label
    // switching target databases makes previously-confirmed mappings look like
    // they disappeared, when they're just filed under the other database.
    el.innerHTML = `<span class="num">${stats.total}</span> <span class="lbl">learned mapping${stats.total === 1 ? "" : "s"} · ${stats.systems} source system${stats.systems === 1 ? "" : "s"} (${dbLabel()})</span>`;
  }
}

async function ensureTargetDbs() {
  if (!state.targetDbs) {
    const res = await api("/api/target-databases");
    state.targetDbs = res.targetDatabases || [];
  }
  return state.targetDbs;
}

// Keyed on database *and* module selection, so changing modules refetches the
// scoped schema instead of silently reusing the previous scope's candidates.
async function ensureSchema() {
  const mods = effectiveModules();
  const key = `${state.targetDatabase}::${mods.slice().sort().join("|")}`;
  if (state.schemaKey !== key) {
    const q = new URLSearchParams({ targetDatabase: state.targetDatabase });
    if (mods.length) q.set("modules", mods.join(","));
    state.schema = await api(`/api/schema?${q.toString()}`);
    state.schemaKey = key;
  }
  return state.schema;
}

async function ensureDialects() {
  if (!state.dialects) {
    const res = await api("/api/dialects");
    state.dialects = res.dialects;
    if (!state.dialects.includes(state.dialect)) state.dialect = res.default;
  }
  return state.dialects;
}

// Module/tab picker, rendered for any target database that has modules --
// today, both do, for different reasons (see TARGET_DB_META in
// schema_rules.py): ServTracker uses it to narrow away real name collisions
// across program-area workbooks; CaseWorthy uses it just to let a migration
// target only the tabs it needs, defaulting to everything selected.
//
// Base modules (ServTracker only) render checked and disabled: every
// ServTracker sheet keys off ClientImportId from the client sheet, so the
// client module isn't optional. CaseWorthy has no base modules -- nothing
// is forced, nothing is required to proceed.
function renderModulePicker(meta) {
  const base = meta.baseModules || [];
  const groupWord = meta.groupNoun || "module";
  const groupWordPlural = groupWord + "s";
  const items = (meta.modules || []).map(m => {
    const locked = m.required;
    const checked = locked || state.modules.includes(m.name);
    const isSingleton = m.sheets.length === 1 && m.sheets[0] === m.name;
    const statLine = isSingleton
      ? `${m.fieldCount} fields`
      : `${m.sheets.length} ${m.sheets.length === 1 ? "sheet" : "sheets"} · ${m.fieldCount} fields`;
    return `
      <label class="module-item${locked ? " locked" : ""}">
        <input type="checkbox" class="module-cb" value="${m.name}" ${checked ? "checked" : ""} ${locked ? "disabled" : ""}>
        <span class="module-name">${m.name}${locked ? ` <em>— always included</em>` : ""}</span>
        <span class="module-meta">${statLine}</span>
      </label>`;
  }).join("");

  const selected = effectiveModules();
  const linkKey = meta.linkKey;
  const linkNote = linkKey ? `
    <div class="link-key-note">
      <strong>${linkKey.field}</strong> is how ${meta.label} links a client across sheets.
      Use the <em>same</em> value for the same client in every sheet you submit — that's what ties
      their demographics to their services. It appears on nearly every sheet by design.
    </div>` : "";

  const summary = state.modules.length === 0
    ? (base.length
        ? `${base.join(", ")} is included by default — no other ${groupWord} is required. Add more above if this customer runs them.`
        : `Nothing selected yet.`)
    : `${selected.length} ${selected.length === 1 ? groupWord : groupWordPlural} in scope${base.length ? ` (including ${base.join(", ")})` : ""}.`;

  return `
    <div class="target-db-row module-picker">
      <label>Which ${meta.label} ${groupWordPlural} are you migrating?</label>
      <div style="color:var(--surface-text-muted);font-size:12px;margin-bottom:8px;">
        ${meta.scopingReason || ""}
      </div>
      <div class="module-actions">
        <button type="button" class="ghost" id="modules-select-all">Select all</button>
        <button type="button" class="ghost" id="modules-select-none">Select none</button>
      </div>
      <div class="module-list">${items}</div>
      <div class="module-summary" id="module-summary">${summary}</div>
      ${linkNote}
    </div>`;
}

async function renderStep1() {
  await ensureTargetDbs();
  const meta = activeDb();
  const unavailable = meta.available === false;

  // Apply each database's sensible default exactly once per database
  // (tracked by modulesInitializedFor), not on every render -- otherwise a
  // customer unchecking everything on a defaultSelectAll database would just
  // get overwritten back to "all" on the next render.
  if (!unavailable && meta.hasModules && state.modulesInitializedFor !== state.targetDatabase) {
    state.modules = meta.defaultSelectAll
      ? (meta.modules || []).map(m => m.name).filter(n => !(meta.baseModules || []).includes(n))
      : [];
    state.modulesInitializedFor = state.targetDatabase;
  }

  const dbOptions = (state.targetDbs || [])
    .map(d => `<option value="${d.name}" ${state.targetDatabase === d.name ? "selected" : ""}>${d.label}</option>`)
    .join("");

  const warning = unavailable
    ? `<div class="db-warning">${meta.label}'s schema isn't loaded in this POC yet. Nothing has been guessed at in its place — a schema has to be extracted from its own validation rules first.</div>`
    : "";

  const moduleBlock = (!unavailable && meta.hasModules) ? renderModulePicker(meta) : "";

  let dialectRow = "";
  if (state.advancedMode) {
    await ensureDialects();
    const dialectOptions = state.dialects.map(d => `<option value="${d}" ${state.dialect === d ? "selected" : ""}>${d}</option>`).join("");
    dialectRow = `
      <div class="target-db-row">
        <label for="dialect">Source database SQL dialect</label>
        <select id="dialect">${dialectOptions}</select>
        <div style="color:var(--surface-text-muted);font-size:12px;margin-top:4px;">Used to generate the SQL export a technical data person runs against your source system (see Advanced options, Step 2 and the Summary step).</div>
      </div>`;
  }

  app.innerHTML = `
    ${renderHeader()}
    <div class="card">
      <h3>What System Are You Migrating From?</h3>
      <div class="target-db-row">
        <label for="target-db">Target database</label>
        <select id="target-db">${dbOptions}</select>
        ${warning}
      </div>
      ${moduleBlock}
      <label for="src-sys">Source system name</label>
      <input type="text" id="src-sys" placeholder="e.g. Bonterra Case Manager, Apricot, a homegrown Access database" value="${state.sourceSystem}">
      <div class="target-db-row" style="margin-top:14px;">
        <label style="display:flex;align-items:center;gap:8px;font-weight:600;">
          <input type="checkbox" id="advanced-toggle" ${state.advancedMode ? "checked" : ""} style="width:auto;">
          Advanced options
        </label>
        <div style="color:var(--surface-text-muted);font-size:12px;">Also collect each field's source table name, so a SQL export (per target table) can be generated for a technical data person to pull your live data.</div>
      </div>
      ${dialectRow}
      <div class="step-nav">
        <span></span>
        <button class="primary" id="next-1" ${unavailable ? "disabled" : ""}>Next: List Your Fields →</button>
      </div>
    </div>
    ${renderFooter()}
  `;
  refreshLibStat();

  // Every handler below re-renders Step 1 from `state`, which throws away
  // whatever's currently typed in #src-sys unless it's captured first --
  // this used to silently wipe the source system name on any toggle/select
  // change made after typing it in.
  function syncSourceSystem() {
    const el = document.getElementById("src-sys");
    if (el) state.sourceSystem = el.value;
  }

  document.getElementById("target-db").onchange = (e) => {
    syncSourceSystem();
    state.targetDatabase = e.target.value;
    localStorage.setItem(TARGET_DB_STORAGE_KEY, state.targetDatabase);
    // Module selections belong to a database; carrying them across would scope
    // the new one by names it doesn't have. Clearing modulesInitializedFor
    // lets the newly-selected database's own default (all-selected or
    // nothing-extra) apply fresh on the next render.
    state.modules = [];
    state.modulesInitializedFor = null;
    state.schemaKey = null;
    renderStep1();
  };
  document.querySelectorAll(".module-cb").forEach(cb => {
    cb.onchange = () => {
      syncSourceSystem();
      const picked = [...document.querySelectorAll(".module-cb")]
        .filter(c => c.checked && !c.disabled)
        .map(c => c.value);
      state.modules = picked;
      state.schemaKey = null;
      renderStep1();
    };
  });
  const selectAllBtn = document.getElementById("modules-select-all");
  if (selectAllBtn) selectAllBtn.onclick = () => {
    syncSourceSystem();
    state.modules = (meta.modules || []).map(m => m.name).filter(n => !(meta.baseModules || []).includes(n));
    state.schemaKey = null;
    renderStep1();
  };
  const selectNoneBtn = document.getElementById("modules-select-none");
  if (selectNoneBtn) selectNoneBtn.onclick = () => {
    syncSourceSystem();
    state.modules = [];
    state.schemaKey = null;
    renderStep1();
  };
  document.getElementById("advanced-toggle").onchange = (e) => {
    syncSourceSystem();
    state.advancedMode = e.target.checked;
    renderStep1();
  };
  const dialectEl = document.getElementById("dialect");
  if (dialectEl) dialectEl.onchange = (e) => { state.dialect = e.target.value; };
  document.getElementById("next-1").onclick = () => {
    if (unavailable) return;
    const val = document.getElementById("src-sys").value.trim();
    if (!val) { alert("Enter the source system name to continue."); return; }
    state.sourceSystem = val;
    state.step = 2;
    renderStep2();
  };
}

// Merges freshly-imported {name, desc, sourceTable} rows into state.fields:
// drops the pattern's own blank rows first (so an import into an untouched
// Step 2 doesn't leave an empty row mixed into real data), skips anything
// that already matches an existing field name + source table (case-
// insensitive), then leaves one trailing blank row for continued manual entry.
function mergeImportedFields(imported) {
  const merged = state.fields.filter(f => f.name.trim());
  const key = f => `${f.name.trim().toLowerCase()}::${(f.sourceTable || "").trim().toLowerCase()}`;
  const seen = new Set(merged.map(key));
  let added = 0, skipped = 0;
  for (const f of imported) {
    const k = key(f);
    if (seen.has(k)) { skipped++; continue; }
    seen.add(k);
    merged.push({ name: f.name, desc: f.desc || "", sourceTable: f.sourceTable || "", sourceValues: f.sourceValues || "" });
    added++;
  }
  merged.push({ name: "", desc: "", sourceTable: "", sourceValues: "" });
  state.fields = merged;
  return { added, skipped };
}

function renderStep2() {
  const rows = state.fields.map((f, i) => `
    <div class="field-row" data-idx="${i}">
      ${state.advancedMode ? `<input type="text" class="fsrctable" placeholder="Source table name (e.g. dbo.ClientExport)" value="${f.sourceTable || ""}">` : ""}
      <input type="text" class="fname" placeholder="Source field name (e.g. Client_DOB)" value="${f.name}">
      <input type="text" class="fdesc" placeholder="Optional: short description or format (e.g. MM/DD/YYYY, 1=Yes/2=No)" value="${f.desc}">
      ${state.advancedMode ? `<input type="text" class="fsrcvalues" placeholder="Optional: this field's known source values (e.g. M, F, U or 1=Yes, 2=No)" value="${f.sourceValues || ""}">` : ""}
      <button class="ghost remove-field">Remove</button>
    </div>
  `).join("");

  const advancedInstructions = state.advancedMode
    ? `Advanced options require table and column names, example: <strong>Client.ClientID</strong> or <strong>Client.DOB</strong>.`
    : "";
  const importFormatHint = state.advancedMode
    ? `Header cells should use that same "Table.Column" form (e.g. Client.ClientID) so we can split out the table name.`
    : `Header cells should just be the column name (e.g. ClientID).`;
  const notice = lastImportNotice
    ? `<div class="import-notice import-${lastImportNotice.kind}">${lastImportNotice.text}</div>`
    : "";
  lastImportNotice = null;

  app.innerHTML = `
    ${renderHeader()}
    <div class="card">
      <h3>List the Fields From ${state.sourceSystem}</h3>
      <div style="color:var(--surface-text-muted);font-size:13px;margin-bottom:14px;">Add each field name from your export. A short description helps but isn't required.${state.advancedMode ? ` Advanced mode is on — also enter each field's source table name so a SQL export can be generated later. ${advancedInstructions} If a field has a known, limited set of values (e.g. a code or category), list them in "known source values" so they can be matched against the target's allowed values and considered for value-mapping in the SQL export.` : ""}</div>
      <div class="import-panel">
        <div class="import-row">
          <input type="file" id="import-file" accept=".csv,.xlsx">
          <button class="secondary" id="import-btn" disabled>Import fields</button>
        </div>
        <div class="import-hint">Only the header row (column names) is read — never the data underneath it. ${importFormatHint}</div>
        <div id="import-status">${notice}</div>
      </div>
      <div class="field-row field-row-header">
        ${state.advancedMode ? `<span>Source table</span>` : ""}
        <span>Field name</span>
        <span>Description</span>
        ${state.advancedMode ? `<span>Known source values</span>` : ""}
        <button class="ghost" style="visibility:hidden;" tabindex="-1">Remove</button>
      </div>
      <div id="field-rows">${rows}</div>
      <button class="secondary" id="add-field">+ Add another field</button>
      <div class="step-nav">
        <button class="secondary" id="back-2">← Back</button>
        <button class="primary" id="next-2">Get Mapping Suggestions →</button>
      </div>
    </div>
    ${renderFooter()}
  `;
  refreshLibStat();

  function syncFieldsFromDOM() {
    const rowEls = [...document.querySelectorAll("#field-rows .field-row")];
    state.fields = rowEls.map(r => ({
      name: r.querySelector(".fname").value.trim(),
      desc: r.querySelector(".fdesc").value.trim(),
      sourceTable: state.advancedMode ? r.querySelector(".fsrctable").value.trim() : "",
      sourceValues: state.advancedMode ? r.querySelector(".fsrcvalues").value.trim() : ""
    }));
  }

  document.getElementById("add-field").onclick = () => {
    syncFieldsFromDOM();
    state.fields.push({ name: "", desc: "", sourceTable: "", sourceValues: "" });
    renderStep2();
  };
  document.querySelectorAll(".remove-field").forEach(btn => {
    btn.onclick = () => {
      syncFieldsFromDOM();
      const idx = parseInt(btn.closest(".field-row").dataset.idx, 10);
      state.fields.splice(idx, 1);
      if (state.fields.length === 0) state.fields.push({ name: "", desc: "", sourceTable: "", sourceValues: "" });
      renderStep2();
    };
  });
  document.getElementById("back-2").onclick = () => { syncFieldsFromDOM(); state.step = 1; renderStep1(); };
  document.getElementById("next-2").onclick = async () => {
    syncFieldsFromDOM();
    const valid = state.fields.filter(f => f.name);
    if (valid.length === 0) { alert("Add at least one field name."); return; }
    state.fields = valid;
    state.step = 3;
    await renderStep3();
  };

  const importFileEl = document.getElementById("import-file");
  const importBtn = document.getElementById("import-btn");
  const importStatusEl = document.getElementById("import-status");
  importFileEl.onchange = () => {
    importBtn.disabled = !importFileEl.files.length;
  };
  importBtn.onclick = async () => {
    const file = importFileEl.files[0];
    if (!file) return;
    importBtn.disabled = true;
    importBtn.textContent = "Importing…";
    importStatusEl.innerHTML = "";
    try {
      const formData = new FormData();
      formData.append("file", file);
      formData.append("advancedMode", state.advancedMode ? "true" : "false");
      const res = await fetch("/api/import-fields", { method: "POST", body: formData });
      const result = await res.json();
      if (!res.ok || result.error) throw new Error(result.error || "Import failed.");

      syncFieldsFromDOM();
      const { added, skipped } = mergeImportedFields(result.fields);
      const parts = [`Imported ${added} field${added === 1 ? "" : "s"} from ${result.sourceFile}.`];
      if (skipped) parts.push(`${skipped} duplicate${skipped === 1 ? "" : "s"} skipped.`);
      parts.push(...(result.warnings || []));
      lastImportNotice = { kind: "success", text: parts.join(" ") };
      renderStep2();
    } catch (err) {
      importStatusEl.innerHTML = `<div class="import-notice import-error">${err.message}</div>`;
      importBtn.disabled = false;
      importBtn.textContent = "Import fields";
    }
  };
}

async function renderStep3() {
  app.innerHTML = `
    ${renderHeader()}
    <div class="card">
      <h3>Mapping Suggestions</h3>
      <div class="loading">Checking the mapping library and asking Claude for suggestions on new fields…</div>
    </div>
  `;
  refreshLibStat();
  await ensureSchema();

  state.suggestions = [];
  for (const f of state.fields) {
    const sug = await api("/api/suggest", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ targetDatabase: state.targetDatabase, modules: effectiveModules(), sourceSystem: state.sourceSystem, fieldName: f.name, desc: f.desc }),
    });
    const targetMeta = state.schema.find(t => t.table === sug.table && t.field === sug.field);
    state.suggestions.push({ source: f.name, desc: f.desc, sourceTable: f.sourceTable || "", sourceValues: f.sourceValues || "", suggestion: sug, targetMeta, confirmedTable: sug.table, confirmedField: sug.field });
  }
  renderStep3Results();
}

function renderStep3Results() {
  const cards = state.suggestions.map((s, i) => {
    const conf = s.suggestion.confidence;
    const pillClass = conf === "learned" ? "learned" : conf;
    const pillLabel = conf === "learned" ? "Learned" : conf.charAt(0).toUpperCase() + conf.slice(1);
    const hasMatch = s.suggestion.table && s.suggestion.field;
    const decode = s.targetMeta && s.targetMeta.decode ? `<div class="decode">Valid values: ${s.targetMeta.decode}</div>` : "";
    const note = s.targetMeta && s.targetMeta.note ? `<div class="decode">${s.targetMeta.note}</div>` : "";
    const requiredNote = s.targetMeta && s.targetMeta.required ? `<div class="decode">This target field is <strong>required</strong> by ${dbLabel()}'s import rules.</div>` : "";
    const linkNote = s.targetMeta && s.targetMeta.linkKey
      ? `<div class="decode link-key-inline">🔑 <strong>${s.targetMeta.field}</strong> links a client across every sheet — use the same value for this client everywhere.</div>`
      : "";
    const mergeNote = s.targetMeta && s.targetMeta.mergeOnly
      ? `<div class="decode">Only needed when updating clients already in ${dbLabel()}. Leave blank for new clients.</div>`
      : "";
    // ServTracker targets are sheets the customer fills in; CaseWorthy targets
    // are tables. Display follows the schema, identity stays table::field.
    const targetName = (row) => (row && row.sheet) ? row.sheet : (row ? row.table : "");
    const shownTarget = s.targetMeta ? targetName(s.targetMeta) : s.confirmedTable;
    const options = state.schema.map(t => `<option value="${t.table}::${t.field}" ${s.confirmedTable===t.table && s.confirmedField===t.field ? "selected" : ""}>${targetName(t)} → ${t.field}${t.required ? " (required)" : ""}</option>`).join("");
    return `
      <div class="suggestion-card" data-idx="${i}">
        <div class="src">${s.source}${s.desc ? ` <span style="font-weight:400;color:var(--surface-text-muted);">— ${s.desc}</span>` : ""}</div>
        ${s.sourceValues ? `<div class="decode">Known source values: ${s.sourceValues}</div>` : ""}
        ${hasMatch ? `<div class="target">${shownTarget} → ${s.confirmedField}</div>` : `<div class="target" style="color:var(--cw-orange);">No confident match</div>`}
        <span class="pill ${pillClass}">${pillLabel}</span>
        <div class="reason" style="margin-top:6px;">${s.suggestion.reasoning || ""}</div>
        ${decode}${note}${requiredNote}${linkNote}${mergeNote}
        <div class="actions">
          <button class="secondary confirm-btn">${s.confirmed ? "Confirmed ✓" : "Confirm this mapping"}</button>
          <button class="ghost override-btn">Choose different field</button>
          <button class="ghost flag-btn" style="border-color:var(--surface-text-muted);color:var(--surface-text-muted);">Flag for consultant review</button>
        </div>
        <div class="override-row">
          <select class="override-select">${options}</select>
          <button class="primary override-save">Use this</button>
        </div>
      </div>
    `;
  }).join("");

  app.innerHTML = `
    ${renderHeader()}
    <div class="card">
      <h3>Mapping Suggestions for ${state.sourceSystem}</h3>
      <div style="color:var(--surface-text-muted);font-size:13px;margin-bottom:14px;">Confirm each mapping, pick a different target field, or flag anything ambiguous for manual review. Confirmed mappings are saved so the next customer on ${state.sourceSystem} sees them instantly.</div>
      ${cards || '<div class="empty">No fields to show.</div>'}
      <div class="step-nav">
        <button class="secondary" id="back-3">← Back</button>
        <button class="primary" id="next-3">Go to Summary →</button>
      </div>
    </div>
    ${renderFooter()}
  `;
  refreshLibStat();

  document.querySelectorAll(".suggestion-card").forEach(card => {
    const idx = parseInt(card.dataset.idx, 10);
    const s = state.suggestions[idx];
    card.querySelector(".confirm-btn").onclick = async () => {
      if (!s.confirmedTable || !s.confirmedField) { alert("Choose a target field first."); return; }
      await api("/api/confirm", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ targetDatabase: state.targetDatabase, sourceSystem: state.sourceSystem, fieldName: s.source, table: s.confirmedTable, field: s.confirmedField, desc: s.desc || "" }),
      });
      s.confirmed = true;
      s.flagged = false;
      renderStep3Results();
    };
    card.querySelector(".override-btn").onclick = () => {
      card.querySelector(".override-row").classList.toggle("show");
    };
    card.querySelector(".override-save").onclick = () => {
      const val = card.querySelector(".override-select").value;
      const [table, field] = val.split("::");
      s.confirmedTable = table; s.confirmedField = field;
      s.suggestion = { table, field, confidence: "medium", reasoning: "Manually selected by consultant." };
      s.targetMeta = state.schema.find(t => t.table === table && t.field === field);
      s.confirmed = false;
      s.valueMap = ""; s.valueMapDraft = null; // a different target field invalidates any prior value match
      renderStep3Results();
    };
    card.querySelector(".flag-btn").onclick = () => {
      s.flagged = true;
      s.confirmed = false;
      s.confirmedTable = null; s.confirmedField = null;
      s.valueMap = ""; s.valueMapDraft = null;
      renderStep3Results();
    };
  });
  document.getElementById("back-3").onclick = () => { state.step = 2; renderStep2(); };
  document.getElementById("next-3").onclick = () => {
    if (fieldsNeedingValueMatch().length) {
      state.step = 3.5;
      renderValueMatchStep();
    } else {
      state.step = 4;
      renderStep4();
    }
  };
}

// Rule-engine results come back keyed by target *table*. For ServTracker the
// customer only ever sees sheet names, so translate for display -- otherwise the
// warnings name `ClientCongregateImport` while the cards above say
// `Congregate Meal Schedule`.
function tableDisplayName(table) {
  const row = (state.schema || []).find(r => r.table === table && r.sheet);
  return row ? row.sheet : table;
}

// Mirrors schema_rules.parse_decode exactly -- a bare entry with no "=" is
// dropped, not self-paired. Only used for a target's own `decode` string,
// which is always properly "code=label" pairs by the time it's in the
// schema (see reference/SCHEMA_FORMAT.md); kept separate from
// parseValueListJs below rather than reusing it, so this side stays in sync
// with parse_decode's semantics specifically, not parse_value_list's.
function parseDecodeJs(str) {
  const pairs = [];
  for (const part of (str || "").split(",")) {
    const p = part.trim();
    const eq = p.indexOf("=");
    if (eq !== -1) pairs.push([p.slice(0, eq).trim(), p.slice(eq + 1).trim()]);
  }
  return pairs;
}

// Mirrors schema_rules.parse_value_list exactly -- a bare entry self-pairs
// (code === label) instead of being dropped, since it's the customer
// directly naming one of their field's own values. Used for the customer's
// own sourceValues/valueMap strings, both of which use this more tolerant
// parsing.
function parseValueListJs(str) {
  const pairs = [];
  for (const part of (str || "").split(",")) {
    const p = part.trim();
    if (!p) continue;
    const eq = p.indexOf("=");
    if (eq !== -1) pairs.push([p.slice(0, eq).trim(), p.slice(eq + 1).trim()]);
    else pairs.push([p, p]);
  }
  return pairs;
}

// Mirrors schema_rules.target_value_pairs: decodePairs (CaseWorthy List
// fields resolved against the ListItem registry -- real structured
// [code,label] pairs, since some labels contain their own commas and would
// corrupt decode's comma-split parsing) wins first, then decode
// (CaseWorthy-style hand-typed "code=label" string), then decodeValues
// (ServTracker-style bare labels, self-paired) -- same fallback order, same
// reasoning (see that function's own docstring).
function targetPairsJs(meta) {
  if (!meta) return [];
  if (meta.decodePairs && meta.decodePairs.length) return meta.decodePairs;
  if (meta.decode) {
    const pairs = parseDecodeJs(meta.decode);
    if (pairs.length) return pairs;
  }
  if (meta.decodeValues && meta.decodeValues.length) return meta.decodeValues.map(v => [v, v]);
  return [];
}

// Gate for the value-matching step (renderValueMatchStep): only fields the
// customer both (a) gave a known-source-values list for, and (b) mapped to
// a target field that actually has approved values to match against. A
// flagged-for-review field is deferred to a consultant entirely, so it's
// excluded here too -- forcing a value match on a mapping nobody's
// confirmed the target field for yet would be asking for a decision that
// might get thrown away.
function fieldsNeedingValueMatch() {
  return state.suggestions.filter(s =>
    !s.flagged && s.confirmedTable && s.confirmedField && s.sourceValues &&
    targetPairsJs(s.targetMeta).length > 0
  );
}

// Inserted between Mapping Suggestions and Summary (Advanced mode only,
// and only when fieldsNeedingValueMatch() is non-empty -- see next-3's
// handler). Every field mapped to a target with approved values, where the
// customer already listed their own source values, gets a required
// dropdown per distinct source value: no automatic guessing, the customer
// picks the match themselves, and that becomes the CASE WHEN in the SQL
// export outright (transform_draft.py's confirmed_value_map, highest
// priority there) rather than something to double-check.
function renderValueMatchStep() {
  const fields = fieldsNeedingValueMatch();

  const cards = fields.map((s, i) => {
    const targetPairs = targetPairsJs(s.targetMeta);
    const targetIsSelfPaired = targetPairs.every(([c, l]) => c === l);
    const targetOptionsHtml = (preselect) => targetPairs.map(([code, label]) =>
      `<option value="${code}" ${preselect === code ? "selected" : ""}>${targetIsSelfPaired ? label : `${code} = ${label}`}</option>`
    ).join("");

    // Priority for the pre-filled selection: this render pass's own edits >
    // a previously-confirmed value map for this exact source field (from
    // /api/suggest's learned/shared-learned paths) > an exact label match
    // (same reconciliation transform_draft.js would do automatically) >
    // unselected, forcing an explicit choice.
    const draft = s.valueMapDraft || Object.fromEntries(parseValueListJs(s.suggestion.valueMap || ""));
    const targetByLabel = Object.fromEntries(targetPairs.map(([c, l]) => [l.trim().toLowerCase(), c]));

    const srcPairs = parseValueListJs(s.sourceValues);
    const seen = new Set();
    const rows = srcPairs.filter(([code]) => {
      if (seen.has(code)) return false;
      seen.add(code);
      return true;
    }).map(([code, label]) => {
      const preselect = draft[code] !== undefined ? draft[code] : (targetByLabel[label.trim().toLowerCase()] || "");
      return `
        <div class="value-match-row" data-code="${code}">
          <span class="value-match-src">${label !== code ? `${code} (${label})` : code}</span>
          <span class="value-match-arrow">→</span>
          <select class="value-match-select">
            <option value="" disabled ${preselect === "" ? "selected" : ""}>Choose a match…</option>
            <option value="__NULL__" ${preselect === "__NULL__" ? "selected" : ""}>Leave unmapped (NULL)</option>
            ${targetOptionsHtml(preselect)}
          </select>
        </div>`;
    }).join("");

    const targetName = s.targetMeta.sheet || s.targetMeta.table;
    return `
      <div class="suggestion-card value-match-card" data-idx="${i}">
        <div class="src">${s.source} <span style="font-weight:400;color:var(--surface-text-muted);">→ ${targetName} → ${s.confirmedField}</span></div>
        <div class="decode">Approved values: ${targetIsSelfPaired ? targetPairs.map(p => p[1]).join(", ") : targetPairs.map(([c, l]) => `${c}=${l}`).join(", ")}</div>
        <div class="value-match-rows">${rows}</div>
      </div>`;
  }).join("");

  app.innerHTML = `
    ${renderHeader()}
    <div class="card">
      <h3>Match Your Values to ${dbLabel()}'s Approved Values</h3>
      <div style="color:var(--surface-text-muted);font-size:13px;margin-bottom:14px;">These fields have a limited set of approved values in ${dbLabel()}. Match each of your own listed source values to the one it corresponds to -- this becomes the value-conversion logic in your SQL export. Choose "Leave unmapped (NULL)" for a value with no real equivalent.</div>
      ${cards || '<div class="empty">Nothing to match.</div>'}
      <div class="step-nav">
        <button class="secondary" id="back-3b">← Back</button>
        <button class="primary" id="continue-3b" disabled>Continue to Summary →</button>
      </div>
    </div>
    ${renderFooter()}
  `;
  refreshLibStat();

  function updateContinueState() {
    const allChosen = [...document.querySelectorAll(".value-match-select")].every(sel => sel.value !== "");
    document.getElementById("continue-3b").disabled = !allChosen;
  }
  updateContinueState();

  document.querySelectorAll(".value-match-card").forEach(card => {
    const idx = parseInt(card.dataset.idx, 10);
    const s = fields[idx];
    s.valueMapDraft = s.valueMapDraft || {};
    card.querySelectorAll(".value-match-row").forEach(row => {
      const code = row.dataset.code;
      const select = row.querySelector(".value-match-select");
      select.onchange = () => {
        s.valueMapDraft[code] = select.value;
        updateContinueState();
      };
      // Selects rendered with a pre-selected option don't fire onchange on
      // their own -- seed the draft from what's actually showing so a
      // field the customer never touches still serializes correctly below.
      if (select.value) s.valueMapDraft[code] = select.value;
    });
  });

  document.getElementById("back-3b").onclick = () => { state.step = 3; renderStep3Results(); };
  document.getElementById("continue-3b").onclick = async () => {
    for (const s of fields) {
      const mapping = s.valueMapDraft || {};
      s.valueMap = Object.entries(mapping)
        .filter(([, tgt]) => tgt && tgt !== "__NULL__")
        .map(([code, tgt]) => `${code}=${tgt}`)
        .join(",");
      await api("/api/confirm-value-mapping", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          targetDatabase: state.targetDatabase, sourceSystem: state.sourceSystem, fieldName: s.source,
          table: s.confirmedTable, field: s.confirmedField, valueMap: s.valueMap, desc: s.desc || "",
        }),
      });
    }
    state.step = 4;
    renderStep4();
  };
}

function renderReadinessPanel(check) {
  const groups = [];
  if (check.requiredMissing.length) {
    groups.push(`
      <div class="readiness-group">
        <h4>Required target fields with no mapping yet</h4>
        <ul>${check.requiredMissing.map(r => `<li>${tableDisplayName(r.table)} → ${r.field}</li>`).join("")}</ul>
      </div>`);
  }
  if (check.fkWarnings.length) {
    groups.push(`
      <div class="readiness-group">
        <h4>Missing dependent tables</h4>
        <ul>${check.fkWarnings.map(w => `<li>${tableDisplayName(w.table)}.${w.field} references <strong>${tableDisplayName(w.dependsOn)}</strong>, but you haven't mapped any ${tableDisplayName(w.dependsOn)} fields yet.</li>`).join("")}</ul>
      </div>`);
  }
  if (check.duplicates.length) {
    groups.push(`
      <div class="readiness-group">
        <h4>Two source fields mapped to the same target</h4>
        <ul>${check.duplicates.map(d => `<li>${tableDisplayName(d.table)} → ${d.field} claimed by: ${d.sourceFields.join(", ")}</li>`).join("")}</ul>
      </div>`);
  }
  if (check.formatHints.length) {
    groups.push(`
      <div class="readiness-group">
        <h4>Possible value/format mismatches</h4>
        <ul>${check.formatHints.map(h => `<li>${h.sourceField}: ${h.hint}</li>`).join("")}</ul>
      </div>`);
  }
  if (!groups.length) {
    return `<div class="readiness-panel"><div class="readiness-clean">✓ No rule violations detected against ${dbLabel()}'s import requirements.</div></div>`;
  }
  return `<div class="readiness-panel">${groups.join("")}</div>`;
}

function renderSqlExportSection(exportResult) {
  if (!exportResult) return "";
  const headerBlock = exportResult.header ? `
    <pre style="background:var(--surface-page);border:1px solid var(--surface-border);color:var(--surface-text);border-radius:6px;padding:12px;font-size:12px;overflow-x:auto;white-space:pre-wrap;margin-bottom:14px;">${exportResult.header.replace(/</g, "&lt;")}</pre>` : "";
  const blocks = exportResult.statements.map(s => `
    <div style="margin-bottom:14px;">
      <div style="font-family:var(--font-heading);font-weight:600;color:var(--surface-heading);margin-bottom:4px;">${s.targetTable} <span style="color:var(--surface-text-muted);font-weight:400;">(source: ${s.sourceTable})</span></div>
      <pre style="background:var(--surface-page);border:1px solid var(--surface-border);color:var(--surface-text);border-radius:6px;padding:12px;font-size:12px;overflow-x:auto;white-space:pre-wrap;">${s.sql.replace(/</g, "&lt;")}</pre>
    </div>`).join("");

  const multiSource = exportResult.multiSourceTables.length ? `
    <div class="db-warning">
      <strong>These target tables are split across more than one source table</strong> — no JOIN is generated, so you'll get one SELECT per source table below and need to merge the results yourself:
      <ul style="margin:6px 0 0 0;">${exportResult.multiSourceTables.map(m => `<li>${m.targetTable}: ${m.sourceTables.join(", ")}</li>`).join("")}</ul>
    </div>` : "";

  return `
    <div class="card">
      <h3>SQL Export (${state.dialect})</h3>
      <div style="color:var(--surface-text-muted);font-size:13px;margin-bottom:14px;">One SELECT statement per target table per source table, aliased to match ${dbLabel()}'s field names — for a technical data person to run against your source system. This does not transform values for you; the header below lists everything still worth checking before running it.</div>
      ${headerBlock}
      ${multiSource}
      ${blocks || '<div class="empty">No SQL to generate yet — confirm mappings with a source table name in Step 2.</div>'}
      <div class="step-nav">
        <span></span>
        <button class="primary" id="download-sql-btn" ${exportResult.statements.length ? "" : "disabled"}>Download SQL (.sql)</button>
      </div>
    </div>`;
}

async function renderStep4() {
  app.innerHTML = `
    ${renderHeader()}
    <div class="card">
      <h3>Summary — ${state.sourceSystem}</h3>
      <div class="loading">Checking mappings against ${dbLabel()}'s import rules…</div>
    </div>
  `;
  refreshLibStat();

  const mappings = state.suggestions.map(s => ({
    sourceField: s.source, desc: s.desc, sourceTable: s.sourceTable || "", sourceValues: s.sourceValues || "",
    valueMap: s.valueMap || "", table: s.confirmedTable, field: s.confirmedField, flagged: !!s.flagged,
  }));
  const check = await api("/api/rulecheck", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ targetDatabase: state.targetDatabase, modules: effectiveModules(), mappings }),
  });

  let exportResult = null;
  if (state.advancedMode) {
    exportResult = await api("/api/sql-export", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ targetDatabase: state.targetDatabase, modules: effectiveModules(), dialect: state.dialect, sourceSystem: state.sourceSystem, mappings }),
    });
  }

  const rows = state.suggestions.map(s => {
    const status = s.flagged ? "Flagged for review" : (s.confirmed ? "Confirmed" : (s.confirmedTable ? "Suggested (not confirmed)" : "Unmapped"));
    const target = s.confirmedTable ? `${tableDisplayName(s.confirmedTable)} → ${s.confirmedField}` : "—";
    const rowClass = s.flagged || (!s.confirmedTable && !s.flagged) ? "flagged-row" : "";
    return `<tr class="${rowClass}"><td>${s.source}</td><td>${target}</td><td>${status}</td></tr>`;
  }).join("");

  const mods = effectiveModules();
  const summaryLines = [`ETL Field Mapping — Target Database: ${dbLabel()} — Source: ${state.sourceSystem}`]
    .concat(mods.length ? [`Modules in scope: ${mods.join(", ")}`] : []).concat([""]).concat(
    state.suggestions.map(s => `${s.source} -> ${s.confirmedTable ? tableDisplayName(s.confirmedTable) + "." + s.confirmedField : "UNMAPPED"} [${s.flagged ? "FLAGGED" : (s.confirmed ? "CONFIRMED" : "SUGGESTED")}]`)
  );
  summaryLines.push("", "-- Import readiness --");
  if (check.requiredMissing.length) summaryLines.push("Required fields with no mapping: " + check.requiredMissing.map(r => `${r.table}.${r.field}`).join(", "));
  if (check.fkWarnings.length) summaryLines.push("Missing dependent tables: " + check.fkWarnings.map(w => `${w.table} needs ${w.dependsOn}`).join(", "));
  if (check.duplicates.length) summaryLines.push("Duplicate target mappings: " + check.duplicates.map(d => `${d.table}.${d.field}`).join(", "));
  if (check.formatHints.length) summaryLines.push("Possible value/format mismatches: " + check.formatHints.map(h => h.sourceField).join(", "));
  if (!check.requiredMissing.length && !check.fkWarnings.length && !check.duplicates.length && !check.formatHints.length) {
    summaryLines.push("No rule violations detected.");
  }
  const summaryText = summaryLines.join("\n");

  app.innerHTML = `
    ${renderHeader()}
    <div class="card">
      <h3>Summary — ${state.sourceSystem}</h3>
      ${renderReadinessPanel(check)}
      <table class="summary">
        <thead><tr><th>Your field</th><th>${dbLabel()} target</th><th>Status</th></tr></thead>
        <tbody>${rows}</tbody>
      </table>
      <div class="step-nav">
        <button class="secondary" id="back-4">← Back to Mappings</button>
        <button class="primary" id="download-btn">Download Summary (.txt)</button>
      </div>
    </div>
    ${renderSqlExportSection(exportResult)}
    ${renderFooter("Internal POC · CaseWorthy Technical Consulting — not for use with real client data")}
  `;
  refreshLibStat();
  document.getElementById("back-4").onclick = () => { state.step = 3; renderStep3Results(); };
  document.getElementById("download-btn").onclick = () => {
    const blob = new Blob([summaryText], { type: "text/plain" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url; a.download = `${state.sourceSystem.replace(/[^a-z0-9]+/gi, "_")}_field_mapping.txt`;
    a.click();
    URL.revokeObjectURL(url);
  };
  const downloadSqlBtn = document.getElementById("download-sql-btn");
  if (downloadSqlBtn) {
    downloadSqlBtn.onclick = () => {
      const sqlText = [exportResult.header, ...exportResult.statements.map(s => s.sql)].filter(Boolean).join("\n\n");
      const blob = new Blob([sqlText], { type: "text/plain" });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url; a.download = `${state.sourceSystem.replace(/[^a-z0-9]+/gi, "_")}_export.sql`;
      a.click();
      URL.revokeObjectURL(url);
    };
  }
}

renderStep1();
