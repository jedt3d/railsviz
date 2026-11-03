// rails_vis viewer: renders the JSON embedded by `bin/rails rails_vis:dump`.
// Everything that comes from the data (names, paths, document bodies, warnings) is untrusted:
// it is inserted as text nodes, and Markdown output passes through sanitizeFragment first.
(function () {
  "use strict";

  const dataEl = document.getElementById("rails-vis-data");
  const main = document.getElementById("main");
  if (!dataEl) {
    main.textContent = "No data embedded. Run bin/rails rails_vis:dump and open doc/rails_vis/index.html.";
    return;
  }
  const DATA = JSON.parse(dataEl.textContent);
  const meta = DATA.meta || {};
  const list = (key) => Array.isArray(DATA[key]) ? DATA[key] : [];
  const documents = list("documents");
  const routes = list("routes");
  const controllers = list("controllers");
  const models = list("models");
  const databases = list("databases");
  const warnings = list("warnings");

  const NAV = [
    ["start", "Start here"],
    ["requests", "Request map"],
    ["domain", "Domain model"],
    ["databases", "Databases"],
    ["docs", "All documents"]
  ];
  const state = { query: "", audience: "engineer" };

  // ---------- helpers ----------

  // h("a", { href, class }, "text", node, [more]) builds an element; strings become text nodes.
  function h(tag, attrs, ...children) {
    const el = document.createElement(tag);
    for (const [k, v] of Object.entries(attrs || {})) {
      if (v == null || v === false) continue;
      if (k === "class") el.className = v;
      else if (k.startsWith("on")) el.addEventListener(k.slice(2), v);
      else el.setAttribute(k, v === true ? "" : v);
    }
    append(el, children);
    return el;
  }

  function append(el, children) {
    for (const c of children.flat(Infinity)) {
      if (c == null || c === false) continue;
      el.append(c instanceof Node ? c : document.createTextNode(String(c)));
    }
    return el;
  }

  function safeUrl(url) {
    return typeof url === "string" && /^https?:\/\//i.test(url) ? url : null;
  }

  function ext(url, text) {
    const href = safeUrl(url);
    return href ? h("a", { href, target: "_blank", rel: "noopener noreferrer" }, text) : null;
  }

  // A code node { name, path, line, url }: GitHub link when url is set, else the path as text.
  function codeLink(node, label) {
    if (!node) return h("span", { class: "muted" }, "no source");
    const where = node.path + (node.line ? ":" + node.line : "");
    const name = label || node.name || where;
    const path = name === node.path || name === where ? null : [" ", h("code", { class: "muted" }, where)];
    return h("span", { class: "code-node" }, ext(node.url, name) || h("span", {}, name), path);
  }

  const matches = (...names) => !state.query || names.some((n) => n && String(n).toLowerCase().includes(state.query));
  const label = (text) => h("div", { class: "cap" }, text);
  const empty = (text) => h("p", { class: "empty" }, text);
  const docHref = (doc) => "#/doc/" + encodeURIComponent(doc.path);
  const modelHref = (name) => "#/domain/" + encodeURIComponent(name);
  const modelNames = new Set(models.map((m) => m.name));

  function modelLink(name) {
    return modelNames.has(name) ? h("a", { href: modelHref(name) }, name) : h("span", {}, name);
  }

  // Documents whose `related` points at a file (compared by repository-relative path).
  function docsAbout(path) {
    return path ? documents.filter((d) => (d.related || []).some((n) => n && n.path === path)) : [];
  }

  function docList(docs) {
    return h("ul", { class: "plain" }, docs.map((d) => h("li", {}, h("a", { href: docHref(d) }, d.title || d.path))));
  }

  function section(title, ...body) {
    return h("section", { class: "block" }, h("h3", { class: "cap" }, title), body);
  }

  function table(head, rows, cls) {
    return h("div", { class: "table-wrap" },
      h("table", { class: cls || "" },
        h("thead", {}, h("tr", {}, head.map((t) => h("th", { scope: "col" }, t)))),
        h("tbody", {}, rows)));
  }

  function pageHeader(title, sub) {
    return h("header", { class: "page-head" }, h("h1", {}, title), sub ? h("p", { class: "muted" }, sub) : null);
  }

  const dark = window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches;
  if (window.mermaid) {
    window.mermaid.initialize({ startOnLoad: false, securityLevel: "strict", theme: dark ? "dark" : "neutral", maxTextSize: 500000 });
  }

  async function renderMermaid(nodes) {
    if (!nodes.length) return;
    if (!window.mermaid) return nodes.forEach((n) => n.classList.add("mermaid-error"));
    for (const node of nodes) {
      try {
        await window.mermaid.run({ nodes: [node] });
      } catch (e) {
        const src = node.dataset.source || "";
        node.replaceChildren(h("p", { class: "warn-text" }, "Diagram failed to render: " + (e && e.message ? e.message : e)), h("pre", {}, src));
      }
    }
  }

  function mermaidBlock(source) {
    const el = h("div", { class: "mermaid diagram", "data-source": source });
    el.textContent = source;
    return el;
  }

  // ---------- Markdown ----------

  if (window.marked) {
    const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
    // Raw HTML in a document body is shown as text, never parsed.
    window.marked.use({ renderer: { html: (token) => esc(token.text || token.raw || "") } });
  }

  function resolveDocPath(fromPath, href) {
    const parts = fromPath.split("/").slice(0, -1);
    for (const seg of href.split(/[?#]/)[0].split("/")) {
      if (seg === "..") parts.pop();
      else if (seg && seg !== ".") parts.push(seg);
    }
    return parts.join("/");
  }

  // Keeps only http(s)/mailto/in-page links, maps relative links to other documents,
  // and turns images into links so the page never fetches anything.
  function sanitizeFragment(frag, doc) {
    frag.querySelectorAll("script, style, iframe, object, embed, link, meta, form").forEach((n) => n.remove());
    frag.querySelectorAll("*").forEach((el) => {
      for (const a of [...el.attributes]) {
        if (/^on/i.test(a.name) || a.name === "style" || a.name === "srcset") el.removeAttribute(a.name);
      }
    });
    frag.querySelectorAll("img").forEach((img) => {
      const alt = img.getAttribute("alt") || "image";
      const link = ext(img.getAttribute("src"), "[image: " + alt + "]");
      img.replaceWith(link || h("span", { class: "muted" }, "[image: " + alt + "]"));
    });
    frag.querySelectorAll("a").forEach((a) => {
      const href = a.getAttribute("href") || "";
      if (safeUrl(href) || /^mailto:/i.test(href)) {
        a.setAttribute("target", "_blank");
        a.setAttribute("rel", "noopener noreferrer");
        return;
      }
      const target = href && !/^[a-z][a-z0-9+.-]*:/i.test(href) && !href.startsWith("#") && resolveDocPath(doc.path, href);
      const linked = target && documents.find((d) => d.path === target);
      if (linked) a.setAttribute("href", docHref(linked));
      else {
        a.removeAttribute("href");
        if (href) a.setAttribute("title", href);
      }
    });
  }

  function renderMarkdown(doc) {
    const body = h("div", { class: "prose" });
    if (!window.marked) {
      body.append(h("pre", {}, doc.body || ""));
      return body;
    }
    const tpl = document.createElement("template"); // inert: nothing in it loads or runs
    tpl.innerHTML = window.marked.parse(doc.body || "");
    sanitizeFragment(tpl.content, doc);
    tpl.content.querySelectorAll("code.language-mermaid").forEach((code) => {
      (code.closest("pre") || code).replaceWith(mermaidBlock(code.textContent));
    });
    body.append(tpl.content);
    return body;
  }

  // ---------- views ----------

  function renderStart() {
    const ordered = documents
      .filter((d) => d.order != null && (d.audience === "all" || d.audience === state.audience))
      .filter((d) => matches(d.title, d.path))
      .sort((a, b) => a.order - b.order || String(a.title).localeCompare(String(b.title)));
    const toggle = h("div", { class: "segmented", role: "group", "aria-label": "Audience" },
      ["engineer", "user"].map((aud) => h("button", {
        type: "button",
        "aria-pressed": String(state.audience === aud),
        onclick: () => { state.audience = aud; render(); }
      }, aud === "engineer" ? "Engineer" : "User")));
    const stats = h("dl", { class: "stats" },
      [["Routes", routes.length], ["Controllers", controllers.length], ["Models", models.length], ["Documents", documents.length]]
        .map(([k, v]) => h("div", {}, h("dt", { class: "cap" }, k), h("dd", {}, v))));
    return [
      pageHeader("Start here", "Read these in order. Documents marked for everyone always show; the toggle adds role-specific ones."),
      h("div", { class: "toolbar" }, label("Audience"), toggle),
      ordered.length
        ? h("ol", { class: "reading" }, ordered.map((d) => h("li", {},
            h("a", { href: docHref(d) }, d.title || d.path),
            h("span", { class: "muted" }, " ", d.kind || "", d.audience !== "all" ? " · " + d.audience : ""))))
        : empty("No ordered documents. Add order: to a document's front matter to list it here."),
      stats
    ];
  }

  function renderDoc(path) {
    const doc = documents.find((d) => d.path === path);
    if (!doc) return [pageHeader("Document not found"), empty(path)];
    const body = renderMarkdown(doc);
    const first = body.firstElementChild;
    const head = first && first.tagName === "H1" ? null : h("h1", {}, doc.title || doc.path);
    const related = (doc.related || []).filter(Boolean);
    return [
      h("p", { class: "crumbs cap" }, h("a", { href: "#/docs" }, "All documents"), " / ", doc.kind || "document"),
      head,
      h("p", { class: "muted" }, h("code", {}, doc.path), " · audience: ", doc.audience || "all"),
      body,
      section("Related code", related.length
        ? h("ul", { class: "plain" }, related.map((n) => h("li", {}, codeLink(n))))
        : empty("None listed. Add related: to the front matter."))
    ];
  }

  // Route key for a controller class, the inverse of Rails routing: API::V1::UsersController -> api/v1/users.
  // Derived from the class name (not by camelizing the route) so custom acronym inflections still match.
  const routeKey = (name) => name.replace(/Controller$/, "").replace(/::/g, "/")
    .replace(/([A-Z]+)([A-Z][a-z])/g, "$1_$2").replace(/([a-z\d])([A-Z])/g, "$1_$2").toLowerCase();

  function filterApplies(f, action) {
    return (!f.only || f.only.includes(action)) && (!f.except || !f.except.includes(action));
  }

  function routeDetail(route, ctrl, action, notes) {
    const filters = ctrl ? (ctrl.filters || []).filter((f) => filterApplies(f, route.action)) : [];
    const docs = ctrl && ctrl.source ? docsAbout(ctrl.source.path) : [];
    return h("div", { class: "detail" },
      notes.length ? h("ul", { class: "plain warn-text" }, notes.map((w) => h("li", {}, w.message))) : null,
      h("div", { class: "detail-grid" },
        h("div", {}, label("Filters"), filters.length
          ? h("ul", { class: "plain" }, filters.map((f) => h("li", {},
              h("code", {}, f.kind + "_action " + f.name), " ", codeLink(f.source, "source"), " ", ext(f.doc_url, "API"))))
          : empty("none")),
        h("div", {}, label("Models referenced"), action && action.models && action.models.length
          ? h("ul", { class: "plain" }, action.models.map((m) => h("li", {}, modelLink(m))))
          : empty("none detected")),
        h("div", {}, label("View"), action && action.view
          ? h("span", {}, h("span", { class: "tag" }, action.view.kind), " ",
              codeLink({ name: action.view.path, path: action.view.path, url: action.view.url }))
          : empty("not resolved")),
        h("div", {}, label("Source"), h("ul", { class: "plain" },
          h("li", {}, "route ", codeLink(route.source)),
          action ? h("li", {}, "action ", codeLink(action.source)) : null,
          ctrl ? h("li", {}, "controller ", codeLink(ctrl.source)) : null)),
        h("div", {}, label("Docs"), h("ul", { class: "plain" },
          docs.map((d) => h("li", {}, h("a", { href: docHref(d) }, d.title || d.path))),
          h("li", {}, ext(route.doc_url, "Rails routing guide"))))));
  }

  function renderRequests() {
    const groups = new Map();
    for (const r of routes) {
      const key = r.controller || "(no controller)";
      if (!groups.has(key)) groups.set(key, []);
      groups.get(key).push(r);
    }
    const out = [pageHeader("Request map", "Every route, grouped by controller. Select a row to see filters, models, view and sources.")];
    const byKey = new Map(controllers.map((c) => [routeKey(c.name), c]));
    let shown = 0;
    for (const [key, rs] of groups) {
      const ctrl = byKey.get(key);
      const className = ctrl ? ctrl.name : key; // missing controller: show the route key; the warning names the class
      const visible = rs.filter((r) => matches(className, key, r.path, r.action, r.name));
      if (!visible.length) continue;
      shown += visible.length;
      const missing = warnings.filter((w) => w.where === "controllers" && w.message.startsWith(key + "#") && /does not exist/.test(w.message));
      const rows = visible.flatMap((r, i) => {
        const action = ctrl && (ctrl.actions || []).find((a) => a.name === r.action);
        const notes = warnings.filter((w) => w.where === "controllers" &&
          (w.message.startsWith(key + "#" + r.action + ":") || w.message.startsWith(className + "#" + r.action + ":")));
        const id = "rd-" + encodeURIComponent(key).replace(/%/g, "") + "-" + i;
        const detail = h("tr", { class: "detail-row", id, hidden: true }, h("td", { colspan: "5" }, routeDetail(r, ctrl, action, notes)));
        const btn = h("button", { type: "button", class: "row-toggle", "aria-expanded": "false", "aria-controls": id,
          onclick: () => { const open = detail.hidden; detail.hidden = !open; btn.setAttribute("aria-expanded", String(open)); } },
          h("span", { class: "chev", "aria-hidden": "true" }, "▸"), " ", r.action || "?");
        return [h("tr", { class: notes.length ? "has-warn" : "" },
          h("td", {}, btn),
          h("td", {}, h("span", { class: "verb" }, r.verb || "")),
          h("td", {}, h("code", {}, r.path)),
          h("td", { class: "muted" }, r.name || ""),
          h("td", { class: "num" }, notes.length ? h("span", { class: "warn-text", title: notes.map((w) => w.message).join("\n") }, "⚠ " + notes.length) : "")), detail];
      });
      out.push(h("section", { class: "group" },
        h("h2", { class: "group-head" }, h("code", {}, className), " ",
          engineTag(rs), ctrl ? codeLink(ctrl.source, "source") : null),
        missing.map((w) => h("p", { class: "warn-text inline-warn" }, "⚠ ", w.message)),
        table(["Action", "Verb", "Path", "Name", ""], rows, "routes")));
    }
    if (!shown) out.push(empty(routes.length ? "No routes match the filter." : "No routes collected."));
    return out;
  }

  function engineTag(rs) {
    const engine = rs.find((r) => r.engine);
    return engine ? h("span", { class: "tag" }, engine.engine) : null;
  }

  // Mermaid erDiagram identifiers allow letters, digits, _ and -; namespaces become __.
  const ident = (s) => { const v = String(s).replace(/::/g, "__").replace(/[^A-Za-z0-9_-]/g, "_"); return /^[A-Za-z_]/.test(v) ? v : "_" + v; };

  function erSource(ms) {
    const names = new Set(ms.map((m) => m.name));
    const lines = ["erDiagram"];
    for (const m of ms) {
      const cols = m.columns || [];
      if (!cols.length) { lines.push("  " + ident(m.name)); continue; }
      lines.push("  " + ident(m.name) + " {");
      for (const c of cols) lines.push("    " + ident(c.type || "unknown") + " " + ident(c.name));
      lines.push("  }");
    }
    for (const m of ms) {
      for (const a of m.associations || []) {
        if (a.macro === "belongs_to" && a.class_name && names.has(a.class_name)) {
          lines.push("  " + ident(a.class_name) + " ||--o{ " + ident(m.name) + " : \"" + String(a.name).replace(/"/g, "'") + "\"");
        }
      }
    }
    return lines.join("\n");
  }

  function modelSection(m) {
    const docs = docsAbout(m.source && m.source.path);
    const assoc = m.associations || [], vals = m.validations || [], cbs = m.callbacks || [], cols = m.columns || [], idx = m.indexes || [];
    return h("section", { class: "model", id: "model-" + ident(m.name) },
      h("h2", {}, m.name, " ", h("span", { class: "muted" }, "table ", h("code", {}, m.table || "?"), " · db ", m.database || "?")),
      h("p", {}, codeLink(m.source, "source")),
      h("div", { class: "model-grid" },
        h("div", {},
          section("Associations", assoc.length ? h("ul", { class: "plain" }, assoc.map((a) => h("li", {},
            h("code", {}, a.macro + " :" + a.name), " → ", modelLink(a.class_name || "?"),
            a.through ? " through " + a.through : "", a.dependent ? " · dependent " + a.dependent : "", " ", ext(a.doc_url, "API")))) : empty("none")),
          section("Validations", vals.length ? h("ul", { class: "plain" }, vals.map((v) => h("li", {},
            h("code", {}, v.kind), " ", (v.attributes || []).join(", "),
            v.options && Object.keys(v.options).length ? h("span", { class: "muted" }, " " + JSON.stringify(v.options)) : "", " ", ext(v.doc_url, "API")))) : empty("none")),
          section("Callbacks", cbs.length ? h("ul", { class: "plain" }, cbs.map((c) => h("li", {},
            h("code", {}, c.kind + "_" + c.event), " ", codeLink(c.source, c.name), " ", ext(c.doc_url, "Guide")))) : empty("none"))),
        h("div", {},
          section("Columns", cols.length ? table(["Name", "Type", "Null", "Default"], cols.map((c) => h("tr", {},
            h("td", {}, h("code", {}, c.name)), h("td", {}, c.type), h("td", {}, c.null ? "yes" : "no"),
            h("td", { class: "num" }, c.default == null ? "" : String(c.default))))) : empty("none")),
          section("Indexes", idx.length ? table(["Name", "Columns", "Unique"], idx.map((i) => h("tr", {},
            h("td", {}, h("code", {}, i.name)), h("td", {}, (i.columns || []).join(", ")), h("td", {}, i.unique ? "yes" : "no")))) : empty("none")),
          h("aside", { class: "about" }, h("h3", { class: "cap" }, "Documents about this"),
            docs.length ? docList(docs) : empty("None. Reference this model's file in a document's related: list.")))));
  }

  function renderDomain(focus) {
    const ms = models.filter((m) => matches(m.name, m.table));
    const out = [pageHeader("Domain model", "Entities with their columns; lines are belongs_to relations.")];
    if (!ms.length) return out.concat(empty(models.length ? "No models match the filter." : "No models collected."));
    out.push(h("nav", { class: "chips", "aria-label": "Models" }, ms.map((m) => h("a", { href: modelHref(m.name) }, m.name))));
    out.push(mermaidBlock(erSource(ms)));
    out.push(...ms.map(modelSection));
    if (focus) setTimeout(() => { const t = document.getElementById("model-" + ident(focus)); if (t) t.scrollIntoView(); }, 0);
    return out;
  }

  function renderDatabases() {
    const envs = new Map();
    for (const d of databases) {
      if (!matches(d.name, d.adapter, d.database, d.env, ...(d.models || []))) continue;
      if (!envs.has(d.env)) envs.set(d.env, []);
      envs.get(d.env).push(d);
    }
    const out = [pageHeader("Databases", "From config/database.yml, per environment. Credentials are never collected.")];
    if (!envs.size) return out.concat(empty(databases.length ? "No databases match the filter." : "No databases collected."));
    for (const [env, ds] of envs) {
      out.push(h("section", { class: "group" }, h("h2", { class: "cap env" }, env),
        h("div", { class: "cards" }, ds.map((d) => {
          const gl = d.gem_links || {};
          const gemLinks = [["homepage", "Homepage"], ["documentation_uri", "Docs"], ["source_code_uri", "Source"], ["changelog_uri", "Changelog"], ["rubygems", "RubyGems"], ["rubydoc", "RubyDoc"]]
            .map(([k, t]) => ext(gl[k], t)).filter(Boolean);
          return h("article", { class: "card" },
            h("h3", {}, d.name, d.replica ? h("span", { class: "tag" }, "replica") : null, d.solid_component ? h("span", { class: "tag" }, d.solid_component) : null),
            h("dl", { class: "kv" },
              h("dt", { class: "cap" }, "Adapter"), h("dd", {}, d.adapter || "unknown"),
              h("dt", { class: "cap" }, "Database"), h("dd", {}, d.database ? h("code", {}, d.database) : h("span", { class: "muted" }, "not set")),
              h("dt", { class: "cap" }, "Solid"), h("dd", {}, d.solid_component || h("span", { class: "muted" }, "none")),
              d.migrations_paths ? [h("dt", { class: "cap" }, "Migrations"), h("dd", {}, h("code", {}, [].concat(d.migrations_paths).join(", ")))] : null,
              h("dt", { class: "cap" }, "Models"), h("dd", {}, (d.models || []).length
                ? (d.models || []).flatMap((m, i) => [i ? ", " : null, modelLink(m)])
                : h("span", { class: "muted" }, "none"))),
            h("p", { class: "links" }, ext(d.doc_url, "Multiple databases guide"), gemLinks.length ? [" · ", gemLinks.flatMap((l, i) => [i ? " · " : null, l])] : null));
        }))));
    }
    return out;
  }

  function renderDocs() {
    const docs = documents.filter((d) => matches(d.title, d.path, d.kind)).slice().sort((a, b) => a.path.localeCompare(b.path));
    return [
      pageHeader("All documents", documents.length + " Markdown files from the configured docs folders."),
      docs.length ? table(["Title", "Kind", "Audience", "Path"], docs.map((d) => h("tr", {},
        h("td", {}, h("a", { href: docHref(d) }, d.title || d.path), d.has_mermaid ? h("span", { class: "tag" }, "diagram") : null),
        h("td", {}, d.kind || ""), h("td", {}, d.audience || "all"), h("td", {}, h("code", { class: "muted" }, d.path)))))
        : empty(documents.length ? "No documents match the filter." : "No documents collected.")
    ];
  }

  // ---------- chrome: nav, footer, banner ----------

  function renderNav(active) {
    document.getElementById("nav").replaceChildren(...NAV.map(([id, text]) =>
      h("li", {}, h("a", { href: "#/" + id, "aria-current": active === id ? "page" : null }, text))));
  }

  function renderFooter() {
    const repo = meta.repo || {};
    const when = meta.generated_at ? new Date(meta.generated_at) : null;
    document.getElementById("footer").replaceChildren(
      h("span", {}, meta.app_name || "app"),
      h("span", {}, "Rails ", meta.rails_version || "?"),
      h("span", { title: meta.generated_at || "" }, "Generated ", when && !isNaN(when) ? when.toLocaleString() : "unknown"),
      h("span", {}, "Commit ", repo.sha ? h("code", { title: repo.sha }, repo.sha.slice(0, 12)) : "none", repo.dirty ? " (dirty)" : ""));
  }

  function renderBanner() {
    const repo = meta.repo || {};
    const el = document.getElementById("banner");
    if (!repo.dirty && !warnings.length) return el.remove();
    const parts = [];
    if (repo.dirty) parts.push("Working tree has uncommitted changes");
    if (warnings.length) parts.push(warnings.length + (warnings.length === 1 ? " warning" : " warnings"));
    el.className = "banner";
    el.setAttribute("role", "status");
    el.append(h("details", {},
      h("summary", {}, "⚠ ", parts.join(" · ")),
      h("ul", { class: "plain" }, warnings.map((w) => h("li", {}, h("span", { class: "tag" }, w.where), " ", w.message)))));
  }

  // ---------- routing ----------

  function render() {
    const raw = location.hash.replace(/^#\/?/, "");
    const [view, ...rest] = raw.split("/");
    const arg = rest.length ? decodeURIComponent(rest.join("/")) : null;
    let nodes, active = view;
    switch (view) {
      case "requests": nodes = renderRequests(); break;
      case "domain": nodes = renderDomain(arg); break;
      case "databases": nodes = renderDatabases(); break;
      case "docs": nodes = renderDocs(); break;
      case "doc": nodes = renderDoc(arg); active = "docs"; break;
      default: nodes = renderStart(); active = "start";
    }
    renderNav(active);
    main.replaceChildren(...[].concat(nodes).flat(Infinity).filter(Boolean));
    renderMermaid([...main.querySelectorAll(".mermaid")]);
  }

  document.getElementById("app-name").textContent = meta.app_name || "rails_vis";
  document.title = (meta.app_name || "rails_vis") + " · rails_vis";
  const search = document.getElementById("search");
  search.addEventListener("input", () => { state.query = search.value.trim().toLowerCase(); render(); });
  const toggle = document.querySelector(".nav-toggle");
  const sidebar = document.getElementById("sidebar");
  toggle.addEventListener("click", () => {
    const open = sidebar.classList.toggle("open");
    toggle.setAttribute("aria-expanded", String(open));
  });
  window.addEventListener("hashchange", () => {
    // Only #/... hashes are routes. Anything else (the skip link #main, an in-page anchor) keeps the current view.
    if (!location.hash.startsWith("#/")) {
      const target = document.getElementById(decodeURIComponent(location.hash.slice(1))) || main;
      if (!target.hasAttribute("tabindex")) target.setAttribute("tabindex", "-1");
      target.focus();
      return;
    }
    sidebar.classList.remove("open");
    toggle.setAttribute("aria-expanded", "false");
    render();
    main.focus({ preventScroll: true });
    window.scrollTo(0, 0);
  });
  renderFooter();
  renderBanner();
  render();
})();
