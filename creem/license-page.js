/*!
 * Lidkeys — Creem license pages (success.html + recover.html), shared script.
 *
 * success.html: Creem redirects here after payment with
 *   ?checkout_id=…&order_id=…&customer_id=…&product_id=…&signature=…
 * The query string is forwarded to the license Worker UNCHANGED (Creem signs the parameters
 * in their original order), so this page never adds its own query parameters — the language
 * choice lives in localStorage, not in the URL.
 *
 * recover.html: order ID + purchase email → POST <worker>/recover (the email goes in the
 * request body, never in a URL).
 *
 * ---------------------------------------------------------------------------------------
 * CONFIG — the only thing to edit before going live:
 *   licenseEndpoint  the deployed Worker, e.g. https://creem-license.<subdomain>.workers.dev
 *                    While it still contains REPLACE_WITH the pages show "not set up yet"
 *                    and never request anything or show a key.
 *   supportEmail     shown on both pages
 * A page may also set window.LIDKEYS_CREEM_CONFIG = {…} before this script.
 * ---------------------------------------------------------------------------------------
 */
(function (root) {
  "use strict";

  var DEFAULT_CONFIG = {
    licenseEndpoint: "https://creem-license.lidworks-lab-server.workers.dev",
    supportEmail: "lidworks@proton.me"
  };

  var LICENSE_KEY_RE = /^LPRO1\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/;
  var SAFE_ID_RE = /^[A-Za-z0-9_-]{4,128}$/;
  var SIGNATURE_RE = /^[0-9a-fA-F]{64}$/;
  var RETRY_DELAYS_MS = [1500, 3000, 6000, 10000, 15000];
  var REQUEST_TIMEOUT_MS = 12000;
  var LANG_STORAGE_KEY = "lidkeys-lang";

  // ------------------------------------------------------------------ strings
  var STRINGS = {
    en: {
      eyebrow_order: "Order complete",
      eyebrow_status: "Order status",
      eyebrow_recover: "Lost your key?",
      title_loading: "Getting your license…",
      lead_loading: "Checking your payment with Creem. This usually takes a few seconds.",
      title_success: "You’re all set.",
      lead_success: "Here is your lifetime Lidkeys Pro license.",
      title_recover: "Find your license key",
      lead_recover: "Enter the order ID and the email you paid with. Both must match the order.",
      loading_first: "Checking the order with Creem…",
      loading_retry_paid: "Creem is still confirming your payment — retrying in a moment…",
      loading_retry_network: "Couldn’t reach the license service — retrying in a moment…",
      loading_retry_server: "The license service is taking a moment — retrying…",
      recover_working: "Looking up your order…",
      chip_product: "Lidkeys Pro · Lifetime",
      chip_licensed_to: "Licensed to ",
      chip_test: "TEST MODE — not a real purchase",
      copied: "Copied",
      copy_manual: "Press ⌘C to copy",
      invalid_input: "Enter an order ID (it starts with ord_) and the email you used at checkout.",
      err: {
        not_configured: ["The license service isn’t set up yet",
          "This page is not connected to the license service yet, so it will not show a key. Your payment is safe — email us with your order ID and we’ll send your key."],
        missing_order: ["This link is missing the order details",
          "Open the link from your Creem receipt, or use “Find my key” with your order ID and email."],
        bad_link: ["We couldn’t verify this link",
          "The order details in this link don’t check out. Use “Find my key” with your order ID and the email you paid with."],
        not_found: ["We couldn’t find that order",
          "Check the order ID (it starts with ord_) and use the exact email you paid with. Still stuck? Email us."],
        not_paid: ["Your payment is still being confirmed",
          "Creem hasn’t marked the order as paid yet. Some payment methods take a minute — try again shortly."],
        payment_failed: ["This payment didn’t go through",
          "The checkout expired or the payment was declined, so no license was issued. If money left your account, email us."],
        refunded: ["This order was refunded",
          "No license is issued for refunded or disputed orders. If this looks wrong, email us with your order ID."],
        wrong_product: ["This order isn’t for Lidkeys Pro",
          "The license service only issues keys for Lidkeys Pro. If this looks wrong, email us with your order ID."],
        server: ["The license service is temporarily unavailable",
          "Nothing is wrong with your payment. Try again in a minute, or email us and we’ll send your key."],
        network: ["Couldn’t reach the license service",
          "Check your internet connection and try again. Your key can always be re-issued for the same order."]
      }
    },
    zh: {
      eyebrow_order: "付款完成",
      eyebrow_status: "订单状态",
      eyebrow_recover: "激活码丢了？",
      title_loading: "正在获取激活码…",
      lead_loading: "正在向 Creem 核实付款，一般几秒钟。",
      title_success: "搞定了。",
      lead_success: "这是你的 Lidkeys Pro 永久激活码。",
      title_recover: "找回激活码",
      lead_recover: "填订单号和付款时用的邮箱，两样都对上才能找回。",
      loading_first: "正在向 Creem 核实订单…",
      loading_retry_paid: "Creem 还在确认付款，稍后自动重试…",
      loading_retry_network: "连不上激活码服务，稍后自动重试…",
      loading_retry_server: "激活码服务有点慢，正在重试…",
      recover_working: "正在查找订单…",
      chip_product: "Lidkeys Pro · 永久",
      chip_licensed_to: "授权给 ",
      chip_test: "测试模式：不是真实购买",
      copied: "已复制",
      copy_manual: "按 ⌘C 复制",
      invalid_input: "请填订单号（以 ord_ 开头）和付款时用的邮箱。",
      err: {
        not_configured: ["激活码服务还没接好",
          "这个页面还没连上激活码服务，所以不会显示激活码。你的付款是安全的：把订单号发邮件给我们，我们把激活码发给你。"],
        missing_order: ["这个链接缺少订单信息",
          "请用 Creem 收据里的链接打开，或者用「找回激活码」，填订单号和邮箱。"],
        bad_link: ["这个链接没通过校验",
          "链接里的订单信息对不上。请用「找回激活码」，填订单号和付款邮箱。"],
        not_found: ["没找到这个订单",
          "请检查订单号（以 ord_ 开头），邮箱要和付款时完全一致。还是不行就给我们写信。"],
        not_paid: ["付款还在确认中",
          "Creem 还没把订单标成已付款。有些付款方式要等一分钟，请稍后再试。"],
        payment_failed: ["这笔付款没有成功",
          "结账已过期或付款被拒，所以没有发激活码。如果钱已经扣了，请给我们写信。"],
        refunded: ["这个订单已退款",
          "已退款或有争议的订单不发激活码。如果有误，请带上订单号给我们写信。"],
        wrong_product: ["这个订单买的不是 Lidkeys Pro",
          "激活码服务只为 Lidkeys Pro 发码。如果有误，请带上订单号给我们写信。"],
        server: ["激活码服务暂时不可用",
          "你的付款没有问题。请过一分钟再试，或者给我们写信，我们把激活码发给你。"],
        network: ["连不上激活码服务",
          "请检查网络后重试。同一个订单随时可以再取一次激活码。"]
      }
    }
  };

  // ------------------------------------------------------------------ pure helpers (tested in Node)
  function mergeConfig(base, extra) {
    var out = {};
    var key;
    for (key in base) if (Object.prototype.hasOwnProperty.call(base, key)) out[key] = base[key];
    if (extra && typeof extra === "object") {
      for (key in extra) {
        if (Object.prototype.hasOwnProperty.call(extra, key) && typeof extra[key] === "string" && extra[key]) out[key] = extra[key];
      }
    }
    return out;
  }

  /** "" when the endpoint is a placeholder or not https (http://localhost allowed for wrangler dev). */
  function cleanEndpoint(value) {
    if (typeof value !== "string") return "";
    var trimmed = value.trim().replace(/\/+$/, "");
    if (!trimmed || trimmed.indexOf("REPLACE_WITH") !== -1) return "";
    var https = /^https:\/\/[A-Za-z0-9.-]+(:\d+)?(\/[A-Za-z0-9._~%/-]*)?$/.test(trimmed);
    var localDev = /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?(\/[A-Za-z0-9._~%/-]*)?$/.test(trimmed);
    return https || localDev ? trimmed : "";
  }

  /** Checks the Creem redirect query without changing it. */
  function inspectRedirect(search) {
    var params;
    try {
      params = new URLSearchParams(search || "");
    } catch (error) {
      return { ok: false, orderId: "" };
    }
    var orderId = params.get("order_id") || "";
    var ok = SIGNATURE_RE.test(params.get("signature") || "")
      && SAFE_ID_RE.test(params.get("checkout_id") || "")
      && SAFE_ID_RE.test(orderId);
    return { ok: ok, orderId: SAFE_ID_RE.test(orderId) ? orderId : "" };
  }

  function isLicenseKey(value) {
    return typeof value === "string" && LICENSE_KEY_RE.test(value);
  }

  function validRecoverInput(orderId, email) {
    var id = (orderId || "").trim();
    var mail = (email || "").trim();
    return SAFE_ID_RE.test(id) && /^[^\s@]+@[^\s@]+$/.test(mail) && mail.length <= 320;
  }

  /**
   * Worker answer → what the page does next.
   * @returns {{state:"success"}|{state:"retry",reason:string}|{state:"error",kind:string}}
   */
  function classifyResult(status, body) {
    body = body || {};
    if (status === 200) return isLicenseKey(body.key) ? { state: "success" } : { state: "retry", reason: "server" };
    var error = body.error;
    if (status === 403 && error === "order_not_paid") {
      var pending = body.status === "pending" || body.status === "processing" || body.status === "no_transaction";
      return pending ? { state: "retry", reason: "not_paid" } : { state: "error", kind: "payment_failed" };
    }
    if (status === 403 && error === "order_refunded") return { state: "error", kind: "refunded" };
    if (status === 403 && error === "product_mismatch") return { state: "error", kind: "wrong_product" };
    if (status === 403 && error === "invalid_signature") return { state: "error", kind: "bad_link" };
    if (status === 403 && error === "origin_not_allowed") return { state: "error", kind: "not_configured" };
    if (status === 400) return { state: "error", kind: "bad_link" };
    if (status === 404) return { state: "error", kind: "not_found" };
    return { state: "retry", reason: "server" };
  }

  function pickLanguage(stored, languages) {
    if (stored === "zh" || stored === "en") return stored;
    var list = languages || [];
    for (var i = 0; i < list.length; i += 1) {
      var tag = String(list[i] || "").toLowerCase();
      if (tag.indexOf("zh") === 0) return "zh";
      if (tag.indexOf("en") === 0) return "en";
    }
    return "en";
  }

  var api = {
    STRINGS: STRINGS,
    DEFAULT_CONFIG: DEFAULT_CONFIG,
    cleanEndpoint: cleanEndpoint,
    inspectRedirect: inspectRedirect,
    isLicenseKey: isLicenseKey,
    validRecoverInput: validRecoverInput,
    classifyResult: classifyResult,
    pickLanguage: pickLanguage,
    mergeConfig: mergeConfig
  };

  if (typeof module === "object" && module && module.exports) {
    module.exports = api;
    return;
  }

  // ------------------------------------------------------------------ browser wiring
  var doc = root.document;
  var page = doc.body.getAttribute("data-page") === "recover" ? "recover" : "success";
  var config = mergeConfig(DEFAULT_CONFIG, root.LIDKEYS_CREEM_CONFIG);
  var endpoint = cleanEndpoint(config.licenseEndpoint);
  var supportEmail = /@/.test(config.supportEmail || "") ? config.supportEmail.trim() : DEFAULT_CONFIG.supportEmail;

  var lang = "en";
  try {
    lang = pickLanguage(root.localStorage && root.localStorage.getItem(LANG_STORAGE_KEY), root.navigator && root.navigator.languages);
  } catch (error) {
    lang = pickLanguage(null, root.navigator && root.navigator.languages);
  }

  function $(id) {
    return doc.getElementById(id);
  }
  function t(key) {
    return STRINGS[lang][key];
  }
  function each(selector, fn) {
    var nodes = doc.querySelectorAll(selector);
    for (var i = 0; i < nodes.length; i += 1) fn(nodes[i]);
  }

  var el = {
    card: $("license-card"),
    eyebrow: $("license-eyebrow"),
    title: $("license-title"),
    lead: $("license-lead"),
    loading: $("state-loading"),
    loadingText: $("loading-text"),
    form: $("state-form"),
    success: $("state-success"),
    error: $("state-error"),
    errorTitle: $("error-title"),
    errorBody: $("error-body"),
    retry: $("retry"),
    key: $("license-key"),
    emailChip: $("email-chip"),
    productChip: $("product-chip"),
    modeChip: $("mode-chip"),
    copyKey: $("copy-key"),
    copyOrder: $("copy-order"),
    copyStatus: $("copy-status"),
    langToggle: $("lang-toggle"),
    recoverForm: $("recover-form"),
    orderInput: $("order-input"),
    emailInput: $("email-input"),
    formMessage: $("form-message"),
    submit: $("recover-submit")
  };

  var state = "loading";
  var header = "loading";
  var errorKind = "";
  var loadingKey = "loading_first";
  var orderId = "";
  var currentKey = "";
  var lastBody = null;
  var attempts = 0;
  var timer = null;
  var copyTimer = null;

  function show(name) {
    state = name;
    if (el.loading) el.loading.hidden = name !== "loading";
    if (el.form) el.form.hidden = name !== "form";
    el.success.hidden = name !== "success";
    el.error.hidden = name !== "error";
    el.card.setAttribute("data-state", name);
    doc.body.setAttribute("data-license-state", name);
  }

  function paintHeader() {
    var map = {
      loading: ["eyebrow_order", "title_loading", "lead_loading"],
      success: ["eyebrow_order", "title_success", "lead_success"],
      error: ["eyebrow_status", null, null],
      recover: ["eyebrow_recover", "title_recover", "lead_recover"]
    };
    var keys = map[header] || map.loading;
    el.eyebrow.textContent = t(keys[0]);
    if (header === "error") {
      el.title.textContent = STRINGS[lang].err[errorKind] ? STRINGS[lang].err[errorKind][0] : STRINGS[lang].err.server[0];
      el.lead.textContent = "";
      el.lead.hidden = true;
    } else {
      el.title.textContent = t(keys[1]);
      el.lead.textContent = t(keys[2]);
      el.lead.hidden = false;
    }
  }

  function paint() {
    doc.documentElement.setAttribute("lang", lang === "zh" ? "zh-Hans" : "en");
    doc.documentElement.setAttribute("data-lang", lang);
    if (el.langToggle) el.langToggle.textContent = lang === "zh" ? "English" : "中文";
    paintHeader();
    if (el.loadingText) el.loadingText.textContent = t(loadingKey);
    if (state === "error") {
      var pair = STRINGS[lang].err[errorKind] || STRINGS[lang].err.server;
      el.errorBody.textContent = pair[1];
    }
    if (lastBody) {
      el.productChip.textContent = t("chip_product");
      el.emailChip.textContent = lastBody.email_masked ? t("chip_licensed_to") + lastBody.email_masked : "";
      el.emailChip.hidden = !lastBody.email_masked;
      el.modeChip.textContent = t("chip_test");
      el.modeChip.hidden = lastBody.mode !== "test";
    }
  }

  function fillStatic() {
    each("[data-support-email]", function (node) {
      node.textContent = supportEmail;
      if (node.tagName === "A") node.setAttribute("href", "mailto:" + supportEmail);
    });
    each("[data-order-id]", function (node) {
      node.textContent = orderId || "—";
    });
    each("[data-recover-link]", function (node) {
      node.setAttribute("href", "recover.html" + (orderId ? "?order_id=" + encodeURIComponent(orderId) : ""));
    });
  }

  function renderError(kind) {
    errorKind = kind;
    header = "error";
    if (el.retry) el.retry.hidden = !(kind === "server" || kind === "network" || kind === "not_paid");
    show("error");
    paint();
  }

  function renderSuccess(body) {
    lastBody = body;
    currentKey = body.key;
    if (body.order_id && SAFE_ID_RE.test(body.order_id)) orderId = body.order_id;
    el.key.textContent = body.key;
    header = "success";
    show("success");
    fillStatic();
    paint();
  }

  function setLoading(key) {
    loadingKey = key;
    header = page === "recover" ? "recover" : "loading";
    show("loading");
    paint();
  }

  function withTimeout(promise) {
    return new Promise(function (resolve, reject) {
      var id = setTimeout(function () { reject(new Error("timeout")); }, REQUEST_TIMEOUT_MS);
      promise.then(function (value) { clearTimeout(id); resolve(value); }, function (error) { clearTimeout(id); reject(error); });
    });
  }

  function request(url, init) {
    return withTimeout(root.fetch(url, init)).then(function (response) {
      return response.json().catch(function () { return null; }).then(function (body) {
        return { status: response.status, body: body };
      });
    });
  }

  // ---------------------------------------------------------------- success page
  function attemptLicense() {
    attempts += 1;
    request(endpoint + "/license" + root.location.search, {
      method: "GET",
      headers: { Accept: "application/json" },
      mode: "cors",
      credentials: "omit",
      cache: "no-store"
    }).then(function (result) {
      var verdict = classifyResult(result.status, result.body);
      if (verdict.state === "success") renderSuccess(result.body);
      else if (verdict.state === "error") renderError(verdict.kind);
      else retryLicense(verdict.reason);
    }, function () {
      retryLicense("network");
    });
  }

  function retryLicense(reason) {
    if (attempts > RETRY_DELAYS_MS.length) {
      renderError(reason === "not_paid" ? "not_paid" : reason === "network" ? "network" : "server");
      return;
    }
    setLoading(reason === "not_paid" ? "loading_retry_paid" : reason === "network" ? "loading_retry_network" : "loading_retry_server");
    timer = setTimeout(function () {
      timer = null;
      attemptLicense();
    }, RETRY_DELAYS_MS[attempts - 1]);
  }

  function startSuccessPage() {
    if (timer) {
      clearTimeout(timer);
      timer = null;
    }
    attempts = 0;
    var check = inspectRedirect(root.location.search);
    orderId = check.orderId;
    fillStatic();
    if (!endpoint) return renderError("not_configured");
    if (!check.ok) return renderError("missing_order");
    setLoading("loading_first");
    attemptLicense();
  }

  // ---------------------------------------------------------------- recover page
  function showForm(message) {
    header = "recover";
    show("form");
    paint();
    el.formMessage.textContent = message || "";
    el.formMessage.hidden = !message;
  }

  function submitRecover() {
    var id = (el.orderInput.value || "").trim();
    var email = (el.emailInput.value || "").trim();
    if (!validRecoverInput(id, email)) {
      showForm(t("invalid_input"));
      return;
    }
    orderId = id;
    el.submit.disabled = true;
    setLoading("recover_working");
    request(endpoint + "/recover", {
      method: "POST",
      headers: { Accept: "application/json", "Content-Type": "application/json" },
      body: JSON.stringify({ order_id: id, email: email }),
      mode: "cors",
      credentials: "omit",
      cache: "no-store"
    }).then(function (result) {
      el.submit.disabled = false;
      var verdict = classifyResult(result.status, result.body);
      if (verdict.state === "success") return renderSuccess(result.body);
      var kind = verdict.state === "error" ? verdict.kind : verdict.reason === "not_paid" ? "not_paid" : "server";
      showForm(STRINGS[lang].err[kind][0] + " — " + STRINGS[lang].err[kind][1]);
    }, function () {
      el.submit.disabled = false;
      showForm(STRINGS[lang].err.network[0] + " — " + STRINGS[lang].err.network[1]);
    });
  }

  function startRecoverPage() {
    var prefill = "";
    try {
      prefill = new URLSearchParams(root.location.search || "").get("order_id") || "";
    } catch (error) {
      prefill = "";
    }
    if (SAFE_ID_RE.test(prefill)) el.orderInput.value = prefill;
    fillStatic();
    if (!endpoint) {
      el.submit.disabled = true;
      renderError("not_configured");
      return;
    }
    showForm("");
  }

  // ---------------------------------------------------------------- copy
  function flash(text) {
    el.copyStatus.textContent = text;
    if (copyTimer) clearTimeout(copyTimer);
    copyTimer = setTimeout(function () { el.copyStatus.textContent = ""; }, 3000);
  }

  function selectNode(node) {
    try {
      var range = doc.createRange();
      range.selectNodeContents(node);
      var selection = root.getSelection();
      selection.removeAllRanges();
      selection.addRange(range);
    } catch (error) {
      /* best effort */
    }
  }

  function copy(text, node) {
    if (!text) return;
    var manual = function () {
      if (node) selectNode(node);
      flash(t("copy_manual"));
    };
    if (root.navigator && root.navigator.clipboard && typeof root.navigator.clipboard.writeText === "function") {
      root.navigator.clipboard.writeText(text).then(function () { flash(t("copied")); }, manual);
    } else {
      manual();
    }
  }

  // ---------------------------------------------------------------- wiring
  if (el.copyKey) el.copyKey.addEventListener("click", function () { copy(currentKey, el.key); });
  if (el.copyOrder) el.copyOrder.addEventListener("click", function () { copy(orderId, null); });
  if (el.key) el.key.addEventListener("click", function () { if (currentKey) selectNode(el.key); });
  if (el.retry) {
    el.retry.addEventListener("click", function () {
      if (page === "recover") showForm("");
      else startSuccessPage();
    });
  }
  if (el.recoverForm) {
    el.recoverForm.addEventListener("submit", function (event) {
      if (event && event.preventDefault) event.preventDefault();
      submitRecover();
    });
  }
  if (el.langToggle) {
    el.langToggle.addEventListener("click", function () {
      lang = lang === "zh" ? "en" : "zh";
      try {
        if (root.localStorage) root.localStorage.setItem(LANG_STORAGE_KEY, lang);
      } catch (error) {
        /* private mode: just switch for this visit */
      }
      paint();
    });
  }

  root.LidkeysCreemPage = { state: function () { return state; }, errorKind: function () { return errorKind; } };

  paint();
  if (page === "recover") startRecoverPage();
  else startSuccessPage();
})(typeof window !== "undefined" ? window : this);
