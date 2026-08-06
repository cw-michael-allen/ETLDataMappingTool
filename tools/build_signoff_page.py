"""
Render reference/servtracker_schema_full.json as a single self-contained HTML
page for human sign-off.

Generated from the schema itself rather than hand-written, so the review copy
can't drift from what the tool actually loads. Brand tokens are taken from
poc/static/styles.css, which the POC README names as already following the
caseworthy-brand-visual-identity skill.

    python tools/build_signoff_page.py
"""

import collections
import html
import json
import os
import re

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCHEMA = os.path.join(REPO_ROOT, "reference", "servtracker_schema_full.json")
REPORT = os.path.join(REPO_ROOT, "reference", "servtracker_extraction_report.md")
OUT = os.path.join(REPO_ROOT, "reference", "servtracker_schema_review.html")


def esc(s):
    return html.escape(str(s if s is not None else ""))


def report_counts():
    """Pull the open-findings counts straight out of the generated report so the
    two documents can never disagree about how many there are."""
    if not os.path.exists(REPORT):
        return {}
    text = open(REPORT, encoding="utf-8").read()

    def rows_under(heading):
        m = re.search(r"###\s+%s\n(.*?)(?=\n### |\n## |\Z)" % re.escape(heading), text, re.S)
        if not m:
            return 0
        body = m.group(1)
        return len([
            ln for ln in body.split("\n")
            if ln.strip().startswith("|") and not re.match(r"^\|[\s\-|]+\|$", ln.strip())
        ]) - 1  # drop the header row

    return {
        "dead": max(rows_under("Checks against import tables that are never created"), 0),
        "mismatch": max(rows_under("`FieldName` label disagreeing with the column tested"), 0),
        "uncaptured": max(rows_under("Rules read but not captured"), 0),
    }


def type_class(t):
    base = t.split(" (")[0]
    return {
        "List": "t-list", "Date": "t-date", "Time": "t-date",
        "Numeric": "t-num", "Text": "t-text",
    }.get(base, "t-fk" if base.startswith("FK") else "t-text")


