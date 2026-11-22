/* CORE10 preview presentation glue — align embedded dashboard language with Owner shell.
 * Does not handle authentication, call any backend or decide permissions.
 */
(function (win) {
  "use strict";
  try {
    var l = new URL(win.location.href).searchParams.get("lang");
    if (l === "bn" || l === "en") {
      win.localStorage.setItem("core10.od.lang", l);
      win.document.documentElement.lang = l;
    }
  } catch (_) {}
})(window);
