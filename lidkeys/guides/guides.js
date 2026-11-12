/* Lidkeys guide clips (lidkeys/index.html and lidkeys/guide/). No external resources.
 *  - A clip loads and plays only when at least 35% of it is on screen; off screen it pauses.
 *  - prefers-reduced-motion: no autoplay; poster + play button; a tap plays the clip once.
 *  - Pause button (WCAG 2.2.2). Pausing remembers the choice for this visitor (localStorage).
 *  - play() refused (e.g. iPhone Low Power Mode) shows the play button instead of an error.
 *  - Hidden tab pauses everything. Phones get the M poster (poster has no responsive form).
 */
(function () {
  "use strict";
  var videos = Array.prototype.slice.call(document.querySelectorAll("figure.ld-clip video"));
  if (!videos.length) return;

  var KEY = "lidkeys.guides.paused";
  var mm = window.matchMedia ? function (q) { return window.matchMedia(q); } : function () { return null; };
  var reduceMQ = mm("(prefers-reduced-motion: reduce)");
  var smallMQ = mm("(max-width: 760px)");

  function readPaused() { try { return window.localStorage.getItem(KEY) === "1"; } catch (e) { return false; } }
  function writePaused(on) {
    try { if (on) window.localStorage.setItem(KEY, "1"); else window.localStorage.removeItem(KEY); } catch (e) { /* private mode */ }
  }

  var userPaused = readPaused();
  function reduced() { return !!(reduceMQ && reduceMQ.matches); }
  function autoplayAllowed() { return !reduced() && !userPaused; }

  var clips = videos.map(function (v) {
    var fig = v.closest("figure");
    var btn = fig.querySelector(".ld-clip-toggle");
    var c = { video: v, fig: fig, btn: btn, visible: false, manual: false, posterD: v.getAttribute("poster"),
              posterM: v.getAttribute("data-poster-m") };
    v.muted = true;               // must be set as a property too for autoplay policies
    v.setAttribute("muted", "");
    v.disablePictureInPicture = true;
    if (btn) {
      btn.hidden = false;
      btn.addEventListener("click", function () { toggle(c); });
    }
    v.addEventListener("playing", function () { state(c, "playing"); });
    v.addEventListener("pause", function () { if (!v.ended) state(c, "paused"); });
    v.addEventListener("ended", function () {       // only in play-once mode (loop is off)
      c.manual = false;
      v.loop = true;
      v.load();                   // back to the poster
      state(c, "paused");
    });
    state(c, "paused");
    return c;
  });

  function state(c, s) {
    c.fig.setAttribute("data-state", s);
    if (c.btn) c.btn.setAttribute("aria-label", s === "playing" ? "Pause" : "Play");
  }

  function posters() {
    var small = !!(smallMQ && smallMQ.matches);
    clips.forEach(function (c) {
      if (!c.posterM || !c.video.paused || c.video.currentTime > 0) return;
      var want = small ? c.posterM : c.posterD;
      if (c.video.getAttribute("poster") !== want) c.video.setAttribute("poster", want);
    });
  }

  function play(c) {
    if (!c.video.paused) return;
    c.video.loop = !(reduced() && c.manual);       // reduced motion: a tap plays it once
    var p;
    try { p = c.video.play(); } catch (e) { p = null; }
    if (p && typeof p.then === "function") {
      p.then(null, function () { c.manual = false; state(c, "paused"); c.fig.classList.add("is-blocked"); });
    }
  }

  function pause(c) { if (!c.video.paused) c.video.pause(); }

  function update(c) {
    var want = c.visible && !document.hidden && (c.manual || autoplayAllowed());
    if (want) play(c); else pause(c);
  }

  function updateAll() { clips.forEach(update); }

  function toggle(c) {
    if (!c.video.paused) {
      // the visitor wants motion to stop: pause every clip and remember it
      userPaused = true;
      writePaused(true);
      clips.forEach(function (o) { o.manual = false; pause(o); });
    } else {
      c.manual = true;
      c.fig.classList.remove("is-blocked");
      play(c);
    }
  }

  if ("IntersectionObserver" in window) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        var c = clips.filter(function (x) { return x.video === e.target; })[0];
        if (!c) return;
        if (e.intersectionRatio >= 0.35) c.visible = true;
        else if (!e.isIntersecting) { c.visible = false; c.manual = false; }   // a tapped clip stops once it scrolls away
        update(c);
      });
    }, { threshold: [0, 0.35, 0.6] });
    clips.forEach(function (c) { io.observe(c.video); });
  } else {
    // Old browsers: no autoplay at all (it would download every clip); the play buttons still work.
    clips.forEach(function (c) { c.visible = true; });
    autoplayAllowed = function () { return false; };
  }

  document.addEventListener("visibilitychange", updateAll);
  function onChange(mq, fn) {
    if (!mq) return;
    if (mq.addEventListener) mq.addEventListener("change", fn); else if (mq.addListener) mq.addListener(fn);
  }
  onChange(reduceMQ, function () { clips.forEach(function (c) { c.manual = false; }); updateAll(); });
  onChange(smallMQ, posters);
  posters();
})();