def build():
    rows = json.load(open(SCHEMA, encoding="utf-8"))
    counts = report_counts()

    by_module = collections.OrderedDict()
    for r in rows:
        for mod in (r.get("modules") or ["(no module)"]):
            by_module.setdefault(mod, collections.OrderedDict()).setdefault(r["sheet"], []).append(r)

    # Base module first, then by size -- reviewers work top-down and the client
    # sheet is the one every other sheet depends on.
    def module_sort(item):
        name = item[0]
        return (name != "Client Master with Demographics", name)

    ordered = sorted(by_module.items(), key=module_sort)

    scratch = sum(1 for r in rows if r.get("notesColumn"))
    total = len(rows) - scratch
    required = sum(1 for r in rows if r["required"])
    unvalidated = sum(1 for r in rows if not r.get("validated") and not r.get("notesColumn"))
    with_values = sum(1 for r in rows if r.get("decodeValues"))
    lookups = sum(1 for r in rows if r.get("lookupTable"))
    sheets = len({r["sheet"] for r in rows})

    parts = []
    a = parts.append

    a('<div class="wrap">')
    a('<header class="hero">')
    a('<div class="eyebrow">CaseWorthy · CW-ETL-FIELDMAP</div>')
    a("<h1>ServTracker Target Schema</h1>")
    a('<p class="sub">Extracted from <code>1 - Master Validation.sql</code> and the 18 master Excel '
      'templates. Every rule below is transcribed from one of those two sources — nothing is inferred. '
      'Review and sign off.</p>')
    a('<div class="stats">')
    for label, value in (
        ("Migratable fields", total), ("Sheets", sheets), ("Required", required),
        ("Allowed-value lists", with_values), ("Lookup-validated", lookups),
        ("No rule found", unvalidated), ("Scratch columns", scratch),
    ):
        a(f'<div class="stat"><div class="n">{value}</div><div class="l">{esc(label)}</div></div>')
    a("</div></header>")

    # ---- what sign-off actually covers -------------------------------------
    a('<section class="card callout">')
    a("<h2>What you're signing off on</h2>")
    a("<ul class=\"check\">")
    a(f"<li><strong>{total} migratable fields across {sheets} sheets</strong> match the columns in "
      "the master templates — the templates are the authority on which fields we offer to migrate.</li>")
    a(f"<li><strong>{scratch} <code>Comments</code> scratch columns</strong> are shown but marked "
      "<span class=\"badge b-notes\">scratch — not migrated</span>. They are free space for whoever "
      "fills the template in, and are excluded as mapping destinations so no data can be routed "
      "into them. <code>Comment</code> (singular) is the real, validated field.</li>")
    a(f"<li><strong>All 785 validation checks parsed</strong>, none unreadable. {required} fields are "
      "marked required; each was cross-checked against an independent parse with zero contradictions.</li>")
    a("<li><strong>Commented-out SQL was excluded</strong>, so retired blocks like "
      "<code>CaseManagersImport</code> contribute no rules.</li>")
    a("<li><strong>Adult DayCare and HDM Meal Choice are excluded</strong> per your call; their "
      "modules do not appear anywhere below.</li>")
    a(f"<li><strong>{unvalidated} fields have no rule found.</strong> That means no rule was located in "
      "the script — <em>not</em> that the field is unconstrained. They're shown as "
      "<span class=\"badge b-unval\">no rule found</span>.</li>")
    a("</ul>")
    if counts:
        a('<div class="open">')
        a("<h3>Still open in the source script — not schema defects</h3>")
        a("<p>These don't block sign-off on the schema, but each is a real bug in "
          "<code>1 - Master Validation.sql</code> worth fixing upstream:</p><ul>")
        if counts.get("dead"):
            a(f"<li><strong>{counts['dead']} table(s) referenced but never created</strong> "
              "(<code>ClientMembershipDetailImport</code>, <code>DestinationsImport</code>) — 21 checks "
              "that never run in production.</li>")
        if counts.get("mismatch"):
            a(f"<li><strong>{counts['mismatch']} checks report against the wrong field</strong> — the "
              "<code>FieldName</code> label disagrees with the column actually tested, so customers see "
              "errors attributed to the wrong column.</li>")
        if counts.get("uncaptured"):
            a(f"<li><strong>{counts['uncaptured']} checks state no machine-readable constraint</strong>, "
              "including typos like <em>“Monthly units most be a number”</em>.</li>")
        a("</ul></div>")
    a("</section>")

    # ---- controls ----------------------------------------------------------
    a('<section class="card controls">')
    a('<input type="search" id="q" placeholder="Filter by field, sheet, or module…" '
      'autocomplete="off" aria-label="Filter fields">')
    a('<div class="toggles">')
    for tid, lbl in (("f-req", "Required only"), ("f-unval", "No rule found"),
                     ("f-vals", "Has allowed values"), ("f-flag", "Link / merge keys")):
        a(f'<label class="tog"><input type="checkbox" id="{tid}"> {esc(lbl)}</label>')
    a('</div><div class="hint" id="count"></div></section>')

    # ---- modules -----------------------------------------------------------
    for mod, sheets_map in ordered:
        mod_fields = sum(len(v) for v in sheets_map.values())
        is_base = mod == "Client Master with Demographics"
        a(f'<section class="card module" data-module="{esc(mod)}">')
        a('<h2 class="mod-head">')
        a(f"<span>{esc(mod)}</span>")
        if is_base:
            a('<span class="badge b-base">required base module</span>')
        a(f'<span class="mod-meta">{len(sheets_map)} sheet(s) · {mod_fields} fields</span>')
        a("</h2>")

        for sheet, fields in sheets_map.items():
            table = fields[0].get("table")
            a('<div class="sheet">')
            a(f'<h3>{esc(sheet)} <span class="tbl">→ {esc(table)}</span></h3>')
            a('<div class="tblwrap"><table>')
            a("<thead><tr><th>Field</th><th>Req</th><th>Type</th>"
              "<th>Allowed values / notes</th></tr></thead><tbody>")
            for f in fields:
                flags = []
                if f.get("notesColumn"):
                    flags.append('<span class="badge b-notes">scratch — not migrated</span>')
                if f.get("linkKey"):
                    flags.append('<span class="badge b-link">link key</span>')
                if f.get("mergeOnly"):
                    flags.append('<span class="badge b-merge">merge only</span>')
                if not f.get("validated") and not f.get("notesColumn"):
                    flags.append('<span class="badge b-unval">no rule found</span>')
                if f.get("unique"):
                    flags.append('<span class="badge b-uniq">unique</span>')
                if f.get("maxLengthConflict"):
                    flags.append('<span class="badge b-warn">length conflict</span>')

                detail = []
                if f.get("decodeValues"):
                    detail.append(
                        '<span class="vals">'
                        + " ".join(f'<code>{esc(v)}</code>' for v in f["decodeValues"])
                        + "</span>"
                    )
                if f.get("lookupTable"):
                    detail.append(
                        f'<span class="muted">Validated against the <code>{esc(f["lookupTable"])}</code> '
                        "lookup table — values live in the database, not the script.</span>"
                    )
                if f.get("note"):
                    detail.append(f'<span class="note">{esc(f["note"])}</span>')
                if f.get("ruleSourceTable"):
                    detail.append(
                        f'<span class="muted">Rules sourced from <code>{esc(f["ruleSourceTable"])}</code>.</span>'
                    )

                search = " ".join([f["field"], sheet, mod, f["type"]]).lower()
                attrs = (
                    f' data-s="{esc(search)}"'
                    f' data-req="{1 if f["required"] else 0}"'
                    f' data-unval="{0 if f.get("validated") else 1}"'
                    f' data-vals="{1 if f.get("decodeValues") else 0}"'
                    f' data-flag="{1 if (f.get("linkKey") or f.get("mergeOnly")) else 0}"'
                )
                a(f'<tr{attrs}{" class=notes-row" if f.get("notesColumn") else ""}>')
                a(f'<td class="fname"><code>{esc(f["field"])}</code> {" ".join(flags)}</td>')
                a(f'<td class="req">{"●" if f["required"] else ""}</td>')
                a(f'<td><span class="type {type_class(f["type"])}">{esc(f["type"])}</span></td>')
                a(f'<td class="detail">{"".join(detail) or "<span class=muted>—</span>"}</td>')
                a("</tr>")
            a("</tbody></table></div></div>")
        a("</section>")

    a('<footer class="foot">Generated by <code>tools/build_signoff_page.py</code> from '
      '<code>reference/servtracker_schema_full.json</code>. Regenerate after any re-extraction.</footer>')
    a("</div>")

    return "\n".join(parts)


