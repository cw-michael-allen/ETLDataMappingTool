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

let state = {
  step: 1,
  targetDatabase: "CaseWorthy",
  targetDbs: null,
  modules: [],
  advancedMode: false,
  dialect: "SQL Server",
  dialects: null,
  sourceSystem: "",
  fields: [{ name: "", desc: "", sourceTable: "" }],
  suggestions: [],
  schema: null,
  schemaKey: null,
};

async function api(path, opts) {
  const res = await fetch(path, opts);
  return res.json();
}

const app = document.getElementById("app");

function renderHeader() {
  const meta = activeDb();
  return `
    ${renderThemeToggle()}
    <div class="header-row">
      <div>
        <img class="brand-logo" src="${meta.logo}" alt="${meta.label}">
        <div class="eyebrow">${meta.label} • ETL Onboarding</div>
        <h1>Field Mapping Assistant</h1>
        <div style="color:var(--surface-text-muted);font-size:13px;">Phase 0 POC — tells you where each of your fields lives in ${meta.label} today, and flags mappings that would break ${meta.label}'s import rules.</div>
      </div>
      <div class="lib-stat" id="lib-stat">
        <div class="num">…</div>
        <div class="lbl">Learned mappings</div>
      </div>
    </div>
    <div class="safety-note">
      ⚠️ Local POC. Only enter <strong>field names and formats</strong> below — never real client names, SSNs, or other personal data.
    </div>
  `;
}

