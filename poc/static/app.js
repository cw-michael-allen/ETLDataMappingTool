// Target-database metadata comes from /api/target-databases, not a hardcoded
// map. Availability used to be `targetDatabase !== "CaseWorthy"`, which meant
// adding a schema file could never actually enable a database in the UI. The
// server now reports whether a schema loaded, plus each database's modules.
// This literal is only a fallback for the first paint, before the fetch lands.
const FALLBACK_DB_META = {
  CaseWorthy: { label: "CaseWorthy", logo: "/assets/logos/caseworthy-corporate.png" },
  ServTracker: { label: "ServTracker", logo: "/assets/logos/servtracker.png" },
};

// "Create Template" is a document generator (upload a CaseWorthy Form XML
// export, get back the Field Definition + Staging Excel sheets for that
// custom form) -- deliberately NOT a schema_rules.TARGET_DATABASES entry,
// since it has no schema to map against and doesn't feed the mapping flow
// (Michael's call, 2026-08-11: keep it decoupled). It only shares the
// target-database <select> for discoverability. See form_xml.py for why
// only a structural XML preview exists so far, not real field extraction.
const CREATE_TEMPLATE_DB = "__create_template__";

function escapeHtml(str) {
  return String(str == null ? "" : str).replace(/[&<>"']/g, ch => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
  }[ch]));
}

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

// CREATE_TEMPLATE_DB is a transient mode, never a "last used database" worth
// reopening into -- unlike CaseWorthy/ServTracker, landing back on the
// upload screen on every fresh page load isn't what "remember my last
// database" was meant to do. Guards against both never persisting it going
// forward (see the target-db onchange handler below) and any stale value a
// browser already has stored from before this fix existed.
const _storedTargetDb = localStorage.getItem(TARGET_DB_STORAGE_KEY);

let state = {
  step: 1,
  targetDatabase: (_storedTargetDb && _storedTargetDb !== CREATE_TEMPLATE_DB) ? _storedTargetDb : "CaseWorthy",
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
  // Live Migration Readiness summary for the Mapping Suggestions page (Step
  // 3) -- null until the first fetch resolves, then refreshed after every
  // confirmed mapping so the panel reflects db.py's real state without a
  // manual trip to the full readiness page. Reset per source-system/target-
  // database switch the same way suggestions/schema already are.
  readinessMini: null,
  // "Create Template" mode's own state -- separate from everything above
  // since it isn't part of the mapping wizard at all. selections mirrors
  // result.formTemplates 1:1 (array of Set<row index>, one per form) once a
  // parse succeeds -- see renderCreateTemplateStep's parse handler.
  createTemplate: { parsing: false, error: null, result: null, file: null, selections: null },
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
  const isCreateTemplate = state.targetDatabase === CREATE_TEMPLATE_DB;
  const helpBlock = isCreateTemplate ? `
    <div class="welcome-panel">
      <p>Upload a CaseWorthy Form XML export (e.g. a custom Assessment or Entity form like WFDEmployment) to preview its structure before it becomes a Field Definition sheet and a Staging Excel template sheet.</p>
      <h4>Important Notes</h4>
      <ul>
        <li>This only reads form <strong>structure</strong> (field names, types, list IDs) — it never ingests real client data, and a form definition export shouldn't contain any.</li>
        <li>This preview is the first step of this feature — turning it into the two Excel deliverables still needs to be built.</li>
      </ul>
    </div>
  ` : state.step === 1 ? `
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
        <div class="eyebrow">${isCreateTemplate ? "CaseWorthy • Create Template" : `${meta.label} • ETL Onboarding`}</div>
        <h1>${isCreateTemplate ? "Create Template" : "Field Mapping Assistant"}</h1>
      </div>
    </div>
    ${helpBlock}
  `;
}

