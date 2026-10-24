// Korean / English switch. Picks ?lang=, then the saved choice, then the browser language.
(function () {
  var root = document.documentElement;
  function saved() {
    try { return localStorage.getItem("lang"); } catch (e) { return null; }
  }
  function apply(lang) {
    root.lang = lang;
    document.querySelectorAll(".lang button").forEach(function (button) {
      button.setAttribute("aria-pressed", String(button.dataset.set === lang));
    });
    var title = root.dataset["title" + (lang === "en" ? "En" : "Ko")];
    if (title) document.title = title;
  }
  var query = new URLSearchParams(location.search).get("lang");
  var initial = query || saved() || (navigator.language || "ko").slice(0, 2);
  apply(initial === "en" ? "en" : "ko");
  document.addEventListener("click", function (event) {
    var button = event.target.closest(".lang button");
    if (!button) return;
    apply(button.dataset.set);
    try { localStorage.setItem("lang", button.dataset.set); } catch (e) {}
  });
})();
