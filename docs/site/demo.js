// 코칭일지 웹 체험: 예시 기록을 앱과 같은 규칙으로 점검하고, 고쳐 본다.
// 규칙은 앱의 KACValidator · Certification 과 같다: 한국코치협회는 세션 30~120분(유의사항 3),
// 같은 날 같은 고객 2회 합산 120분까지, 1:1 코치더코치는 2배로 기록. ICF 는 세션 길이 제한이 없고
// 받은 코치더코치를 시간에 넣지 않는다. 고객 수: KAC 3명 · ACC 8명. 목표: KAC 50시간 · ACC 100시간.
(() => {
  const root = document.getElementById("demo");
  if (!root) return;
  const T = JSON.parse(root.dataset.text);
  const CERTS = { KAC: { icf: false, hours: 50, clients: 3 }, ACC: { icf: true, hours: 100, clients: 8 } };
  const fill = (s, v) => s.replace(/\{(\w+)\}/g, (_, k) => v[k]);
  const toMin = t => +t.slice(0, 2) * 60 + +t.slice(3);
  const toTime = m => `${String(Math.floor(m / 60)).padStart(2, "0")}:${String(m % 60).padStart(2, "0")}`;
  const P = T.people;
  const SAMPLE = [
    { who: P[0], kind: "paid", day: "2026-10-23", start: "16:30", end: "18:45" },
    { who: P[1], kind: "free", day: "2026-10-23", start: "19:00", end: "19:40" },
    { who: P[2], kind: "paid", day: "2026-10-22", start: "11:00", end: "12:00" },
    { who: P[2], kind: "paid", day: "2026-10-22", start: "15:00", end: "16:10" },
    { who: P[3], kind: "ctc", day: "2026-10-20", start: "16:00", end: "16:50" },
    { who: P[4], kind: "free", day: "2026-10-19", start: "20:30", end: "20:55" }
  ];
  let log, cert = "KAC";
  const reset = () => { log = SAMPLE.map((e, id) => ({ ...e, id })); };
  reset();

  const range = e => toMin(e.end) - toMin(e.start);
  const recorded = e => e.kind === "ctc" ? range(e) * 2 : range(e);           // 1:1 코치더코치 2배
  const allowed = e => e.kind === "ctc" ? [60, 120] : [30, 120];

  function check() {
    const c = CERTS[cert], issues = new Map(log.map(e => [e.id, []])), global = [];
    const add = (e, sev, msg, fix) => issues.get(e.id).push({ sev, msg, fix });
    for (const e of log) {
      if (c.icf) { if (e.kind === "ctc") add(e, "warn", T.ctcIcf); continue; }
      const m = recorded(e), [lo, hi] = allowed(e);
      if (m > hi) add(e, "error", fill(T.long, { min: m, lo, hi }), "trim");
      else if (m < lo) add(e, "error", fill(T.short, { min: m, lo, hi }), "delete");
    }
    if (!c.icf) {                                                          // 같은 날 같은 고객
      const groups = {};
      log.filter(e => e.kind !== "ctc").forEach(e => (groups[e.day + e.who] ||= []).push(e));
      Object.values(groups).forEach(g => {
        const sum = g.slice(0, 2).reduce((s, e) => s + recorded(e), 0);
        if (g.length >= 2 && sum > 120) add(g[1], "error", fill(T.sameDay, { day: g[1].day, name: g[1].who, min: sum }), "delete");
      });
    }
    const clients = new Set(log.filter(e => e.kind !== "ctc").map(e => e.who)).size;
    if (clients < c.clients) global.push({ sev: c.icf ? "warn" : "error", msg: fill(T.clients, { cert, n: c.clients, count: clients }) });
    return { issues, global };
  }

  function render() {
    const { issues, global } = check(), c = CERTS[cert];
    const counted = log.filter(e => !(c.icf && e.kind === "ctc"));
    const total = counted.reduce((s, e) => s + recorded(e), 0);
    const all = [...global, ...[...issues.values()].flat()];
    const errors = all.filter(i => i.sev === "error").length, warns = all.length - errors;
    root.innerHTML = `
      <div class="cl-top">
        <div class="cl-certs" role="group" aria-label="${T.cert}">
          ${Object.keys(CERTS).map(k => `<button type="button" class="chip" data-cert="${k}" aria-pressed="${k === cert}">${k}</button>`).join("")}
        </div>
        <button type="button" class="chip cl-reset" data-act="reset">${T.reset}</button>
      </div>
      <div class="cl-summary">
        <div><span class="muted small">${T.total}</span><b>${fill(T.hm, { h: Math.floor(total / 60), m: total % 60 })}</b></div>
        <div class="muted small">${fill(T.goal, { cert, h: c.hours })}</div>
        <div class="cl-bar" aria-hidden="true"><i style="width:${Math.min(100, total / (c.hours * 60) * 100)}%"></i></div>
        <p class="cl-status ${errors ? "bad" : warns ? "warn" : "ok"}" aria-live="polite">${errors || warns ? fill(T.tally, { e: errors, w: warns }) : T.pass}</p>
        ${global.map(i => `<p class="cl-issue ${i.sev}">${i.msg}</p>`).join("")}
      </div>
      <ul class="cl-list">${log.map(e => {
        const list = issues.get(e.id), excluded = c.icf && e.kind === "ctc";
        return `<li class="cl-row${list.some(i => i.sev === "error") ? " has-error" : ""}">
          <div class="cl-head"><b>${e.who}</b><span class="cl-min${excluded ? " off" : ""}">${fill(T.min, { n: recorded(e) })}</span></div>
          <div class="muted small">${e.day} ${e.start}-${e.end}</div>
          <div><span class="cl-kind ${e.kind}">${T[e.kind]}</span>${e.kind === "ctc" ? ` <span class="muted small">${T.ctcDouble}</span>` : ""}</div>
          ${list.map(i => `<p class="cl-issue ${i.sev}">${i.msg}</p>${
            i.fix === "trim" ? `<button type="button" class="chip cl-fix" data-trim="${e.id}">${fill(T.fix, { time: toTime(toMin(e.start) + allowed(e)[1]), hi: allowed(e)[1] })}</button>`
            : i.fix === "delete" ? `<button type="button" class="chip cl-fix" data-del="${e.id}">${T.del}</button>` : ""}`).join("")}
        </li>`;
      }).join("")}</ul>
      <p class="muted small cl-foot">${T.note}</p>`;
  }

  root.addEventListener("click", ev => {
    const b = ev.target.closest("button"); if (!b) return;
    if (b.dataset.cert) cert = b.dataset.cert;
    if (b.dataset.act === "reset") reset();
    if (b.dataset.trim) { const e = log.find(x => x.id === +b.dataset.trim); e.end = toTime(toMin(e.start) + allowed(e)[1]); }
    if (b.dataset.del) log = log.filter(x => x.id !== +b.dataset.del);
    const focus = b.dataset.cert ? `[data-cert="${cert}"]` : ".cl-status";
    render();
    const f = root.querySelector(focus); if (f && f.tagName === "BUTTON") f.focus();
  });

  render();
})();