CSS = """
:root{
  --cw-blue:#003594;--cw-teal:#009ABE;--cw-teal-dark:#007898;--cw-gold:#EDB400;
  --cw-black:#333;--cw-gray:#CED1D4;--cw-green:#0E9987;--cw-purple:#7265AF;--cw-orange:#DA623E;
  --page:#F7F8F9;--card:#fff;--border:#CED1D4;--text:#333;--muted:#6B6B6B;--head:#003594;
  --tint:#EEF2FA;
  --font-h:'Poppins','Helvetica Neue',Arial,sans-serif;
  --font-b:'Source Sans 3','Source Sans Pro',-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
}
@media (prefers-color-scheme:dark){
  :root{--page:#16181A;--card:#24282B;--border:#3A4045;--text:#F5F6F7;--muted:#A8AEB3;
        --head:#fff;--tint:#2A3F55;}
}
:root[data-theme="dark"]{--page:#16181A;--card:#24282B;--border:#3A4045;--text:#F5F6F7;
  --muted:#A8AEB3;--head:#fff;--tint:#2A3F55;}
:root[data-theme="light"]{--page:#F7F8F9;--card:#fff;--border:#CED1D4;--text:#333;
  --muted:#6B6B6B;--head:#003594;--tint:#EEF2FA;}

*{box-sizing:border-box}
body{margin:0;background:var(--page);color:var(--text);font-family:var(--font-b);
  font-size:15px;line-height:1.55;-webkit-font-smoothing:antialiased}
.wrap{max-width:1140px;margin:0 auto;padding:28px 18px 60px}
h1,h2,h3{font-family:var(--font-h);color:var(--head);margin:0}
code{font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:.86em;
  background:var(--tint);padding:1px 5px;border-radius:3px;color:var(--text)}

.hero{margin-bottom:22px}
.eyebrow{font-family:var(--font-h);font-size:11px;letter-spacing:.14em;text-transform:uppercase;
  color:var(--cw-teal);font-weight:600;margin-bottom:6px}
.hero h1{font-size:30px;font-weight:700;letter-spacing:-.01em}
.sub{color:var(--muted);max-width:76ch;margin:8px 0 0}
.stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(120px,1fr));gap:10px;margin-top:18px}
.stat{background:var(--card);border:1px solid var(--border);border-radius:8px;padding:12px 14px}
.stat .n{font-family:var(--font-h);font-size:24px;font-weight:700;color:var(--cw-teal);line-height:1.1}
.stat .l{font-size:11.5px;color:var(--muted);text-transform:uppercase;letter-spacing:.05em;margin-top:2px}

.card{background:var(--card);border:1px solid var(--border);border-radius:10px;
  padding:20px 22px;margin-bottom:18px}
.callout{border-left:4px solid var(--cw-teal)}
.callout h2{font-size:18px;margin-bottom:10px}
ul.check{list-style:none;padding:0;margin:0}
ul.check li{position:relative;padding-left:26px;margin-bottom:9px}
ul.check li::before{content:"✓";position:absolute;left:0;top:0;color:var(--cw-green);font-weight:700}
.open{margin-top:18px;padding:14px 16px;background:var(--tint);border-radius:8px;
  border-left:3px solid var(--cw-gold)}
.open h3{font-size:14px;color:var(--cw-orange);margin-bottom:6px}
.open p{margin:0 0 8px;font-size:13.5px;color:var(--muted)}
.open ul{margin:0;padding-left:20px;font-size:13.5px}
.open li{margin-bottom:5px}

.controls{position:sticky;top:0;z-index:20;display:flex;flex-wrap:wrap;gap:12px;
  align-items:center;padding:14px 18px}
#q{flex:1 1 260px;min-width:0;padding:9px 12px;border:1px solid var(--border);border-radius:6px;
  background:var(--page);color:var(--text);font-family:var(--font-b);font-size:14px}
#q:focus{outline:2px solid var(--cw-teal);outline-offset:1px}
.toggles{display:flex;flex-wrap:wrap;gap:12px}
.tog{font-size:13px;color:var(--muted);display:flex;align-items:center;gap:5px;cursor:pointer;
  white-space:nowrap}
.hint{font-size:12.5px;color:var(--muted);margin-left:auto}

.module{padding-top:16px}
.mod-head{display:flex;align-items:center;gap:10px;flex-wrap:wrap;font-size:19px;
  padding-bottom:10px;border-bottom:2px solid var(--cw-teal);margin-bottom:14px}
.mod-meta{margin-left:auto;font-family:var(--font-b);font-size:12.5px;color:var(--muted);font-weight:400}
.sheet{margin-bottom:20px}
.sheet h3{font-size:14.5px;margin-bottom:7px;display:flex;gap:8px;align-items:baseline;flex-wrap:wrap}
.tbl{font-family:var(--font-b);font-size:12px;color:var(--muted);font-weight:400}

.tblwrap{overflow-x:auto;border:1px solid var(--border);border-radius:7px}
table{width:100%;border-collapse:collapse;font-size:13.5px;min-width:640px}
thead th{position:sticky;top:0;background:var(--tint);color:var(--head);text-align:left;
  font-family:var(--font-h);font-size:11.5px;letter-spacing:.04em;text-transform:uppercase;
  padding:8px 11px;white-space:nowrap}
tbody td{padding:8px 11px;border-top:1px solid var(--border);vertical-align:top}
tbody tr:hover{background:var(--tint)}
.fname{white-space:nowrap}
.req{text-align:center;color:var(--cw-orange);font-size:15px;width:44px}
.detail{width:46%}
.detail .muted,.muted{color:var(--muted);font-size:12.5px}
.note{display:block;color:var(--cw-teal-dark);font-size:12.5px}
.vals code{margin-right:3px;margin-bottom:2px;display:inline-block}

.type{font-size:11.5px;font-family:var(--font-h);padding:2px 7px;border-radius:10px;
  white-space:nowrap;border:1px solid transparent}
.t-text{color:var(--muted);border-color:var(--border)}
.t-list{color:var(--cw-purple);border-color:var(--cw-purple)}
.t-date{color:var(--cw-teal-dark);border-color:var(--cw-teal)}
.t-num{color:var(--cw-green);border-color:var(--cw-green)}
.t-fk{color:var(--cw-orange);border-color:var(--cw-orange)}

.badge{font-family:var(--font-h);font-size:10px;text-transform:uppercase;letter-spacing:.04em;
  padding:2px 6px;border-radius:9px;white-space:nowrap;font-weight:600}
/* teal-dark, not teal: white on #009ABE is 3.3:1, and these badges are 10px
   uppercase, so they need the 4.5:1 small-text threshold. Both are brand
   tokens; this just picks the one that passes. */
.b-link{background:var(--cw-teal-dark);color:#fff}
.b-merge{background:var(--cw-purple);color:#fff}
.b-unval{background:transparent;color:var(--cw-orange);border:1px solid var(--cw-orange)}
.b-uniq{background:transparent;color:var(--cw-green);border:1px solid var(--cw-green)}
.b-warn{background:var(--cw-gold);color:#333}
.b-base{background:var(--cw-blue);color:#fff}
.b-notes{background:transparent;color:var(--muted);border:1px dashed var(--border)}
tr.notes-row{opacity:.72}

.foot{text-align:center;font-size:12px;color:var(--muted);margin-top:28px}
tr.hide,.sheet.hide,.module.hide{display:none}
@media (max-width:640px){
  .hero h1{font-size:24px}
  .controls{position:static}
  .hint{margin-left:0;width:100%}
}
"""