async function refreshLibStat() {
  const stats = await api(`/api/stats?targetDatabase=${encodeURIComponent(state.targetDatabase)}`);
  const el = document.getElementById("lib-stat");
  if (el) {
    el.innerHTML = `<div class="num">${stats.total}</div><div class="lbl">Learned mappings · ${stats.systems} source system${stats.systems === 1 ? "" : "s"}</div>`;
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

// Module picker, rendered only for a target database that actually has modules
// (ServTracker ships as separate program-area workbooks; CaseWorthy is one
// staging workbook and never shows this).
//
// Base modules render checked and disabled: every ServTracker sheet keys off
// ClientImportId from the client sheet, so the client module isn't optional.
// Scoping matters for suggestion quality -- unscoped, a field named `Site` or
// `StartDate` ties across six sheets and can't reach high confidence.
function renderModulePicker(meta) {
  const base = meta.baseModules || [];
  const items = (meta.modules || []).map(m => {
    const locked = m.required;
    const checked = locked || state.modules.includes(m.name);
    const sheetWord = m.sheets.length === 1 ? "sheet" : "sheets";
    return `
      <label class="module-item${locked ? " locked" : ""}">
        <input type="checkbox" class="module-cb" value="${m.name}" ${checked ? "checked" : ""} ${locked ? "disabled" : ""}>
        <span class="module-name">${m.name}${locked ? ` <em>— always included</em>` : ""}</span>
        <span class="module-meta">${m.sheets.length} ${sheetWord} · ${m.fieldCount} fields</span>
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

  return `
    <div class="target-db-row module-picker">
      <label>Which ${meta.label} modules are you migrating?</label>
      <div style="color:var(--surface-text-muted);font-size:12px;margin-bottom:8px;">
        Pick only what this customer actually runs. ${meta.label} has ${(meta.modules || []).length} modules
        across ${meta.fieldCount} fields — narrowing them makes the field suggestions far more accurate,
        because the same column name (<code>Site</code>, <code>StartDate</code>, <code>Funding</code>)
        appears on many sheets.
      </div>
      <div class="module-list">${items}</div>
      <div class="module-summary" id="module-summary">
        ${state.modules.length === 0
          ? `<span class="module-warn">Select at least one module to continue.</span>`
          : `${selected.length} module${selected.length === 1 ? "" : "s"} in scope${base.length ? ` (including ${base.join(", ")})` : ""}.`}
      </div>
      ${linkNote}
    </div>`;
}

async function renderStep1() {
  await ensureTargetDbs();
  const meta = activeDb();
  const dbOptions = (state.targetDbs || [])
    .map(d => `<option value="${d.name}" ${state.targetDatabase === d.name ? "selected" : ""}>${d.label}</option>`)
    .join("");

  const unavailable = meta.available === false;
  const warning = unavailable
    ? `<div class="db-warning">${meta.label}'s schema isn't loaded in this POC yet. Nothing has been guessed at in its place — a schema has to be extracted from its own validation rules first.</div>`
    : "";

  const moduleBlock = (!unavailable && meta.hasModules) ? renderModulePicker(meta) : "";
  const needsModules = !unavailable && meta.hasModules && state.modules.length === 0;

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
        <button class="primary" id="next-1" ${unavailable || needsModules ? "disabled" : ""}>Next: List Your Fields →</button>
      </div>
    </div>
    <footer>Internal POC · CaseWorthy Technical Consulting</footer>
  `;
  refreshLibStat();

  document.getElementById("target-db").onchange = (e) => {
    state.targetDatabase = e.target.value;
    // Module selections belong to a database; carrying them across would scope
    // the new one by names it doesn't have.
    state.modules = [];
    state.schemaKey = null;
    renderStep1();
  };
  document.querySelectorAll(".module-cb").forEach(cb => {
    cb.onchange = () => {
      const picked = [...document.querySelectorAll(".module-cb")]
        .filter(c => c.checked && !c.disabled)
        .map(c => c.value);
      state.modules = picked;
      state.schemaKey = null;
      renderStep1();
    };
  });
  document.getElementById("advanced-toggle").onchange = (e) => {
    state.advancedMode = e.target.checked;
    renderStep1();
  };
  const dialectEl = document.getElementById("dialect");
  if (dialectEl) dialectEl.onchange = (e) => { state.dialect = e.target.value; };
  document.getElementById("next-1").onclick = () => {
    if (unavailable || needsModules) return;
    const val = document.getElementById("src-sys").value.trim();
    if (!val) { alert("Enter the source system name to continue."); return; }
    state.sourceSystem = val;
    state.step = 2;
    renderStep2();
  };
}

function renderStep2() {
  const rows = state.fields.map((f, i) => `
    <div class="field-row" data-idx="${i}">
      ${state.advancedMode ? `<input type="text" class="fsrctable" placeholder="Source table name (e.g. dbo.ClientExport)" value="${f.sourceTable || ""}">` : ""}
      <input type="text" class="fname" placeholder="Source field name (e.g. Client_DOB)" value="${f.name}">
      <input type="text" class="fdesc" placeholder="Optional: short description or format (e.g. MM/DD/YYYY, 1=Yes/2=No)" value="${f.desc}">
      <button class="ghost remove-field">Remove</button>
    </div>
  `).join("");

  app.innerHTML = `
    ${renderHeader()}
    <div class="card">
      <h3>List the Fields From ${state.sourceSystem}</h3>
      <div style="color:var(--surface-text-muted);font-size:13px;margin-bottom:14px;">Add each field name from your export. A short description helps but isn't required.${state.advancedMode ? " Advanced mode is on — also enter each field's source table name so a SQL export can be generated later." : ""}</div>
      <div id="field-rows">${rows}</div>
      <button class="secondary" id="add-field">+ Add another field</button>
      <div class="step-nav">
        <button class="secondary" id="back-2">← Back</button>
        <button class="primary" id="next-2">Get Mapping Suggestions →</button>
      </div>
    </div>
    <footer>Internal POC · CaseWorthy Technical Consulting</footer>
  `;
  refreshLibStat();

  function syncFieldsFromDOM() {
    const rowEls = [...document.querySelectorAll("#field-rows .field-row")];
    state.fields = rowEls.map(r => ({
      name: r.querySelector(".fname").value.trim(),
      desc: r.querySelector(".fdesc").value.trim(),
      sourceTable: state.advancedMode ? r.querySelector(".fsrctable").value.trim() : ""
    }));
  }

  document.getElementById("add-field").onclick = () => {
    syncFieldsFromDOM();
    state.fields.push({ name: "", desc: "", sourceTable: "" });
    renderStep2();
  };
  document.querySelectorAll(".remove-field").forEach(btn => {
    btn.onclick = () => {
      syncFieldsFromDOM();
      const idx = parseInt(btn.closest(".field-row").dataset.idx, 10);
      state.fields.splice(idx, 1);
      if (state.fields.length === 0) state.fields.push({ name: "", desc: "", sourceTable: "" });
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
    state.suggestions.push({ source: f.name, desc: f.desc, sourceTable: f.sourceTable || "", suggestion: sug, targetMeta, confirmedTable: sug.table, confirmedField: sug.field });
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
    <footer>Internal POC · CaseWorthy Technical Consulting</footer>
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
        body: JSON.stringify({ targetDatabase: state.targetDatabase, sourceSystem: state.sourceSystem, fieldName: s.source, table: s.confirmedTable, field: s.confirmedField }),
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
      renderStep3Results();
    };
    card.querySelector(".flag-btn").onclick = () => {
      s.flagged = true;
      s.confirmed = false;
      s.confirmedTable = null; s.confirmedField = null;
      renderStep3Results();
    };
  });
  document.getElementById("back-3").onclick = () => { state.step = 2; renderStep2(); };
  document.getElementById("next-3").onclick = () => { state.step = 4; renderStep4(); };
}

// Rule-engine results come back keyed by target *table*. For ServTracker the
// customer only ever sees sheet names, so translate for display -- otherwise the
// warnings name `ClientCongregateImport` while the cards above say
// `Congregate Meal Schedule`.
function tableDisplayName(table) {
  const row = (state.schema || []).find(r => r.table === table && r.sheet);
  return row ? row.sheet : table;
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

  const skipped = exportResult.skipped.length ? `
    <div style="color:var(--surface-text-muted);font-size:12px;margin-top:8px;">${exportResult.skipped.length} field(s) excluded from the SQL export (${[...new Set(exportResult.skipped.map(s => s.reason))].join("; ")}).</div>` : "";

  return `
    <div class="card">
      <h3>SQL Export (${state.dialect})</h3>
      <div style="color:var(--surface-text-muted);font-size:13px;margin-bottom:14px;">One SELECT statement per target table per source table, aliased to match ${dbLabel()}'s field names — for a technical data person to run against your source system. Comments call out required/decode constraints to double-check; this does not transform values for you.</div>
      ${multiSource}
      ${blocks || '<div class="empty">No SQL to generate yet — confirm mappings with a source table name in Step 2.</div>'}
      ${skipped}
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
    sourceField: s.source, desc: s.desc, sourceTable: s.sourceTable || "", table: s.confirmedTable, field: s.confirmedField,
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
      body: JSON.stringify({ targetDatabase: state.targetDatabase, modules: effectiveModules(), dialect: state.dialect, mappings }),
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
    <footer>Internal POC · CaseWorthy Technical Consulting — not for use with real client data</footer>
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
      const sqlText = exportResult.statements.map(s => s.sql).join("\n\n");
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
