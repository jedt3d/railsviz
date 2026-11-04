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
  const middleware = list("middleware");
  const gems = list("gems");
  const pages = list("pages");
  const layouts = list("layouts");
  const hash = (key) => DATA[key] && typeof DATA[key] === "object" && !Array.isArray(DATA[key]) ? DATA[key] : {};
  const boot = hash("boot");
  const entry = hash("entry_points");
  const entryList = (key) => Array.isArray(entry[key]) ? entry[key] : [];

  // id, label, icon, count shown in the sidebar
  const NAV = [
    ["start", "Start here", "i-start", null],
    ["requests", "Request map", "i-route", routes.length],
    ["flow", "Page flow", "i-flow", () => flowGraph().nodes.size],
    ["domain", "Domain model", "i-model", models.length],
    ["databases", "Databases", "i-db", databases.length],
    ["boot", "Boot", "i-boot", null],
    ["middleware", "Middleware", "i-stack", middleware.length],
    ["entry", "Entry points", "i-bolt", ["jobs", "mailers", "channels", "rake_tasks"].reduce((s, k) => s + entryList(k).length, 0)],
    ["gems", "Gems", "i-gem", gems.length],
    ["docs", "Documents", "i-doc", documents.length]
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

  // An icon from the sprite in index.html; decorative unless a label is given.
  function icon(id, cls, title) {
    const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    svg.setAttribute("class", "icon" + (cls ? " " + cls : ""));
    if (title) { svg.setAttribute("role", "img"); svg.setAttribute("aria-label", title); } else svg.setAttribute("aria-hidden", "true");
    const use = document.createElementNS("http://www.w3.org/2000/svg", "use");
    use.setAttribute("href", "#" + id);
    svg.append(use);
    return svg;
  }

  function safeUrl(url) {
    return typeof url === "string" && /^https?:\/\//i.test(url) ? url : null;
  }

  function ext(url, text) {
    const href = safeUrl(url);
    return href ? h("a", { href, class: "ext", target: "_blank", rel: "noopener noreferrer" }, text, icon("i-ext")) : null;
  }

  // A code node { name, path, line, url }: GitHub link when url is set, else the path as text.
  function codeLink(node, label) {
    if (!node) return h("span", { class: "muted" }, "no source");
    // Gem code: no repository path or line, only a link to the gem.
    if (node.path == null) {
      const text = label || node.name;
      return h("span", { class: "code-node" }, ext(node.url, text) || h("span", {}, text), " ", h("span", { class: "tag tag--out" }, "gem"));
    }
    const where = node.path + (node.line ? ":" + node.line : "");
    const name = label || node.name || where;
    const path = name === node.path || name === where ? null : [" ", h("code", { class: "muted" }, where)];
    return h("span", { class: "code-node" }, ext(node.url, name) || h("span", {}, name), path);
  }

  const matches = (...names) => !state.query || names.some((n) => n && String(n).toLowerCase().includes(state.query));
  const label = (text) => h("div", { class: "label" }, text);
  const empty = (text) => h("p", { class: "empty" }, text);
  const docHref = (doc) => "#/doc/" + encodeURIComponent(doc.path);
  const modelHref = (name) => "#/domain/" + encodeURIComponent(name);
  const modelNames = new Set(models.map((m) => m.name));
  const search = document.getElementById("search");

  // Nothing matched the filter, or nothing was collected: what is empty, why, and the one action that fills it.
  function emptyState(kind, collected) {
    if (!collected) return h("div", { class: "empty-state" }, h("p", {}, "No " + kind + " collected."), h("p", {}, "Run bin/rails rails_vis:dump in the app to fill this view."));
    return h("div", { class: "empty-state" },
      h("p", {}, "No " + kind + " match “" + state.query + "”."),
      h("button", { type: "button", class: "btn", onclick: () => { search.value = ""; state.query = ""; render(); } }, "Clear the filter"));
  }

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
    return h("section", { class: "block" }, h("h3", {}, title), body);
  }

  function table(head, rows, cls, cols) {
    return h("div", { class: "table-wrap" },
      h("table", { class: cls || "" },
        cols ? h("colgroup", {}, cols.map(([c, w]) => h("col", { class: "c-" + c, style: w ? "width:" + w : null }))) : null,
        h("thead", {}, h("tr", {}, head.map((t) => h("th", { scope: "col" }, t)))),
        h("tbody", {}, rows)));
  }

  function pageHeader(title, sub) {
    return h("header", { class: "page-head" }, h("h1", {}, title), sub ? h("p", {}, sub) : null);
  }

  // Script of a text, for the per-language faces: Thai and Japanese documents take their own line-height and family.
  function langOf(text) {
    const s = String(text || "").slice(0, 4000);
    const th = (s.match(/[฀-๿]/g) || []).length;
    const ja = (s.match(/[぀-ヿ一-鿿]/g) || []).length;
    if (th > 20 && th >= ja) return "th";
    if (ja > 20) return "ja";
    return null;
  }

  // ---------- colour mode ----------

  const root = document.documentElement;
  const modeBtn = document.getElementById("mode");
  const osDark = window.matchMedia ? window.matchMedia("(prefers-color-scheme: dark)") : null;
  const effectiveMode = () => root.dataset.mode || (osDark && osDark.matches ? "dark" : "light");

  function syncModeButton() {
    const dark = effectiveMode() === "dark";
    modeBtn.setAttribute("aria-pressed", String(dark));
    modeBtn.setAttribute("aria-label", dark ? "Switch to light mode" : "Switch to dark mode");
  }

  function initMermaid() {
    if (!window.mermaid) return;
    const dark = effectiveMode() === "dark";
    const font = getComputedStyle(document.body).fontFamily;
    window.mermaid.initialize({
      startOnLoad: false, securityLevel: "strict", theme: dark ? "dark" : "neutral", maxTextSize: 500000,
      themeVariables: { fontFamily: font, fontSize: "14px" }
    });
  }

  modeBtn.addEventListener("click", () => {
    const next = effectiveMode() === "dark" ? "light" : "dark";
    root.dataset.mode = next;
    try { localStorage.setItem("rails_vis_mode", next); } catch (_) { /* private mode: the choice lasts this page only */ }
    syncModeButton();
    initMermaid();
    render(); // diagrams re-render in the new theme
  });
  if (osDark) osDark.addEventListener("change", () => { if (!root.dataset.mode) { syncModeButton(); initMermaid(); render(); } });
  syncModeButton();
  initMermaid();

  // ---------- diagrams: Mermaid in a viewer (fit all, zoom, pan, full screen) ----------

  async function renderMermaid(nodes) {
    if (!nodes.length) return;
    if (!window.mermaid) return nodes.forEach((n) => n.classList.add("mermaid-error"));
    for (const node of nodes) {
      try {
        await window.mermaid.run({ nodes: [node] });
        viewerize(node);
      } catch (e) {
        const src = node.dataset.source || "";
        node.replaceChildren(h("div", { class: "diagram-error" },
          h("p", {}, "The diagram could not be drawn: " + (e && e.message ? e.message : e) + ". Check the Mermaid source below."), h("pre", {}, src)));
      }
    }
  }

  function mermaidBlock(source) {
    const el = h("div", { class: "mermaid", "data-source": source });
    el.textContent = source;
    return el;
  }

  // Wraps a rendered diagram: wheel zooms at the cursor, drag or space-and-move pans, buttons zoom, fit and go full screen.
  function viewerize(node) {
    const svg = node.querySelector("svg");
    if (!svg) return;
    const box = h("div", { class: "diagram", tabindex: "0", role: "group", "aria-label": "Diagram viewer" });
    node.replaceWith(box);
    box.append(node);
    const vb = svg.viewBox && svg.viewBox.baseVal;
    const w = vb && vb.width ? vb.width : svg.getBoundingClientRect().width || 800;
    const hh = vb && vb.height ? vb.height : svg.getBoundingClientRect().height || 400;
    svg.setAttribute("width", w); svg.setAttribute("height", hh); svg.style.maxWidth = "none";
    const t = { s: 1, x: 0, y: 0 };
    const apply = () => { svg.style.transform = "translate(" + t.x + "px, " + t.y + "px) scale(" + t.s + ")"; };
    const fit = () => {
      const r = box.getBoundingClientRect();
      t.s = Math.max(0.05, Math.min(r.width / w, r.height / hh) * 0.92);
      t.x = (r.width - w * t.s) / 2; t.y = (r.height - hh * t.s) / 2;
      apply();
    };
    const zoom = (f, cx, cy) => {
      const r = box.getBoundingClientRect();
      const px = cx == null ? r.width / 2 : cx, py = cy == null ? r.height / 2 : cy;
      const ns = Math.min(8, Math.max(0.05, t.s * f));
      t.x = px - (px - t.x) * (ns / t.s); t.y = py - (py - t.y) * (ns / t.s); t.s = ns;
      apply();
    };
    const btn = (id, title, fn) => h("button", { type: "button", class: "icon-btn", "aria-label": title, title, onclick: fn }, icon(id));
    const full = btn("i-expand", "Full screen", () => {
      if (document.fullscreenElement === box) document.exitFullscreen();
      else if (box.requestFullscreen) box.requestFullscreen();
      else { box.classList.toggle("viewer-max"); setFullIcon(box.classList.contains("viewer-max")); setTimeout(fit, 0); }
    });
    const setFullIcon = (on) => {
      full.replaceChildren(icon(on ? "i-collapse" : "i-expand"));
      full.setAttribute("aria-label", on ? "Exit full screen" : "Full screen"); full.title = full.getAttribute("aria-label");
    };
    box.addEventListener("fullscreenchange", () => { setFullIcon(document.fullscreenElement === box); setTimeout(fit, 0); });
    box.append(h("div", { class: "viewer-bar" },
      btn("i-zoom-in", "Zoom in", () => zoom(1.25)), btn("i-zoom-out", "Zoom out", () => zoom(0.8)), btn("i-fit", "Fit the whole diagram", fit), full),
      h("span", { class: "viewer-hint" }, "Click the diagram, then scroll to zoom; drag to pan; space and move to pan"));
    const engaged = () => document.activeElement === box || box.contains(document.activeElement) || document.fullscreenElement === box || box.classList.contains("viewer-max");
    box.addEventListener("wheel", (e) => {
      if (!(engaged() || e.ctrlKey || e.metaKey)) return;
      e.preventDefault();
      const r = box.getBoundingClientRect();
      zoom(e.deltaY < 0 ? 1.1 : 0.9, e.clientX - r.left, e.clientY - r.top);
    }, { passive: false });
    let drag = null;
    box.addEventListener("pointerdown", (e) => {
      if (e.button !== 0 || e.target.closest(".viewer-bar")) return;
      box.focus({ preventScroll: true });
      drag = { x: e.clientX - t.x, y: e.clientY - t.y }; box.classList.add("dragging"); box.setPointerCapture(e.pointerId);
    });
    box.addEventListener("pointermove", (e) => {
      if (drag) { t.x = e.clientX - drag.x; t.y = e.clientY - drag.y; apply(); return; }
      if (space && last) { t.x += e.clientX - last.x; t.y += e.clientY - last.y; apply(); }
      last = { x: e.clientX, y: e.clientY };
    });
    const endDrag = () => { drag = null; box.classList.remove("dragging"); };
    box.addEventListener("pointerup", endDrag); box.addEventListener("pointercancel", endDrag);
    let space = false, last = null; // hold the space bar and move the cursor to pan, the design-tool convention
    box.addEventListener("keydown", (e) => {
      if (e.key === " " && !space) { space = true; box.classList.add("space-pan"); e.preventDefault(); }
      if (e.key === "+" || e.key === "=") zoom(1.25);
      if (e.key === "-") zoom(0.8);
      if (e.key === "0") fit();
    });
    box.addEventListener("keyup", (e) => { if (e.key === " ") { space = false; box.classList.remove("space-pan"); } });
    box.addEventListener("pointerleave", () => { last = null; });
    if (window.ResizeObserver) new ResizeObserver(fit).observe(box);
    fit();
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
    const lang = langOf(doc.body);
    const body = h("div", { class: "prose", lang });
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

  // ---------- charts: bars and one stacked bar, drawn from the data ----------

  function barChart(rows, cls) {
    const max = Math.max(1, ...rows.map((r) => r.value));
    return h("div", { class: "bars", role: "list" }, rows.map((r) => h("div", { class: "bar-row", role: "listitem" },
      r.href ? h("a", { href: r.href, title: r.label }, r.label) : h("span", { title: r.label }, r.label),
      h("div", { class: "bar", "aria-hidden": "true" }, h("div", { class: "bar-fill" + (cls ? " " + cls : ""), style: "width:" + (100 * r.value / max).toFixed(1) + "%" })),
      h("span", { class: "num" }, r.value))));
  }

  function stackedBar(parts) {
    const total = parts.reduce((s, p) => s + p.value, 0) || 1;
    return [
      h("div", { class: "stack", "aria-hidden": "true" }, parts.map((p, i) => h("span", { class: "ramp-" + (i % 5 + 1), style: "width:" + (100 * p.value / total).toFixed(1) + "%", title: p.label + ": " + p.value }))),
      h("ul", { class: "legend" }, parts.map((p, i) => h("li", {}, h("span", { class: "swatch ramp-" + (i % 5 + 1), "aria-hidden": "true" }), p.label, " ", h("span", { class: "num muted" }, p.value))))
    ];
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
      [["Routes", routes.length, "i-route", "route"], ["Controllers", controllers.length, "i-ctrl", "route"], ["Models", models.length, "i-model", "model"],
       ["Databases", databases.length, "i-db", "db"], ["Documents", documents.length, "i-doc", "doc"], ["Gems", gems.length, "i-gem", "doc"], ["Warnings", warnings.length, "i-warn", "warn"]]
        .map(([k, v, ic, role]) => h("div", { class: "stat stat--" + role }, h("dt", {}, icon(ic), k), h("dd", {}, v))));
    // Routes per controller: the shape of the app, the eight busiest named, the rest summed.
    const perCtrl = new Map();
    for (const r of routes) { const k = r.redirect ? "(redirects)" : (r.controller || "(no controller)"); perCtrl.set(k, (perCtrl.get(k) || 0) + 1); }
    const sorted = [...perCtrl].sort((a, b) => b[1] - a[1]);
    const top = sorted.slice(0, 8).map(([k, v]) => ({ label: k, value: v, href: "#/requests/" + encodeURIComponent(k) }));
    const rest = sorted.slice(8).reduce((s, [, v]) => s + v, 0);
    if (rest) top.push({ label: sorted.length - 8 + " more controllers", value: rest, href: "#/requests" });
    const perDb = new Map();
    for (const m of models) perDb.set(m.database || "primary", (perDb.get(m.database || "primary") || 0) + 1);
    const dbParts = [...perDb].sort((a, b) => b[1] - a[1]).map(([k, v]) => ({ label: k, value: v }));
    return [
      pageHeader("Start here", "What " + (meta.app_name || "this app") + " is made of, and the documents to read first."),
      h("div", { class: "overview" },
        h("div", {},
          stats,
          routes.length ? h("section", { class: "chart" }, h("h2", {}, "Routes per controller"), h("p", { class: "chart-sub" }, "Where the requests land. Every bar opens its controller in the request map."), barChart(top)) : null),
        h("div", {},
          h("h2", {}, "Read in this order"),
          h("p", { class: "chart-sub" }, "Documents marked for everyone always show; the switch adds the role-specific ones."),
          h("div", { class: "toolbar" }, label("Audience"), toggle),
          ordered.length
            ? h("ol", { class: "reading" }, ordered.map((d) => h("li", {},
                h("a", { href: docHref(d) }, d.title || d.path),
                h("span", { class: "tag tag--doc" }, d.kind || "document", d.audience !== "all" ? " for " + d.audience : ""))))
            : h("div", { class: "empty-state" }, h("p", {}, "No ordered documents yet."), h("p", {}, "Add order: to a document’s front matter, or list it under start_here in config/rails_vis.yml, and it appears here.")),
          models.length ? h("section", { class: "chart" }, h("h2", {}, "Models per database"), stackedBar(dbParts)) : null))
    ];
  }

  function renderDoc(path) {
    const doc = documents.find((d) => d.path === path);
    if (!doc) return [pageHeader("Document not found"), empty(path)];
    const body = renderMarkdown(doc);
    const first = body.firstElementChild;
    const own = first && first.tagName === "H1" ? first : null; // a document's own H1 becomes the page title
    if (own) own.remove();
    const head = own || h("h1", { lang: body.getAttribute("lang") }, doc.title || doc.path);
    const related = (doc.related || []).filter(Boolean);
    return [
      h("p", { class: "crumbs" }, h("a", { href: "#/docs" }, "Documents"), icon("i-chev"), h("span", {}, doc.title || doc.path)),
      head,
      h("p", { class: "doc-meta" }, h("span", { class: "tag tag--doc" }, doc.kind || "document"), h("code", {}, doc.path), h("span", {}, "audience: " + (doc.audience || "all"))),
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

  function verbPill(verb) {
    const v = String(verb || "").toUpperCase();
    const cls = v === "DELETE" ? " verb--delete" : /^(POST|PUT|PATCH)$/.test(v) ? " verb--write" : "";
    return h("span", { class: "verb" + cls }, v);
  }

  function routeDetail(route, ctrl, action, notes) {
    const filters = ctrl ? (ctrl.filters || []).filter((f) => filterApplies(f, route.action)) : [];
    const docs = ctrl && ctrl.source ? docsAbout(ctrl.source.path) : [];
    return h("div", { class: "detail" },
      notes.length ? h("ul", { class: "plain warn-text warn-list" }, notes.map((w) => h("li", { class: "inline-warn" }, icon("i-warn"), w.message))) : null,
      h("div", { class: "detail-grid" },
        h("div", {}, label("Filters"), filters.length
          ? h("ul", { class: "plain" }, filters.map((f) => h("li", {},
              h("code", {}, f.kind + "_action " + f.name), " ", codeLink(f.source, "source"), " ", ext(f.doc_url, "API"))))
          : empty("none")),
        h("div", {}, label("Models referenced"), action && action.models && action.models.length
          ? h("ul", { class: "plain" }, action.models.map((m) => h("li", {}, modelLink(m))))
          : empty("none detected")),
        h("div", {}, label("View"), route.redirect ? empty("redirect") : action && action.view
          ? h("span", {}, h("span", { class: "tag tag--out" }, action.view.kind), " ",
              codeLink({ name: action.view.path, path: action.view.path, url: action.view.url }))
          : empty("not resolved")),
        h("div", {}, label("Source"), h("ul", { class: "plain" },
          route.name ? h("li", {}, "name ", h("code", {}, route.name)) : null,
          h("li", {}, "route ", codeLink(route.source)),
          !route.redirect && action ? h("li", {}, "action ", codeLink(action.source)) : null,
          !route.redirect && ctrl ? h("li", {}, "controller ", codeLink(ctrl.source)) : null)),
        h("div", {}, label("Docs"), h("ul", { class: "plain" },
          docs.map((d) => h("li", {}, h("a", { href: docHref(d) }, d.title || d.path))),
          h("li", {}, ext(route.doc_url, "Rails routing guide"))))));
  }

  const groupId = (key) => "g-" + encodeURIComponent(key).replace(/%/g, "");

  function renderRequests(focus) {
    const groups = new Map();
    for (const r of routes) {
      const key = r.redirect ? "(redirects)" : (r.controller || "(no controller)");
      if (!groups.has(key)) groups.set(key, []);
      groups.get(key).push(r);
    }
    const out = [pageHeader("Request map", "Every route, grouped by the controller that answers it. Open a row for its filters, models, view and source lines.")];
    const byKey = new Map(controllers.map((c) => [routeKey(c.name), c]));
    let shown = 0;
    for (const [key, rs] of groups) {
      const ctrl = byKey.get(key);
      const className = ctrl ? ctrl.name : key; // missing controller: show the route key; the warning names the class
      const visible = rs.filter((r) => matches(className, key, r.path, r.action, r.name, r.redirect && r.redirect.to));
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
          icon("i-chev", "chev"), r.redirect ? h("span", { class: "tag tag--route" }, "redirect " + r.redirect.status) : (r.action || "?"));
        return [h("tr", { class: notes.length ? "has-warn" : "" },
          h("td", {}, btn),
          h("td", {}, verbPill(r.verb)),
          h("td", {}, h("code", {}, r.path), r.redirect ? h("div", { class: "muted" }, "to ", h("code", {}, r.redirect.to || "a computed path")) : null),
          h("td", { class: "muted" }, r.name || ""),
          h("td", { class: "num" }, notes.length ? h("span", { class: "warn-text", title: notes.map((w) => w.message).join("\n") }, icon("i-warn", "", notes.length + " warnings"), " " + notes.length) : "")), detail];
      });
      out.push(h("section", { class: "group", id: groupId(key) },
        h("h2", { class: "group-head" }, className, " ",
          engineTag(rs), ctrl ? codeLink(ctrl.source, "source") : null),
        missing.map((w) => h("p", { class: "warn-text inline-warn" }, icon("i-warn"), w.message)),
        table(["Action", "Verb", "Path", "Name", ""], rows, "routes", [["action", "30%"], ["verb", "6rem"], ["path", null], ["name", "20%"], ["warn", "3.5rem"]])));
    }
    if (!shown) out.push(emptyState("routes", routes.length));
    if (focus) setTimeout(() => { const t = document.getElementById(groupId(focus)); if (t) t.scrollIntoView(); }, 0);
    return out;
  }

  function engineTag(rs) {
    const engine = rs.find((r) => r.engine);
    return engine ? h("span", { class: "tag tag--out" }, engine.engine) : null;
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
      h("div", { class: "model-head" }, icon("i-model"), h("h2", {}, m.name), codeLink(m.source, "source")),
      h("p", { class: "model-meta" }, h("span", {}, "table ", h("code", {}, m.table || "?")), h("span", {}, "database ", h("span", { class: "tag tag--db" }, m.database || "?"))),
      h("div", { class: "model-grid" },
        h("div", {},
          section("Associations", assoc.length ? h("ul", { class: "plain" }, assoc.map((a) => h("li", {},
            h("code", {}, a.macro + " :" + a.name), " ", modelLink(a.class_name || "?"),
            a.through ? " through " + a.through : "", a.dependent ? ", dependent " + a.dependent : "", " ", ext(a.doc_url, "API")))) : empty("none")),
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
          h("aside", { class: "about" }, h("h3", {}, "Documents about this model"),
            docs.length ? docList(docs) : empty("None. Reference this model’s file in a document’s related: list.")))));
  }

  function renderDomain(focus) {
    const ms = models.filter((m) => matches(m.name, m.table));
    const out = [pageHeader("Domain model", "Every model with its columns; the lines are belongs_to relations.")];
    if (!ms.length) return out.concat(emptyState("models", models.length));
    out.push(h("nav", { class: "chips", "aria-label": "Models" }, ms.map((m) => h("a", { class: "chip", href: modelHref(m.name) }, icon("i-model"), m.name))));
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
    const out = [pageHeader("Databases", "From config/database.yml, one table per environment. Credentials are never collected.")];
    if (!envs.size) return out.concat(emptyState("databases", databases.length));
    for (const [env, ds] of envs) {
      out.push(h("section", { class: "group" }, h("h2", { class: "env-head" }, icon("i-db"), env),
        table(["Name", "Adapter", "Database", "Solid", "Models", "Links"], ds.map((d) => {
          return h("tr", {},
            h("td", {}, h("strong", {}, d.name), " ", d.replica ? h("span", { class: "tag tag--out" }, "replica") : null),
            h("td", {}, d.adapter || "unknown"),
            h("td", {}, d.database ? h("code", {}, d.database) : h("span", { class: "muted" }, "not set"),
              d.migrations_paths ? h("div", { class: "muted" }, "migrations ", h("code", {}, [].concat(d.migrations_paths).join(", "))) : null),
            h("td", {}, d.solid_component ? h("span", { class: "tag tag--db" }, d.solid_component) : h("span", { class: "muted" }, "none")),
            h("td", {}, (d.models || []).length ? (d.models || []).flatMap((m, i) => [i ? ", " : null, modelLink(m)]) : h("span", { class: "muted" }, "none")),
            h("td", {}, h("div", { class: "links" }, ext(d.doc_url, "Guide"), gemLinks(d.gem_links))));
        }))));
    }
    return out;
  }

  function gemLinks(gl) {
    gl = gl || {};
    return [["homepage", "Homepage"], ["documentation_uri", "Docs"], ["source_code_uri", "Source"], ["changelog_uri", "Changelog"], ["rubygems", "RubyGems"], ["rubydoc", "RubyDoc"]]
      .map(([k, t]) => ext(gl[k], t)).filter(Boolean);
  }

  // A ruled section of a view: heading, an optional guide link, then the body.
  function group(title, docUrl, ...body) {
    return h("section", { class: "group" }, h("h2", { class: "group-head" }, title, " ", ext(docUrl, "Guide")), body);
  }

  const muted = (text) => h("span", { class: "muted" }, text);

  function renderBoot() {
    const envs = Array.isArray(boot.environments) ? boot.environments : [];
    const files = Array.isArray(boot.initializer_files) ? boot.initializer_files : [];
    const reads = [[boot.application, "application"], ...envs.map((n) => [n, "environment"]), ...files.map((n) => [n, "initializer"])]
      .filter(([n]) => n && matches(n.name, n.path));
    const apps = (boot.app_initializers || []).filter((i) => matches(i.name, i.railtie));
    const fw = (boot.framework_initializers || []).filter((i) => matches(i.railtie));
    const env = (boot.env_keys || []).filter((k) => matches(k.key));
    const creds = boot.credentials_keys;
    const credWarn = warnings.find((w) => w.where === "boot" && /^credentials/.test(w.message));
    return [
      h("header", { class: "page-head" }, h("h1", {}, "Boot and configuration"),
        h("p", {}, "What Rails reads before the first request, in load order. ", ext(boot.doc_url, "Configuring Rails guide"))),
      group("Read at boot", null, reads.length
        ? h("ol", { class: "reading" }, reads.map(([n, kind]) => h("li", {}, codeLink(n), h("span", { class: "tag tag--out" }, kind))))
        : emptyState("boot files", Object.keys(boot).length)),
      group("Initializers the app defines", null, apps.length
        ? table(["Name", "Railtie", "Source"], apps.map((i) => h("tr", {},
            h("td", {}, h("code", {}, i.name)), h("td", {}, i.railtie), h("td", {}, codeLink(i.source, "source")))))
        : empty("none")),
      group("Framework initializers per railtie", null, fw.length
        ? barChart(fw.map((i) => ({ label: i.railtie, value: i.count, href: safeUrl(i.url) })))
        : empty("none")),
      group("ENV keys read under config/", null, env.length
        ? table(["Key", "Read at"], env.map((k) => h("tr", {},
            h("td", {}, h("code", {}, k.key)),
            h("td", {}, (k.references || []).flatMap((r, i) => [i ? " " : null, codeLink(r, r.path + (r.line ? ":" + r.line : ""))])))))
        : empty("none")),
      group("Credentials keys", null, Array.isArray(creds)
        ? (creds.length ? h("ul", { class: "plain links" }, creds.map((k) => h("li", {}, h("code", {}, k)))) : empty("none"))
        : h("p", { class: "warn-text inline-warn" }, icon("i-warn"), credWarn ? credWarn.message : "Credential keys were not collected."))
    ];
  }

  function renderMiddleware() {
    const rows = middleware.map((m, i) => [m, i + 1]).filter(([m]) => matches(m.name, m.gem && m.gem.name));
    return [
      h("header", { class: "page-head" }, h("h1", {}, "Middleware stack"),
        h("p", {}, "Requests pass top to bottom. ", ext(middleware.length ? middleware[0].doc_url : null, "Rails on Rack guide"))),
      rows.length
        ? table(["#", "Middleware", "From", "Source"], rows.map(([m, n]) => h("tr", {},
            h("td", { class: "num" }, n),
            h("td", {}, h("code", {}, m.name)),
            h("td", {}, m.gem ? h("span", { class: "tag tag--out" }, m.gem.name + " " + m.gem.version) : h("span", { class: "tag tag--accent" }, "this app")),
            h("td", {}, !m.source ? muted("no source") : m.source.path == null ? ext(m.source.url, "source") : codeLink(m.source, "source")))), "", [["n", "3rem"], ["name", null], ["from", null], ["source", null]])
        : emptyState("middleware", middleware.length)
    ];
  }

  function renderEntry() {
    const pick = (key, ...fields) => entryList(key).filter((r) => matches(...fields.map((f) => r[f])));
    const guide = (key) => (entryList(key)[0] || {}).doc_url;
    const jobs = pick("jobs", "name", "queue");
    const recurring = pick("recurring", "name", "class", "command", "env");
    const mailers = entryList("mailers").flatMap((m) => (m.actions || []).map((a) => [m, a])).filter(([m, a]) => matches(m.name, a.name));
    const channels = pick("channels", "name");
    const tasks = pick("rake_tasks", "name", "comment");
    const src = (n) => codeLink(n, "source");
    return [
      pageHeader("Entry points", "Work that starts outside a request. Queue adapter: " + (entry.queue_adapter || "unknown") + "."),
      group("Jobs", guide("jobs"), jobs.length
        ? table(["Name", "Queue", "Source"], jobs.map((j) => h("tr", {},
            h("td", {}, h("code", {}, j.name)), h("td", {}, j.queue ? h("span", { class: "tag tag--out" }, j.queue) : muted("default")), h("td", {}, src(j.source)))))
        : empty("none")),
      group("Recurring tasks", null, recurring.length
        ? table(["Env", "Name", "Runs", "Queue", "Schedule", "Source"], recurring.map((r) => h("tr", {},
            h("td", {}, r.env), h("td", {}, h("code", {}, r.name)), h("td", {}, h("code", {}, r.class || r.command || "?")),
            h("td", {}, r.queue || muted("default")), h("td", {}, r.schedule), h("td", {}, src(r.source)))))
        : empty("none")),
      group("Mailers", guide("mailers"), mailers.length
        ? table(["Mailer", "Action", "Templates", "Source"], mailers.map(([m, a]) => h("tr", {},
            h("td", {}, h("code", {}, m.name)), h("td", {}, h("code", {}, a.name)),
            h("td", {}, (a.templates || []).length ? a.templates.flatMap((t, i) => [i ? " " : null, codeLink(t)]) : muted("none")),
            h("td", {}, src(a.source)))))
        : empty("none")),
      group("Channels", guide("channels"), channels.length
        ? table(["Name", "Source"], channels.map((c) => h("tr", {}, h("td", {}, h("code", {}, c.name)), h("td", {}, src(c.source)))))
        : empty("none")),
      group("Rake tasks", guide("rake_tasks"), tasks.length
        ? table(["Task", "Description", "Source"], tasks.map((t) => h("tr", {},
            h("td", {}, h("code", {}, t.name)), h("td", {}, t.comment || muted("none")), h("td", {}, src(t.source)))))
        : empty("none"))
    ];
  }

  function renderGems() {
    const rows = gems.filter((g) => matches(g.name, g.railtie));
    return [
      pageHeader("Gems", gems.length + " gems in the bundle, the Gemfile's own first."),
      rows.length
        ? table(["Gem", "Version", "Railtie", "Initializers", "Middleware", "Links"], rows.map((g) => {
            const mw = g.middleware || [];
            return h("tr", {},
              h("td", {}, h("strong", {}, g.name), g.direct ? [" ", h("span", { class: "tag tag--accent" }, "Gemfile")] : null),
              h("td", {}, h("code", {}, g.version)),
              h("td", {}, g.railtie ? h("code", {}, g.railtie) : muted("none")),
              h("td", { class: "num" }, g.initializers || 0),
              h("td", { class: "num", title: mw.length ? mw.join("\n") : null }, mw.length),
              h("td", {}, h("div", { class: "links" }, gemLinks(g.links))));
          }), "", [["gem", "14rem"], ["version", null], ["railtie", null], ["initializers", null], ["middleware", null], ["links", "18rem"]])
        : emptyState("gems", gems.length)
    ];
  }

  function renderDocs() {
    const docs = documents.filter((d) => matches(d.title, d.path, d.kind)).slice().sort((a, b) => a.path.localeCompare(b.path));
    return [
      pageHeader("Documents", documents.length + " Markdown files from the configured docs folders."),
      docs.length ? table(["Title", "Kind", "Audience", "Path"], docs.map((d) => h("tr", {},
        h("td", {}, h("a", { href: docHref(d), lang: langOf(d.title) }, d.title || d.path), d.has_mermaid ? [" ", h("span", { class: "tag tag--out" }, "diagram")] : null),
        h("td", {}, h("span", { class: "tag tag--doc" }, d.kind || "document")), h("td", {}, d.audience || "all"), h("td", {}, h("code", { class: "muted" }, d.path)))))
        : emptyState("documents", documents.length)
    ];
  }

  // ---------- page flow ----------

  // At this many pages the diagram draws one group at a time.
  const FLOW_LIMIT = 60;
  let flowCache = null;

  // A page's group: its controller's namespace (everything before the last ::), or (app) for top-level controllers.
  const flowGroupOf = (name) => name.includes("::") ? name.slice(0, name.lastIndexOf("::")) : "(app)";
  const engineOf = (key) => { const r = routes.find((x) => x.controller === key); return r ? r.engine || null : null; };
  const flowHref = (node) => "#/flow/" + encodeURIComponent(node.group) + "/" + node.id;

  // A link to the route it reaches: the named route by (engine, stem), then on that path the GET route for a link,
  // or for a form the write route of its method (the first write route when the method is not set).
  function flowRoute(link) {
    const engine = link.engine || null;
    const named = routes.find((r) => r.name === link.stem && (r.engine || null) === engine);
    if (!named) return null;
    const onPath = routes.filter((r) => r.path === named.path && (r.engine || null) === engine);
    if (!link.form) return onPath.find((r) => r.verb === "GET") || null;
    const writes = onPath.filter((r) => r.verb !== "GET");
    return (link.method ? writes.find((r) => r.verb === link.method.toUpperCase()) : writes[0]) || null;
  }

  // Pages as nodes, links and form landings as edges, groups by namespace (largest first), layout links resolved.
  function flowGraph() {
    if (flowCache) return flowCache;
    const nodes = new Map(), byRoute = new Map(), edges = [], seen = new Set();
    let groups = new Map();
    for (const page of pages) {
      const key = routeKey(page.controller), engine = engineOf(key);
      const ctrl = controllers.find((c) => c.name === page.controller);
      const action = ctrl && (ctrl.actions || []).find((a) => a.name === page.action);
      const inertia = !!(action && action.view && action.view.kind === "inertia");
      if (page.format !== "html" && !inertia) continue;
      const rs = routes.filter((r) => r.verb === "GET" && r.controller === key && r.action === page.action && (r.engine || null) === engine);
      if (!rs.length) continue;
      const group = flowGroupOf(page.controller);
      const node = { id: ident(page.controller + "#" + page.action), controller: page.controller, action: page.action, group,
        path: rs[0].path, verb: "GET", routes: rs, page, inertia, muted: false };
      nodes.set(node.id, node);
      rs.forEach((r) => byRoute.set(r, node));
      if (!groups.has(group)) groups.set(group, []);
      groups.get(group).push(node);
    }
    groups = new Map([...groups].sort((a, b) => b[1].length - a[1].length || a[0].localeCompare(b[0])));
    const add = (edge) => {
      const k = edge.from + " " + edge.to + " " + edge.label;
      if (!seen.has(k)) { seen.add(k); edges.push(edge); }
    };
    for (const node of nodes.values()) {
      for (const link of node.page.links || []) {
        const route = flowRoute(link);
        if (!route) continue;
        const base = { from: node.id, form: !!link.form, source: link.source };
        if (!link.form) {
          const to = byRoute.get(route);
          if (to) add({ ...base, to: to.id, label: "", stub: null });
          continue;
        }
        // A form lands where its target action redirects, when that is a page; otherwise it ends in a small action node.
        const target = pages.find((p) => routeKey(p.controller) === route.controller && p.action === route.action);
        const landings = (target ? target.redirects || [] : [])
          .map((r) => byRoute.get(flowRoute({ stem: r.stem, engine: r.engine, form: false }))).filter(Boolean);
        if (landings.length) landings.forEach((to) => add({ ...base, to: to.id, label: route.action, stub: null }));
        else {
          const ctrl = target ? target.controller : (controllers.find((c) => routeKey(c.name) === route.controller) || {}).name || route.controller;
          add({ ...base, to: "stub_" + ident(ctrl + "#" + route.action), label: "", stub: { verb: route.verb, action: route.action } });
        }
      }
    }
    const nav = layouts.map((layout) => {
      const once = new Set();
      const links = (layout.links || []).map(flowRoute).filter((r) => r && !once.has(r) && once.add(r))
        .map((route) => ({ route, node: byRoute.get(route) || null }));
      return { layout, links };
    });
    flowCache = { nodes, edges, groups, nav };
    return flowCache;
  }

  // Mermaid source: every group as a subgraph when group is null; else one subgraph per controller of that group,
  // plus the pages outside it that it links to or is linked from, muted.
  function flowSource(graph, group) {
    const q = (s) => '"' + String(s).replace(/"/g, "#quot;") + '"';
    const shape = (n) => n.id + (n.inertia ? "[[" + q(n.path) + "]]" : "[" + q(n.path) + "]");
    const inGroup = (id) => group == null || (graph.nodes.has(id) && graph.nodes.get(id).group === group);
    const lines = ["flowchart LR"], drawn = new Set();
    const subgraph = (name, ns) => {
      lines.push("  subgraph sg_" + ident(name) + "[" + q(name) + "]");
      for (const n of ns) { lines.push("    " + shape(n)); drawn.add(n.id); }
      lines.push("  end");
    };
    if (group == null) for (const [g, ns] of graph.groups) subgraph(g, ns);
    else {
      const byCtrl = new Map();
      for (const n of graph.groups.get(group) || []) {
        if (!byCtrl.has(n.controller)) byCtrl.set(n.controller, []);
        byCtrl.get(n.controller).push(n);
      }
      for (const [c, ns] of byCtrl) subgraph(c, ns);
      for (const e of graph.edges) {
        const other = inGroup(e.from) ? e.to : inGroup(e.to) ? e.from : null;
        const n = other && graph.nodes.get(other);
        if (n && !drawn.has(n.id)) { lines.push("  " + shape(n), "  class " + n.id + " muted"); drawn.add(n.id); }
      }
    }
    for (const e of graph.edges) {
      if (!inGroup(e.from) && !inGroup(e.to)) continue;
      if (e.stub && drawn.has(e.from) && !drawn.has(e.to)) { lines.push("  " + e.to + "([" + q(e.stub.verb + " " + e.stub.action) + "])"); drawn.add(e.to); }
      if (!drawn.has(e.from) || !drawn.has(e.to)) continue;
      lines.push("  " + e.from + (e.label ? " -->|" + q(e.label) + "| " : " --> ") + e.to);
    }
    return lines.join("\n");
  }

  function renderFlow(arg) {
    const graph = flowGraph();
    const [want, pageId] = String(arg || "").split("/");
    state.flowPage = pageId && graph.nodes.has(pageId) ? pageId : null;
    const out = [pageHeader("Page flow", "Every page a GET route reaches, and the links, forms and redirects between them. Layout links are listed above the diagram, not drawn.")];
    if (!graph.nodes.size) {
      return out.concat(h("div", { class: "empty-state" },
        h("p", {}, "No pages. A page is a controller action a GET route reaches that renders an HTML template or an Inertia page; this app has none.")));
    }
    const drawn = graph.nodes.size >= FLOW_LIMIT ? (graph.groups.has(want) ? want : graph.groups.keys().next().value) : null;
    out.push(h("nav", { class: "chips", "aria-label": "Page groups" }, [...graph.groups].map(([g, ns]) =>
      h("a", { class: "chip", href: "#/flow/" + encodeURIComponent(g), "aria-current": g === drawn ? "page" : null },
        icon("i-flow"), g, " ", h("span", { class: "num muted" }, ns.length)))));
    if (graph.nav.length) {
      out.push(h("div", { class: "flow-nav", role: "group", "aria-label": "Navigation" }, graph.nav.map(({ layout, links }) =>
        h("div", {}, label("Navigation"), codeLink(layout.source, layout.name),
          links.length ? links.map(({ route, node }) => node
            ? h("a", { class: "chip", href: flowHref(node) }, h("code", {}, route.path), verbPill(route.verb))
            : h("span", { class: "chip" }, h("code", {}, route.path), verbPill(route.verb)))
            : muted("no links")))));
    }
    const block = mermaidBlock(flowSource(graph, drawn));
    block.setAttribute("data-flow-group", drawn == null ? "*" : drawn);
    out.push(block, h("div", { id: "flow-detail" }));
    const fromNav = new Set(graph.nav.flatMap((n) => n.links.map((l) => l.node && l.node.id)));
    const rows = [...graph.nodes.values()]
      .filter((n) => matches(n.path, ...n.routes.map((r) => r.name), n.controller, n.page.template && n.page.template.path))
      .sort((a, b) => a.path.localeCompare(b.path))
      .map((n) => {
        const linksOut = graph.edges.filter((e) => e.from === n.id && !e.stub).length;
        const into = graph.edges.filter((e) => e.to === n.id);
        const lands = [...new Set(into.filter((e) => e.label).map((e) => e.label))];
        const warns = warnings.filter((w) => w.where === "pages" && w.message.startsWith(n.controller + "#" + n.action + ":")).length;
        return h("tr", {},
          h("td", {}, verbPill(n.verb), " ", h("a", { href: flowHref(n) }, h("code", {}, n.path)),
            n.inertia ? [" ", h("span", { class: "tag tag--out" }, "page")] : null,
            !into.length && !fromNav.has(n.id) ? [" ", h("span", { class: "tag tag--warn" }, "unreached")] : null),
          h("td", {}, codeLink(n.page.template)),
          h("td", { class: "num" }, linksOut),
          h("td", { class: "num" }, into.length, !into.length && fromNav.has(n.id) ? [" ", h("span", { class: "tag tag--out" }, "from navigation")] : null),
          h("td", {}, lands.length ? lands.join(", ") : muted("none")),
          h("td", { class: "num" }, warns ? h("span", { class: "warn-text" }, icon("i-warn", "", warns + " warnings"), " " + warns) : ""));
      });
    out.push(rows.length
      ? table(["Page", "Template", "Links out", "Linked from", "Lands here after", "Warnings"], rows, "flow-ledger")
      : emptyState("pages", pages.length));
    return out;
  }

  // ---------- chrome: nav, footer, banner ----------

  function renderNav(active) {
    document.getElementById("nav").replaceChildren(...NAV.map(([id, text, ic, count]) => {
      const n = typeof count === "function" ? count() : count;
      return h("li", {}, h("a", { href: "#/" + id, "aria-current": active === id ? "page" : null }, icon(ic), text,
        n == null ? null : h("span", { class: "count" }, n)));
    }));
  }

  function renderFooter() {
    const repo = meta.repo || {};
    const when = meta.generated_at ? new Date(meta.generated_at) : null;
    document.getElementById("footer").replaceChildren(
      h("span", {}, meta.app_name || "app"),
      h("span", {}, "Rails ", meta.rails_version || "?"),
      h("span", { title: meta.generated_at || "" }, "Generated ", when && !isNaN(when) ? when.toLocaleString() : "unknown"),
      h("span", {}, "Commit ", repo.sha ? h("code", { title: repo.sha }, repo.sha.slice(0, 12)) : "none", repo.dirty ? " (dirty)" : ""),
      h("span", {}, "Fonts: IBM Plex (OFL)"));
  }

  function renderBanner() {
    const repo = meta.repo || {};
    const el = document.getElementById("banner");
    if (!repo.dirty && !warnings.length) return el.remove();
    const parts = [];
    if (repo.dirty) parts.push("working tree has uncommitted changes, so source links point at the last commit");
    if (warnings.length) parts.push(warnings.length + (warnings.length === 1 ? " warning from the dump" : " warnings from the dump"));
    el.className = "banner";
    el.setAttribute("role", "status");
    el.append(h("details", {},
      h("summary", {}, icon("i-chev", "chev"), icon("i-warn"), parts.join("; ")),
      h("ul", { class: "plain" }, warnings.map((w) => h("li", {}, h("span", { class: "tag" }, w.where), " ", w.message)))));
  }

  // ---------- routing ----------

  // A malformed escape (a stray %) falls back to the raw text instead of throwing.
  function decode(s) {
    try { return decodeURIComponent(s); } catch (_) { return s; }
  }

  function render() {
    const raw = location.hash.replace(/^#\/?/, "");
    const [view, ...rest] = raw.split("/");
    const arg = rest.length ? decode(rest.join("/")) : null;
    let nodes, active = view;
    switch (view) {
      case "requests": nodes = renderRequests(arg); break;
      case "flow": nodes = renderFlow(arg); break;
      case "domain": nodes = renderDomain(arg); break;
      case "databases": nodes = renderDatabases(); break;
      case "boot": nodes = renderBoot(); break;
      case "middleware": nodes = renderMiddleware(); break;
      case "entry": nodes = renderEntry(); break;
      case "gems": nodes = renderGems(); break;
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
  search.addEventListener("input", () => { state.query = search.value.trim().toLowerCase(); render(); });
  const toggle = document.querySelector(".nav-toggle");
  const sidebar = document.getElementById("sidebar");
  toggle.addEventListener("click", () => {
    const open = sidebar.classList.toggle("open");
    toggle.setAttribute("aria-expanded", String(open));
  });
  window.addEventListener("hashchange", () => {
    // Routes are #/... and the empty hash (Start here, e.g. after Back to the first entry).
    // Any other hash (the skip link #main, an in-page anchor) keeps the current view and only moves focus.
    if (location.hash && !location.hash.startsWith("#/")) {
      const target = document.getElementById(decode(location.hash.slice(1))) || main;
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