JS = """
(function(){
  var q=document.getElementById('q'), count=document.getElementById('count');
  var togs=['f-req','f-unval','f-vals','f-flag'].map(function(id){return document.getElementById(id);});
  var rows=[].slice.call(document.querySelectorAll('tbody tr'));
  function apply(){
    var term=(q.value||'').trim().toLowerCase();
    var req=togs[0].checked, unval=togs[1].checked, vals=togs[2].checked, flag=togs[3].checked;
    var shown=0;
    rows.forEach(function(r){
      var ok = (!term || r.dataset.s.indexOf(term)>-1)
        && (!req   || r.dataset.req==='1')
        && (!unval || r.dataset.unval==='1')
        && (!vals  || r.dataset.vals==='1')
        && (!flag  || r.dataset.flag==='1');
      r.classList.toggle('hide', !ok);
      if(ok) shown++;
    });
    // Collapse sheets and modules that have nothing left to show.
    [].forEach.call(document.querySelectorAll('.sheet'), function(s){
      s.classList.toggle('hide', !s.querySelector('tbody tr:not(.hide)'));
    });
    [].forEach.call(document.querySelectorAll('.module'), function(m){
      m.classList.toggle('hide', !m.querySelector('.sheet:not(.hide)'));
    });
    count.textContent = shown + ' of ' + rows.length + ' fields';
  }
  q.addEventListener('input', apply);
  togs.forEach(function(t){ t.addEventListener('change', apply); });
  apply();
})();
"""


def main():
    body = build()
    page = (
        '<link rel="preconnect" href="https://fonts.googleapis.com">\n'
        '<style>%s</style>\n%s\n<script>%s</script>\n' % (CSS, body, JS)
    )
    with open(OUT, "w", encoding="utf-8") as f:
        # Declared explicitly: opened as a local file, or served without a
        # charset header, the em dashes and arrows otherwise render as mojibake.
        f.write('<meta charset="utf-8">\n')
        f.write('<meta name="viewport" content="width=device-width, initial-scale=1">\n')
        f.write("<title>ServTracker Target Schema — Sign-off Review</title>\n")
        f.write(page)
    print("Wrote %s (%.0f KB)" % (os.path.relpath(OUT, REPO_ROOT), os.path.getsize(OUT) / 1024))


if __name__ == "__main__":
    main()