// Learned-mappings counter moved here deliberately: still visible on every
// step, but small and out of the way at the bottom rather than a prominent
// box next to the H1. refreshLibStat() targets the same #lib-stat id
// regardless of where it lives in the markup.
function renderFooter(extra, showLibStat = true) {
  const libStat = showLibStat
    ? `<div class="lib-stat" id="lib-stat"><span class="num">…</span> <span class="lbl">learned mappings</span></div>`
    : "";
  return `
    <footer>
      ${extra || "Internal POC · CaseWorthy Technical Consulting"}
      ${libStat}
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
  if (state.targetDatabase === CREATE_TEMPLATE_DB) return renderCreateTemplateStep();
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
    .join("")
    // Not one of the schema-backed databases above -- see CREATE_TEMPLATE_DB's
    // own comment for why this is a separate, decoupled mode rather than a
    // schema_rules.TARGET_DATABASES entry.
    + `<option value="${CREATE_TEMPLATE_DB}">+ Create Template (CaseWorthy)</option>`;

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
      <label for="src-sys">Source system name</label>
      <input type="text" id="src-sys" placeholder="e.g. Bonterra Case Manager, Apricot, a homegrown Access database" value="${escapeHtml(state.sourceSystem)}">
      ${!unavailable ? `<div style="margin-top:6px;"><button type="button" class="ghost" id="view-readiness-link">View Migration Readiness →</button></div>` : ""}
      ${moduleBlock}
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
    // Create Template is a transient mode, not a "last used database" worth
    // reopening into on the next visit -- see the top-of-file comment by
    // _storedTargetDb for why this is never written to storage.
    if (state.targetDatabase !== CREATE_TEMPLATE_DB) {
      localStorage.setItem(TARGET_DB_STORAGE_KEY, state.targetDatabase);
    }
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
  // Saving migration_scope is a deliberately explicit act (the "Save
  // current module scope" button inside the Readiness view itself), never
  // a silent side effect of navigating Step 1 -- CaseWorthy's default is
  // every module selected, so auto-saving here on "Next" or on opening
  // Readiness would immediately turn readiness.py's "no saved scope yet ->
  // default to the Master Migration Template's own 5 tables" behavior into
  // "saved, all 28 tables" the first time anyone used the tool without
  // narrowing modules first -- defeating the point of that default (2026-08-17).
  const readinessLink = document.getElementById("view-readiness-link");
  if (readinessLink) readinessLink.onclick = () => {
    const val = document.getElementById("src-sys").value.trim();
    if (!val) { alert("Enter the source system name first."); return; }
    state.sourceSystem = val;
    state.step = "readiness";
    renderMigrationReadinessStep();
  };
  document.getElementById("next-1").onclick = () => {
    if (unavailable) return;
    const val = document.getElementById("src-sys").value.trim();
    if (!val) { alert("Enter the source system name to continue."); return; }
    state.sourceSystem = val;
    state.step = 2;
    renderStep2();
  };
}

// Recursively renders form_xml.py's bounded tree structure as nested <ul>s.
// Every piece of text here is uploaded file content, not something this tool
// authored, so everything goes through escapeHtml -- unlike most of the rest
// of this file, which renders a consultant's own typed input back to them.
function renderXmlTreeNode(node) {
  const attrs = node.attrib
    ? ` <span class="xml-attrs">${Object.entries(node.attrib).map(([k, v]) => `${escapeHtml(k)}="${escapeHtml(v)}"`).join(" ")}</span>`
    : "";
  const text = node.text ? ` <span class="xml-text">"${escapeHtml(node.text)}"</span>` : "";
  const truncated = node.truncated ? `<div class="xml-truncated">${escapeHtml(node.truncated)}</div>` : "";
  const children = node.children && node.children.length
    ? `<ul>${node.children.map(c => `<li>${renderXmlTreeNode(c)}</li>`).join("")}</ul>`
    : "";
  return `<span class="xml-tag">&lt;${escapeHtml(node.tag)}&gt;</span>${attrs}${text}${truncated}${children}`;
}

// Comments is always a decode list (create_template.py only ever populates
// it from a ListID's values, one "code - label" per line) -- a short list
// (Yes/No, etc.) is fine shown in full, but a long one (Gender, Race: 15-30
// lines) stretched the whole Comments row for every field in the table.
// Collapsed in place per-cell (Michael's call, 2026-08-13: keep the
// transposed layout matching the reference spreadsheet, don't restructure
// the preview into one row per field) rather than always-expanded.
const COMMENTS_COLLAPSE_THRESHOLD = 3; // lines; short lists just show in full, nothing to gain by collapsing

function renderCommentsCell(comments) {
  if (!comments) return "";
  const lines = comments.split("\n");
  const full = escapeHtml(comments).replace(/\n/g, "<br>");
  if (lines.length <= COMMENTS_COLLAPSE_THRESHOLD) return full;
  // Explicit [open]-scoped visibility, not the browser's own native <details>
  // collapse -- see the Step 3 override-details CSS comment for why that
  // wasn't reliably hiding content in this app's rendering environment.
  return `
    <details class="comment-details">
      <summary>${lines.length} values</summary>
      <div class="comment-full">${full}</div>
    </details>`;
}

// One <table> per <Form> found, in the same column order as the reference
// Field Definition examples (WFDEmployment/WFDCheckIn): ColumnName/TableName/
// FieldLabel/DataType/FormElementType/Required/ListID/CharacterMaxLength/
// Comments. See create_template.py's own docstring for what each column is
// sourced from.
//
// The leading checkbox column is this table's own -- it controls which
// fields make it into the Field Definition and Staging Excel downloads
// (see state.createTemplate.selections).
// Synthetic join columns (primary-key anchors and foreign-key links this
// table needs but that were never a FormElement on the original form -- see
// create_template.py's compute_link_additions_by_form) render as real rows
// in-line with the form's own fields, not just a summary banner (Michael's
// call, 2026-08-12) -- no checkbox (a join key isn't optional the way a data
// field is) and a distinct "synthetic" tint so it's never mistaken for
// something the form actually asked for.
// Validation cell shared by both real and synthetic rows: r.validation is a
// human-readable summary of whatever the form itself configured
// (create_template.py's _validation_summary), r.validationIssue (real rows
// only -- always null on synthetic ones, which have no form validation of
// their own to judge) is a short reason that configuration doesn't match
// what the target field needs (_validation_issue) -- addresses Russ's
// 2026-08-18 comment that it takes manual form-by-form digging today to
// notice things like missing validation.
function renderValidationCell(r) {
  if (r.validationIssue) {
    return `<td class="ft-validation-issue" title="${escapeHtml(r.validationIssue)}">⚠ ${escapeHtml(r.validation || "None")}</td>`;
  }
  return `<td>${r.validation ? escapeHtml(r.validation) : ""}</td>`;
}

function renderSyntheticRow(r) {
  return `
    <tr class="ft-synthetic-row" title="Added automatically -- not a field on the original form">
      <td class="ft-select-cell">—</td>
      <td>${escapeHtml(r.columnName)}</td>
      <td>${escapeHtml(r.tableName)}</td>
      <td>${escapeHtml(r.fieldLabel)}</td>
      <td>${r.dataType ? escapeHtml(r.dataType) : `<span class="ft-unresolved">?</span>`}</td>
      <td>${escapeHtml(r.formElementType)}</td>
      <td>${escapeHtml(r.required)}</td>
      <td>${r.listId ? escapeHtml(r.listId) : ""}</td>
      <td>${r.characterMaxLength != null ? escapeHtml(String(r.characterMaxLength)) : ""}</td>
      ${renderValidationCell(r)}
      <td>${r.linkedTo ? `<span class="ft-linked">${escapeHtml(r.linkedTo)}</span>` : ""}</td>
      <td class="ft-comments">${renderCommentsCell(r.comments)}</td>
    </tr>`;
}

function renderFormTemplateTable(form, formIndex, selected, linkAdditions) {
  const syntheticRows = (linkAdditions || []).map(renderSyntheticRow).join("");
  const rows = form.rows.map((r, i) => `
    <tr>
      <td class="ft-select-cell"><input type="checkbox" class="ct-field-cb" data-form-index="${formIndex}" data-row-index="${i}" ${selected.has(i) ? "checked" : ""}></td>
      <td>${escapeHtml(r.columnName)}</td>
      <td>${escapeHtml(r.tableName)}</td>
      <td>${escapeHtml(r.fieldLabel)}</td>
      <td>${r.dataType ? escapeHtml(r.dataType) : `<span class="ft-unresolved">?</span>`}</td>
      <td>${escapeHtml(r.formElementType)}</td>
      <td>${escapeHtml(r.required)}</td>
      <td>${r.listId ? escapeHtml(r.listId) : ""}</td>
      <td>${r.characterMaxLength != null ? escapeHtml(String(r.characterMaxLength)) : ""}</td>
      ${renderValidationCell(r)}
      <td>${r.linkedTo ? `<span class="ft-linked">${escapeHtml(r.linkedTo)}</span>` : ""}</td>
      <td class="ft-comments">${renderCommentsCell(r.comments)}</td>
    </tr>`).join("");
  // A plain informational tint, not import-error's red/orange -- this is an
  // honest "we don't have this fact yet" gap, not the tool malfunctioning.
  const unresolvedNote = form.unresolvedColumns && form.unresolvedColumns.length
    ? `<div class="import-notice import-info">Data type not found for: ${form.unresolvedColumns.map(escapeHtml).join(", ")} — their table isn't described in this export's own &lt;Tables&gt; section or in the base CaseWorthy schema.</div>`
    : "";
  return `
    <div class="field-def-block">
      <h4>${escapeHtml(form.formDisplayName || form.formName || "Untitled form")}</h4>
      <div class="field-def-subtitle">${escapeHtml(form.formName || "")} — ${form.rows.length} field(s), ${selected.size} selected for download${(linkAdditions || []).length ? `, ${linkAdditions.length} linking column${linkAdditions.length === 1 ? "" : "s"} added automatically` : ""}</div>
      <div class="module-actions">
        <button type="button" class="ghost ct-select-all" data-form-index="${formIndex}">Select all</button>
        <button type="button" class="ghost ct-select-none" data-form-index="${formIndex}">Deselect all</button>
        <button type="button" class="ghost ct-select-required" data-form-index="${formIndex}">Select required only</button>
      </div>
      ${unresolvedNote}
      <div class="xml-tree-wrap field-def-table-wrap">
        <table class="field-def-table">
          <thead><tr>
            <th></th><th>ColumnName</th><th>TableName</th><th>FieldLabel</th><th>DataType</th>
            <th>FormElementType</th><th>Required</th><th>ListID</th><th>CharacterMaxLength</th><th>Validation</th><th>LinkedTo</th><th>Comments</th>
          </tr></thead>
          <tbody>${syntheticRows}${rows || (syntheticRows ? "" : `<tr><td colspan="12" class="empty">No data fields found on this form.</td></tr>`)}</tbody>
        </table>
      </div>
    </div>`;
}

// Re-sends the already-uploaded file to a binary-response route and saves
// the result -- POST responses can't be downloaded via a plain <a href>, so
// this goes through fetch -> blob -> a temporary object URL instead.
// extraFields: plain object of additional form-data fields (e.g. the
// Staging Excel download's field selections).
async function downloadCreateTemplateFile(routeSuffix, filename, extraFields) {
  const ct = state.createTemplate;
  if (!ct.file) return;
  const formData = new FormData();
  formData.append("file", ct.file);
  if (extraFields) {
    Object.entries(extraFields).forEach(([key, value]) => formData.append(key, value));
  }
  const res = await fetch(`/api/create-template/${routeSuffix}`, { method: "POST", body: formData });
  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    alert(err.error || "Download failed.");
    return;
  }
  const blob = await res.blob();
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}

async function renderCreateTemplateStep() {
  const ct = state.createTemplate;

  const tagCountsHtml = ct.result
    ? `<div class="xml-tagcounts">Element counts: ${Object.entries(ct.result.tagCounts)
        .sort((a, b) => b[1] - a[1])
        .map(([tag, count]) => `${escapeHtml(tag)} (${count})`)
        .join(", ")}</div>`
    : "";
  const rawTreeHtml = ct.result
    ? `<div class="xml-tree-wrap"><div class="xml-tree">${renderXmlTreeNode(ct.result.tree)}</div></div>`
    : "";
  const errorHtml = ct.error ? `<div class="import-notice import-error">${escapeHtml(ct.error)}</div>` : "";

  const templates = ct.result && ct.result.formTemplates;
  const linkAdditionsByForm = (ct.result && ct.result.linkAdditionsByForm) || [];
  const templatesHtml = templates && templates.length
    ? templates.map((form, i) => renderFormTemplateTable(form, i, ct.selections[i], linkAdditionsByForm[i])).join("") + `
      <div class="step-nav" style="margin-top:4px;">
        <button class="secondary" id="ct-download-field-def">Download Field Definition (.xlsx)</button>
        <button class="secondary" id="ct-download-staging">Download Staging Excel (.xlsx)</button>
      </div>`
    : "";
  const templatesErrorHtml = ct.result && ct.result.formTemplatesError && !templates
    ? `<div class="import-notice">Couldn't build a Field Definition table from this file: ${escapeHtml(ct.result.formTemplatesError)} Showing the raw structure below instead.</div>`
    : "";
  // Always reflects what download time will do, regardless of the current
  // checkbox selections -- a join key isn't optional the way a data field
  // is (see create_template.py's compute_link_additions). The rows
  // themselves are now also spliced directly into each form's table above
  // (renderFormTemplateTable's syntheticRows) -- this banner stays as a
  // one-line total so a customer doesn't have to count grayed-out rows
  // across every form block to know how many there are.
  const linkAdditions = ct.result && ct.result.linkAdditions;
  const linkAdditionsHtml = linkAdditions && linkAdditions.length
    ? `<div class="import-notice import-info">Both downloads (and the tables below) automatically add ${linkAdditions.length} join column${linkAdditions.length === 1 ? "" : "s"} not present on the original form(s), needed to link sheets together: ${linkAdditions.map(a => a.kind === "primary-key"
        ? `${escapeHtml(a.table)}.${escapeHtml(a.column)} (its own primary key)`
        : `${escapeHtml(a.table)}.${escapeHtml(a.column)} → ${escapeHtml(a.linkedTo)}`).join(", ")}.</div>`
    : "";
  // Migration Readiness for this upload -- decoupled from the main wizard's
  // own db.py-backed rollup (no source-system identity, nothing keyed by
  // customer); computed by the server regardless of checkbox selections,
  // same precedent as linkAdditions above. Reflects EVERY upload recorded
  // so far (db.py's create_template_uploads), not just this one file --
  // found necessary 2026-08-17: a second upload wasn't "remembering" what
  // an earlier one in the same session already covered. Each required
  // field carries mappedBy (the file that covers it) or null (still
  // missing) -- see renderFormReadinessPanel.
  const formReadiness = ct.result && ct.result.readiness;
  const readinessHtml = formReadiness ? `
    <div class="card" style="margin-top:0;">
      <div style="display:flex;justify-content:space-between;align-items:center;gap:8px;">
        <h4 style="margin:0;">Migration Readiness (all forms uploaded so far)</h4>
        <div style="display:flex;gap:8px;">
          <button type="button" class="ghost" id="ct-print-readiness">Print</button>
          <button type="button" class="ghost" id="ct-clear-uploads">Clear uploaded forms</button>
        </div>
      </div>
      ${renderFormReadinessPanel(formReadiness.requiredFields)}
      ${renderValidationIssuesPanel(formReadiness.validationIssues)}
    </div>` : "";
  // Once the structured table renders, the raw tree is only useful for
  // double-checking something the table doesn't explain -- tuck it behind a
  // disclosure instead of showing both at full length. Without a structured
  // result (unrecognized export, or a parse error), show the tree by default.
  const rawTreeBlock = templatesHtml
    ? `<details class="xml-raw-details"><summary>Show raw XML structure</summary>${tagCountsHtml}${rawTreeHtml}</details>`
    : `${tagCountsHtml}${rawTreeHtml}`;

  app.innerHTML = `
    ${renderHeader()}
    <div class="card">
      <h3>Upload a Form XML Export</h3>
      <div class="import-row">
        <input type="file" id="xml-file" accept=".xml">
        <button class="secondary" id="xml-parse-btn" disabled>${ct.parsing ? "Parsing…" : "Preview Structure"}</button>
      </div>
      <div class="import-hint">Reads the whole file (it's form structure, not client data). A recognized CaseWorthy Form export (&lt;Ecm&gt;...) becomes a Field Definition table below; anything else falls back to a raw structure preview.</div>
      <div id="xml-status">${errorHtml}</div>
      ${ct.result ? `
        <div style="margin-top:14px;">
          <strong>${escapeHtml(ct.result.sourceFile)}</strong> — ${ct.result.elementCount.toLocaleString()} element(s)
        </div>
        ${templatesErrorHtml}
        ${linkAdditionsHtml}
        ${readinessHtml}
        ${templatesHtml}
        ${rawTreeBlock}
      ` : ""}
      <div class="step-nav">
        <button class="secondary" id="ct-back">← Back to Field Mapping</button>
        <span></span>
      </div>
    </div>
    ${renderFooter("Internal POC · CaseWorthy Technical Consulting", false)}
  `;

  const fileEl = document.getElementById("xml-file");
  const parseBtn = document.getElementById("xml-parse-btn");
  const statusEl = document.getElementById("xml-status");
  fileEl.onchange = () => { parseBtn.disabled = !fileEl.files.length; };
  // Shared by the initial "Preview Structure" click and the "Clear uploaded
  // forms" button's own refresh (re-parsing the already-loaded file so the
  // readiness panel reflects the now-empty coverage ledger immediately,
  // without asking the user to re-pick the file they already chose).
  async function reparseFile(file) {
    if (!file) return;
    ct.parsing = true;
    ct.error = null;
    parseBtn.disabled = true;
    parseBtn.textContent = "Parsing…";
    statusEl.innerHTML = "";
    try {
      const formData = new FormData();
      formData.append("file", file);
      const res = await fetch("/api/create-template/parse-xml", { method: "POST", body: formData });
      const result = await res.json();
      if (!res.ok || result.error) throw new Error(result.error || "Couldn't parse that file.");
      ct.result = result;
      ct.file = file; // kept so the download buttons can resend it without asking the user to re-pick
      // Default selection: Required fields start checked, Optional fields
      // start unchecked -- "pick and choose what you want in the staging
      // file," starting from the fields the target actually requires.
      ct.selections = (result.formTemplates || []).map(form =>
        new Set(form.rows.map((r, i) => i).filter(i => form.rows[i].required === "Required"))
      );
    } catch (err) {
      ct.error = err.message;
      ct.result = null;
      ct.file = null;
      ct.selections = null;
    } finally {
      ct.parsing = false;
      renderCreateTemplateStep();
    }
  }
  parseBtn.onclick = () => reparseFile(fileEl.files[0]);
  // Field-select checkboxes/buttons only exist once a structured result has
  // rendered -- updated in place (not a full re-render) so ticking one box
  // doesn't reset scroll position or repaint the whole (potentially large)
  // table.
  function updateSelectedCount(formIndex) {
    const block = document.querySelectorAll(".field-def-block")[formIndex];
    const subtitle = block && block.querySelector(".field-def-subtitle");
    if (!subtitle) return;
    const form = templates[formIndex];
    subtitle.textContent = `${form.formName || ""} — ${form.rows.length} field(s), ${ct.selections[formIndex].size} selected for download`;
  }
  document.querySelectorAll(".ct-field-cb").forEach(cb => {
    cb.onchange = () => {
      const fi = Number(cb.dataset.formIndex), ri = Number(cb.dataset.rowIndex);
      if (cb.checked) ct.selections[fi].add(ri); else ct.selections[fi].delete(ri);
      updateSelectedCount(fi);
    };
  });
  document.querySelectorAll(".ct-select-all").forEach(btn => {
    btn.onclick = () => {
      const fi = Number(btn.dataset.formIndex);
      ct.selections[fi] = new Set(templates[fi].rows.map((_, i) => i));
      document.querySelectorAll(`.ct-field-cb[data-form-index="${fi}"]`).forEach(cb => { cb.checked = true; });
      updateSelectedCount(fi);
    };
  });
  document.querySelectorAll(".ct-select-none").forEach(btn => {
    btn.onclick = () => {
      const fi = Number(btn.dataset.formIndex);
      ct.selections[fi] = new Set();
      document.querySelectorAll(`.ct-field-cb[data-form-index="${fi}"]`).forEach(cb => { cb.checked = false; });
      updateSelectedCount(fi);
    };
  });
  document.querySelectorAll(".ct-select-required").forEach(btn => {
    btn.onclick = () => {
      const fi = Number(btn.dataset.formIndex);
      const form = templates[fi];
      ct.selections[fi] = new Set(form.rows.map((r, i) => i).filter(i => form.rows[i].required === "Required"));
      document.querySelectorAll(`.ct-field-cb[data-form-index="${fi}"]`).forEach(cb => {
        cb.checked = ct.selections[fi].has(Number(cb.dataset.rowIndex));
      });
      updateSelectedCount(fi);
    };
  });
  // Both downloads honor the same checkbox selections now (Michael's call,
  // 2026-08-12) -- one shared payload sent to each.
  const selectionsPayload = () => ({ selections: JSON.stringify(ct.selections.map(set => Array.from(set))) });
  const downloadFieldDefBtn = document.getElementById("ct-download-field-def");
  if (downloadFieldDefBtn) downloadFieldDefBtn.onclick = () => downloadCreateTemplateFile(
    "download-field-definition", "Field_Definition.xlsx", selectionsPayload(),
  );
  const downloadStagingBtn = document.getElementById("ct-download-staging");
  if (downloadStagingBtn) downloadStagingBtn.onclick = () => downloadCreateTemplateFile(
    "download-staging-excel", "Staging_Excel.xlsx", selectionsPayload(),
  );
  const clearUploadsBtn = document.getElementById("ct-clear-uploads");
  if (clearUploadsBtn) clearUploadsBtn.onclick = async () => {
    if (!confirm("Clear the accumulated coverage from every form uploaded so far? This can't be undone.")) return;
    await api("/api/create-template/clear-uploads", { method: "POST" });
    // Deliberately does NOT re-parse the already-loaded file afterward --
    // that re-parse itself writes that file's own coverage straight back
    // into the ledger (parse-xml records on every call, not just the
    // first), so the readiness panel looked like it never fully cleared --
    // "one required target stuck" (Michael, 2026-08-17) was really every
    // field the still-loaded file covers, re-seeded immediately. Clearing
    // now blanks the whole preview; re-upload (or re-click "Preview
    // Structure") to start tracking again from a genuinely empty ledger.
    ct.result = null;
    ct.file = null;
    ct.selections = null;
    renderCreateTemplateStep();
  };
  const printReadinessBtn = document.getElementById("ct-print-readiness");
  if (printReadinessBtn) printReadinessBtn.onclick = () => {
    // window.open must run synchronously inside the click handler (no
    // await before it) or browsers treat it as an unrequested popup and
    // block it.
    printReadinessReport(formReadiness.requiredFields, formReadiness.validationIssues, ct.result.sourceFile);
  };
  document.getElementById("ct-back").onclick = () => {
    state.targetDatabase = "CaseWorthy";
    localStorage.setItem(TARGET_DB_STORAGE_KEY, state.targetDatabase);
    renderStep1();
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
      ${state.advancedMode ? `<input type="text" class="fsrctable" placeholder="Source table name (e.g. dbo.ClientExport)" value="${escapeHtml(f.sourceTable || "")}">` : ""}
      <input type="text" class="fname" placeholder="Source field name (e.g. Client_DOB)" value="${escapeHtml(f.name)}">
      <input type="text" class="fdesc" placeholder="Optional: short description or format (e.g. MM/DD/YYYY, 1=Yes/2=No)" value="${escapeHtml(f.desc)}">
      ${state.advancedMode ? `<input type="text" class="fsrcvalues" placeholder="Optional: this field's known source values (e.g. M, F, U or 1=Yes, 2=No)" value="${escapeHtml(f.sourceValues || "")}">` : ""}
      <button class="ghost remove-field">Remove</button>
    </div>
  `).join("");

  const advancedInstructions = state.advancedMode
    ? `Advanced options require table and column names, example: <strong>Client.ClientID</strong> or <strong>Client.DOB</strong>.`
    : "";
  const importFormatHint = state.advancedMode
    ? `Header cells should use that same "Table.Column" form (e.g. Client.ClientID) so we can split out the table name.`
    : `Header cells should just be the column name (e.g. ClientID).`;
  // lastImportNotice.text is pre-escaped where it's built (the import-btn
  // handler below) -- the one piece of it that's ever attacker-controllable
  // (the uploaded file's own name) goes through escapeHtml there before
  // this string is assembled, so it's safe to render as-is here.
  const notice = lastImportNotice
    ? `<div class="import-notice import-${lastImportNotice.kind}">${lastImportNotice.text}</div>`
    : "";
  lastImportNotice = null;

  app.innerHTML = `
    ${renderHeader()}
    <div class="card">
      <h3>List the Fields From ${escapeHtml(state.sourceSystem)}</h3>
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
      // result.sourceFile is the uploaded file's own name -- attacker-controllable
      // (nothing stops a crafted request from naming it anything), so it's
      // escaped here before landing in lastImportNotice.text, which renderStep2
      // trusts and renders as raw HTML. result.warnings is server-generated,
      // count-only text (see file_import.py's build_fields) -- safe as-is.
      const parts = [`Imported ${added} field${added === 1 ? "" : "s"} from ${escapeHtml(result.sourceFile)}.`];
      if (skipped) parts.push(`${skipped} duplicate${skipped === 1 ? "" : "s"} skipped.`);
      parts.push(...(result.warnings || []));
      lastImportNotice = { kind: "success", text: parts.join(" ") };
      renderStep2();
    } catch (err) {
      importStatusEl.innerHTML = `<div class="import-notice import-error">${escapeHtml(err.message)}</div>`;
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
  state.readinessMini = null;
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
  refreshReadinessMini();
}

// Compact Migration Readiness summary shown on the Mapping Suggestions page
// itself (Michael, 2026-08-18) -- reads whatever refreshReadinessMini last
// fetched from /api/readiness (same rollup the full readiness page uses),
// so it's always the real db.py state, never a locally-recomputed guess.
// Root element keeps a stable id so refreshReadinessMini can swap it in
// place via outerHTML without a full Step 3 re-render.
function renderReadinessMiniPanel() {
  const result = state.readinessMini;
  if (!result) {
    return `<div class="card" id="mapping-readiness-mini" style="margin-top:0;padding:10px 14px;font-size:13px;color:var(--surface-text-muted);">Checking migration readiness…</div>`;
  }
  const coverageLine = result.coveragePercent == null
    ? `No in-scope target fields to measure coverage against yet.`
    : `<strong>${result.coveragePercent}%</strong> of ${result.totalInScopeFieldCount} in-scope target fields mapped (${result.mappedFieldCount} confirmed).`;
  const missingCount = result.requiredMissing.length;
  const missingNote = missingCount
    ? `<span style="color:var(--cw-orange);">${missingCount} required field${missingCount === 1 ? "" : "s"} still missing.</span>`
    : `<span style="color:var(--surface-text-muted);">No required-field gaps in scope.</span>`;
  return `
    <div class="card" id="mapping-readiness-mini" style="margin-top:0;padding:12px 14px;display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:10px;">
      <div style="font-size:13px;"><strong>Migration Readiness:</strong> ${coverageLine} ${missingNote}</div>
      <button type="button" class="ghost" id="mapping-readiness-link" style="white-space:nowrap;">View full readiness →</button>
    </div>`;
}

function bindReadinessMiniHandlers() {
  const link = document.getElementById("mapping-readiness-link");
  if (link) link.onclick = () => { state.step = "readiness"; renderMigrationReadinessStep(); };
}

// Fire-and-forget: fetches the same rollup the full readiness page uses and
// swaps the mini panel in place, without disturbing whatever the customer's
// doing on the rest of the page (a full renderStep3Results() would blow away
// in-progress overrides on unrelated cards). Called once when Step 3 first
// loads and again after every confirmed mapping.
async function refreshReadinessMini() {
  const q = new URLSearchParams({ targetDatabase: state.targetDatabase, sourceSystem: state.sourceSystem, modules: effectiveModules().join(",") });
  const result = await api(`/api/readiness?${q.toString()}`);
  state.readinessMini = result;
  const panelHost = document.getElementById("mapping-readiness-mini");
  if (panelHost) panelHost.outerHTML = renderReadinessMiniPanel();
  bindReadinessMiniHandlers();
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
        <div class="src">${escapeHtml(s.source)}${s.desc ? ` <span style="font-weight:400;color:var(--surface-text-muted);">— ${escapeHtml(s.desc)}</span>` : ""}</div>
        ${s.sourceValues ? `<div class="decode">Known source values: ${escapeHtml(s.sourceValues)}</div>` : ""}
        ${hasMatch ? `<div class="target">${escapeHtml(shownTarget)} → ${escapeHtml(s.confirmedField)}</div>` : `<div class="target" style="color:var(--cw-orange);">No confident match</div>`}
        <span class="pill ${pillClass}">${pillLabel}</span>
        <div class="reason" style="margin-top:6px;">${escapeHtml(s.suggestion.reasoning || "")}</div>
        ${decode}${note}${requiredNote}${linkNote}${mergeNote}
        <div class="actions">
          <button class="secondary confirm-btn">${s.confirmed ? "Confirmed ✓" : "Confirm this mapping"}</button>
          <button class="ghost flag-btn" style="border-color:var(--surface-text-muted);color:var(--surface-text-muted);">Flag for consultant review</button>
        </div>
        <details class="override-details">
          <summary>Choose a different target field</summary>
          <div class="override-row">
            <select class="override-select">${options}</select>
            <button class="primary override-save">Use this</button>
          </div>
        </details>
      </div>
    `;
  }).join("");

  app.innerHTML = `
    ${renderHeader()}
    ${renderReadinessMiniPanel()}
    <div class="card">
      <h3>Mapping Suggestions for ${escapeHtml(state.sourceSystem)}</h3>
      <div style="color:var(--surface-text-muted);font-size:13px;margin-bottom:14px;">Confirm each mapping, pick a different target field, or flag anything ambiguous for manual review. Confirmed mappings are saved so the next customer on ${escapeHtml(state.sourceSystem)} sees them instantly.</div>
      ${cards || '<div class="empty">No fields to show.</div>'}
      <div class="step-nav">
        <button class="secondary" id="back-3">← Back</button>
        <button class="primary" id="next-3">Go to Summary →</button>
      </div>
    </div>
    ${renderFooter()}
  `;
  refreshLibStat();
  bindReadinessMiniHandlers();

  document.querySelectorAll(".suggestion-card").forEach(card => {
    const idx = parseInt(card.dataset.idx, 10);
    const s = state.suggestions[idx];
    card.querySelector(".confirm-btn").onclick = async () => {
      if (!s.confirmedTable || !s.confirmedField) { alert("Choose a target field first."); return; }
      await api("/api/confirm", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ targetDatabase: state.targetDatabase, sourceSystem: state.sourceSystem, fieldName: s.source, table: s.confirmedTable, field: s.confirmedField, desc: s.desc || "", confidence: s.suggestion.confidence || "" }),
      });
      s.confirmed = true;
      s.flagged = false;
      renderStep3Results();
      refreshReadinessMini();
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
      `<option value="${escapeHtml(code)}" ${preselect === code ? "selected" : ""}>${targetIsSelfPaired ? escapeHtml(label) : `${escapeHtml(code)} = ${escapeHtml(label)}`}</option>`
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
        <div class="value-match-row" data-code="${escapeHtml(code)}">
          <span class="value-match-src">${label !== code ? `${escapeHtml(code)} (${escapeHtml(label)})` : escapeHtml(code)}</span>
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
        <div class="src">${escapeHtml(s.source)} <span style="font-weight:400;color:var(--surface-text-muted);">→ ${escapeHtml(targetName)} → ${escapeHtml(s.confirmedField)}</span></div>
        <div class="decode">Approved values: ${targetIsSelfPaired ? targetPairs.map(p => escapeHtml(p[1])).join(", ") : targetPairs.map(([c, l]) => `${escapeHtml(c)}=${escapeHtml(l)}`).join(", ")}</div>
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
        <ul>${check.requiredMissing.map(r => `<li>${tableDisplayName(r.table)} → ${escapeHtml(r.field)}</li>`).join("")}</ul>
      </div>`);
  }
  if (check.fkWarnings.length) {
    groups.push(`
      <div class="readiness-group">
        <h4>Missing dependent tables</h4>
        <ul>${check.fkWarnings.map(w => `<li>${tableDisplayName(w.table)}.${escapeHtml(w.field)} references <strong>${tableDisplayName(w.dependsOn)}</strong>, but you haven't mapped any ${tableDisplayName(w.dependsOn)} fields yet.</li>`).join("")}</ul>
      </div>`);
  }
  if (check.duplicates.length) {
    groups.push(`
      <div class="readiness-group">
        <h4>Two source fields mapped to the same target</h4>
        <ul>${check.duplicates.map(d => `<li>${tableDisplayName(d.table)} → ${escapeHtml(d.field)} claimed by: ${d.sourceFields.map(escapeHtml).join(", ")}</li>`).join("")}</ul>
      </div>`);
  }
  if (check.formatHints.length) {
    groups.push(`
      <div class="readiness-group">
        <h4>Possible value/format mismatches</h4>
        <ul>${check.formatHints.map(h => `<li>${escapeHtml(h.sourceField)}: ${escapeHtml(h.hint)}</li>`).join("")}</ul>
      </div>`);
  }
  if (!groups.length) {
    return `<div class="readiness-panel"><div class="readiness-clean">✓ No rule violations detected against ${dbLabel()}'s import requirements.</div></div>`;
  }
  return `<div class="readiness-panel">${groups.join("")}</div>`;
}

