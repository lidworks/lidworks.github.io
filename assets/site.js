// Lidworks 产品页共用的小脚本：页脚年份 + "复制安装命令"按钮。
document.querySelectorAll("[data-year]").forEach(function (el) { el.textContent = new Date().getFullYear(); });

// 复制命令；浏览器不让写剪贴板时，就把命令选中，提示用户自己按 ⌘C
document.querySelectorAll(".command").forEach(function (box) {
  var copy = box.querySelector("button");
  var cmd = box.querySelector("code");
  if (!copy || !cmd) return;
  var label = copy.textContent;
  function flash(text) { copy.textContent = text; setTimeout(function () { copy.textContent = label; }, 2500); }
  function selectCommand() {
    var range = document.createRange();
    range.selectNodeContents(cmd);
    var selection = window.getSelection();
    selection.removeAllRanges();
    selection.addRange(range);
    flash("Press ⌘C");
  }
  copy.addEventListener("click", function () {
    if (navigator.clipboard && window.isSecureContext) {
      navigator.clipboard.writeText(cmd.textContent).then(function () { flash("Copied"); }, selectCommand);
    } else {
      selectCommand();
    }
  });
});