// Create Template's own per-upload readiness check (poc/app.py's
// _handle_create_template_parse_xml + readiness.py's required_fields_for_tables)
// -- each entry carries mappedBy (the uploaded file that covers it) or null
// (still missing). Distinct from renderReadinessPanel above: that one only
// ever shows what's missing (check_batch never reports what's already
// satisfied), but showing the covering file name for a satisfied field is
// the whole point of this panel.
function renderFormReadinessPanel(requiredFields) {
  if (!requiredFields.length) {
    return `<div class="readiness-panel"><div class="readiness-clean">✓ No required fields to track yet -- upload a form to see its requirements.</div></div>`;
  }
  const missing = requiredFields.filter(r => !r.mappedBy);
  const covered = requiredFields.filter(r => r.mappedBy);
  const missingBlock = missing.length ? `
    <div class="readiness-group">
      <h4>Required target fields with no mapping yet</h4>
      <ul>${missing.map(r => `<li>${tableDisplayName(r.table)} → ${escapeHtml(r.field)}</li>`).join("")}</ul>
    </div>` : `<div class="readiness-clean">✓ Every required field tracked so far is covered by an uploaded form.</div>`;
  const coveredBlock = covered.length ? `
    <div class="readiness-group">
      <h4>Required target fields already covered</h4>
      <ul>${covered.map(r => `<li>${tableDisplayName(r.table)} → ${escapeHtml(r.field)} <span style="color:var(--surface-text-muted);">— from ${escapeHtml(r.mappedBy)}</span></li>`).join("")}</ul>
    </div>` : "";
  return `<div class="readiness-panel">${missingBlock}${coveredBlock}</div>`;
}

// Calls out fields whose own form validation doesn't match what their
// target field needs (create_template.py's _validation_issue, surfaced
// per-upload via db.get_create_template_uploads) -- Russ's 2026-08-18
// comment was specifically that this kind of thing takes manual form-by-
// form digging today; this is the "we already noticed it for you" answer.
// Named by table/field/file so a TC knows exactly which form to go fix.
function renderValidationIssuesPanel(validationIssues) {
  if (!validationIssues || !validationIssues.length) {
    return `<div class="readiness-panel"><div class="readiness-clean">✓ No validation issues found in any form uploaded so far.</div></div>`;
  }
  return `
    <div class="readiness-panel">
      <div class="readiness-group">
        <h4>Validation issues</h4>
        <ul>${validationIssues.map(v => `<li>${tableDisplayName(v.table)} → ${escapeHtml(v.field)} <span style="color:var(--surface-text-muted);">(${escapeHtml(v.file)})</span> — ${escapeHtml(v.issue)}</li>`).join("")}</ul>
      </div>
    </div>`;
}

// Opens a standalone, purpose-built print view of the Create Template
// readiness check (not the interactive SPA screen itself, which has too
// much unrelated chrome -- upload controls, other buttons, raw XML tree --
// to print cleanly) and triggers the browser's print dialog on it.
// mostRecentFile is just for the report's own header line -- the table
// below already names the real source file per field via each row's own
// "Source File" column.
function printReadinessReport(requiredFields, validationIssues, mostRecentFile) {
  const rows = requiredFields.slice().sort((a, b) =>
    tableDisplayName(a.table).localeCompare(tableDisplayName(b.table)) || a.field.localeCompare(b.field)
  );
  const coveredCount = rows.filter(r => r.mappedBy).length;
  const generatedAt = new Date().toLocaleString();
  const rowsHtml = rows.map(r => `
    <tr class="${r.mappedBy ? "covered" : "missing"}">
      <td>${escapeHtml(tableDisplayName(r.table))}</td>
      <td>${escapeHtml(r.field)}</td>
      <td>${r.mappedBy ? escapeHtml(r.mappedBy) : "Missing"}</td>
    </tr>`).join("");
  const validationRowsHtml = (validationIssues || []).map(v => `
    <tr class="missing">
      <td>${escapeHtml(tableDisplayName(v.table))}</td>
      <td>${escapeHtml(v.field)}</td>
      <td>${escapeHtml(v.file)}</td>
      <td>${escapeHtml(v.issue)}</td>
    </tr>`).join("");
  const validationSection = (validationIssues || []).length ? `
  <div class="summary">${validationIssues.length} validation issue${validationIssues.length === 1 ? "" : "s"} found.</div>
  <table>
    <thead><tr><th>Target Table</th><th>Field</th><th>Form</th><th>Issue</th></tr></thead>
    <tbody>${validationRowsHtml}</tbody>
  </table>` : `<div class="summary">No validation issues found in any form uploaded so far.</div>`;
  const html = `<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>Migration Readiness Report</title>
<style>
  body { font-family: Arial, Helvetica, sans-serif; color: #1a1a1a; padding: 24px; }
  h1 { font-size: 18px; margin: 24px 0 4px 0; }
  h1:first-of-type { margin-top: 0; }
  .meta { color: #555; font-size: 12px; margin-bottom: 4px; }
  .summary { margin: 12px 0; font-size: 13px; font-weight: bold; }
  table { width: 100%; border-collapse: collapse; font-size: 13px; margin-top: 8px; }
  th, td { border: 1px solid #ccc; padding: 6px 8px; text-align: left; }
  th { background: #f0f0f0; }
  tr.missing td { background: #fdeae3; }
  tr.covered td { background: #e2f4f1; }
  .print-btn { margin-bottom: 16px; }
  @media print { .print-btn { display: none; } }
</style>
</head>
<body>
  <button class="print-btn" onclick="window.print()">Print</button>
  <h1>Migration Readiness Report</h1>
  <div class="meta">Generated ${escapeHtml(generatedAt)}${mostRecentFile ? ` &middot; Most recently uploaded: ${escapeHtml(mostRecentFile)}` : ""}</div>
  <div class="summary">${coveredCount} of ${rows.length} required field${rows.length === 1 ? "" : "s"} covered so far.</div>
  <table>
    <thead><tr><th>Target Table</th><th>Field</th><th>Source File / Status</th></tr></thead>
    <tbody>${rowsHtml}</tbody>
  </table>
  <h1>Validation Issues</h1>
  ${validationSection}
</body>
</html>`;
  const win = window.open("", "_blank");
  if (!win) { alert("Your browser blocked the print report popup -- allow popups for this page and try again."); return; }
  win.document.write(html);
  win.document.close();
}

// Aggregates coverage/confidence/gaps across EVERY mapping persisted so far
// for this source system (readiness.py's compute_readiness), not just what's
// on screen right now -- reached from Step 1, not a numbered wizard step
// (state.step = "readiness" mirrors the non-numeric "3.5" sentinel already
// used for the value-match sub-step). Computed fresh from db.py on every
// visit, same as everything else in this app -- nothing here is cached.
async function renderMigrationReadinessStep() {
  const sourceSystem = state.sourceSystem;
  app.innerHTML = `
    ${renderHeader()}
    <div class="card">
      <h3>Migration Readiness — ${escapeHtml(sourceSystem)}</h3>
      <div class="loading">Checking everything mapped so far against ${dbLabel()}'s import requirements…</div>
    </div>
  `;
  refreshLibStat();

  const q = new URLSearchParams({ targetDatabase: state.targetDatabase, sourceSystem, modules: effectiveModules().join(",") });
  const result = await api(`/api/readiness?${q.toString()}`);

  const confBuckets = ["high", "medium", "low", "learned", "none", "unknown"];
  const confPills = confBuckets
    .filter(b => result.confidenceCounts[b] > 0)
    .map(b => `<span class="pill ${b}">${result.confidenceCounts[b]} ${b === "unknown" ? "unknown" : b.charAt(0).toUpperCase() + b.slice(1)}</span>`)
    .join(" ");

  const coverageLine = result.coveragePercent == null
    ? `No fields exist yet for the modules in scope — nothing to measure coverage against.`
    : `<strong>${result.coveragePercent}%</strong> of ${result.totalInScopeFieldCount} in-scope target fields mapped (${result.mappedFieldCount} confirmed mapping${result.mappedFieldCount === 1 ? "" : "s"} total).`;

  // scopeSource: "current" (the live tab/module-picker selection from Step 1
  // -- wins whenever it's available, see readiness.py), "saved" (an
  // explicit migration_scope exists, only ever consulted when there's no
  // live selection to offer), "masterTemplateDefault" (CaseWorthy, neither
  // of the above -- defaults to the Master Migration Template's own
  // tables, not all 28), or "fullSchema" (ServTracker, or a CaseWorthy
  // install with no Master Template loaded).
  const scopeNote = result.scopeSource === "current"
    ? `Scoped to what's currently selected on Step 1: ${result.scopeModules.map(escapeHtml).join(", ")}.`
    : result.scopeSource === "saved"
    ? `Scoped to: ${result.scopeModules.map(escapeHtml).join(", ")}.`
    : result.scopeSource === "masterTemplateDefault"
    ? `No saved module scope yet — showing gaps against the Master Migration Template's own tables: ${result.scopeModules.map(escapeHtml).join(", ")}. Use "Save current module scope" below once you know exactly which ${groupNounPlural()} this migration covers.`
    : `No saved module scope yet — showing gaps against ${dbLabel()}'s full schema. Use "Save current module scope" below once you know which ${groupNounPlural()} this migration covers.`;

  const unstarted = result.unstartedModules.length
    ? `<div class="db-warning"><strong>Not started yet:</strong> ${result.unstartedModules.map(escapeHtml).join(", ")} — in scope, but nothing has been mapped there.</div>`
    : "";

  app.innerHTML = `
    ${renderHeader()}
    <div class="card">
      <h3>Migration Readiness — ${escapeHtml(sourceSystem)}</h3>
      <div style="color:var(--surface-text-muted);font-size:13px;margin-bottom:6px;">${scopeNote}</div>
      <div style="margin:10px 0;">${coverageLine}</div>
      <div style="margin-bottom:14px;">${confPills || '<span style="color:var(--surface-text-muted);font-size:13px;">No confirmed mappings yet.</span>'}</div>
      ${unstarted}
      ${renderReadinessPanel(result)}
      <div class="step-nav">
        <button class="secondary" id="back-readiness">← Back</button>
        <button class="secondary" id="save-scope-readiness">Save current module scope</button>
      </div>
    </div>
    ${renderFooter()}
  `;
  refreshLibStat();

  document.getElementById("back-readiness").onclick = () => { state.step = 1; renderStep1(); };
  document.getElementById("save-scope-readiness").onclick = async () => {
    const mods = effectiveModules();
    if (!mods.length) { alert("No modules selected on Step 1 to save yet."); return; }
    await api("/api/migration-scope", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ targetDatabase: state.targetDatabase, sourceSystem, modules: mods }),
    });
    renderMigrationReadinessStep();
  };
}

// activeDb() already carries groupNoun ("tab"/"module") from schema_rules'
// own TARGET_DB_META -- this just reads it with a safe fallback rather than
// importing a whole extra concept for one word of copy.
function groupNounPlural() {
  const meta = activeDb();
  return (meta.groupNoun ? meta.groupNoun + "s" : "modules");
}

function renderSqlExportSection(exportResult) {
  if (!exportResult) return "";
  const headerBlock = exportResult.header ? `
    <pre style="background:var(--surface-page);border:1px solid var(--surface-border);color:var(--surface-text);border-radius:6px;padding:12px;font-size:12px;overflow-x:auto;white-space:pre-wrap;margin-bottom:14px;">${escapeHtml(exportResult.header)}</pre>` : "";
  const blocks = exportResult.statements.map(s => `
    <div style="margin-bottom:14px;">
      <div style="font-family:var(--font-heading);font-weight:600;color:var(--surface-heading);margin-bottom:4px;">${escapeHtml(s.targetTable)} <span style="color:var(--surface-text-muted);font-weight:400;">(source: ${escapeHtml(s.sourceTable)})</span></div>
      <pre style="background:var(--surface-page);border:1px solid var(--surface-border);color:var(--surface-text);border-radius:6px;padding:12px;font-size:12px;overflow-x:auto;white-space:pre-wrap;">${escapeHtml(s.sql)}</pre>
    </div>`).join("");

  const multiSource = exportResult.multiSourceTables.length ? `
    <div class="db-warning">
      <strong>These target tables are split across more than one source table</strong> — no JOIN is generated, so you'll get one SELECT per source table below and need to merge the results yourself:
      <ul style="margin:6px 0 0 0;">${exportResult.multiSourceTables.map(m => `<li>${escapeHtml(m.targetTable)}: ${m.sourceTables.map(escapeHtml).join(", ")}</li>`).join("")}</ul>
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
      <h3>Summary — ${escapeHtml(state.sourceSystem)}</h3>
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
    return `<tr class="${rowClass}"><td>${escapeHtml(s.source)}</td><td>${target}</td><td>${status}</td></tr>`;
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
      <h3>Summary — ${escapeHtml(state.sourceSystem)}</h3>
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
