// dsh-winshell client plugin: a "Default terminal" preference row in the
// Web UI General settings, mirroring the shipped EnterBehaviorRow grammar
// (row layout, capsule selector with chevron, --dsw-* tokens).
//
// DSH >= 0.1.5: the browser module table (PLATFORM_MODULES) seeds react,
// @deepseek-ai/cordis, @deepseek-ai/dsh-client-store, @deepseek-ai/dsh-client-ui-slots,
// @deepseek-ai/dsh-client-ui-primitives and @deepseek-ai/dsh-client-ui-dockkit by
// exact bare specifier. The old dsh-client-runtime name is gone from that table
// (and so is its /client subpath), so this bundle requests dsh-client-store.

import { useState } from "react";
import { defineStore } from "@deepseek-ai/dsh-client-store";
import { IconChevronDownOutline14, Menu } from "@deepseek-ai/dsh-client-ui-primitives";

const SETTINGS_NS = "settings.winshell";
const SETTINGS_NAMESPACE = "winshell";
const SHELLS = ["powershell", "gitbash", "wsl"];

// Injected once when the browser loads the bundle (node tests guard on document).
const ROW_CSS = 
  ".btRow{border-bottom:1px solid var(--dsw-alias-border-l2);align-items:center;gap:8px;padding:16px 0;display:flex}" +
  ".btRowText{flex-direction:column;flex:1;gap:4px;min-width:0;padding-right:48px;display:flex}" +
  ".btTitle{color:var(--dsw-alias-label-primary);font-size:14px;font-weight:400;line-height:22px}" +
  ".btDesc{color:var(--dsw-alias-label-tertiary);font-size:12px;font-weight:400;line-height:18px}" +
  ".btSelector{background:var(--dsw-alias-bg-module-platform);height:36px;font:inherit;color:var(--dsw-alias-label-primary);cursor:pointer;border:none;border-radius:18px;align-items:center;gap:12px;padding:0 14px;font-size:14px;line-height:22px;display:inline-flex}" +
  ".btSelector:hover{background:var(--dsw-alias-interactive-bg-hover)}" +
  ".btChevron{flex:none}";
if (typeof document !== "undefined" && document.querySelector("style[data-plugin-css=\"winshell-row\"]") === null) {
  const tag = document.createElement("style");
  tag.dataset.plugin = "dsh-winshell";
  tag.dataset.pluginCss = "winshell-row";
  tag.textContent = ROW_CSS;
  document.head.appendChild(tag);
}

const zh = {
  "shell.title": "默认终端",
  "shell.description": "shell 工具执行命令时使用的终端",
  "shell.powershell": "PowerShell",
  "shell.gitbash": "Git Bash",
  "shell.wsl": "WSL"
};
const en = {
  "shell.title": "Default terminal",
  "shell.description": "Terminal used by the shell tool",
  "shell.powershell": "PowerShell",
  "shell.gitbash": "Git Bash",
  "shell.wsl": "WSL"
};

export const inject = ["slots", "locale", "settingsScope"];

function ShellPreferenceRow({ t, useStore, setShell }) {
  const shell = useStore((s) => s.shell);
  const writable = useStore((s) => s.writable);
  const [open, setOpen] = useState(false);
  const items = SHELLS.map((id) => ({ id, label: t("shell." + id) }));
  return (
    <div className="btRow">
      <div className="btRowText">
        <div className="btTitle">{t("shell.title")}</div>
        <div className="btDesc">{t("shell.description")}</div>
      </div>
      <Menu
        open={open}
        onClose={() => setOpen(false)}
        items={items}
        selectedId={shell}
        onSelect={(id) => {
          setOpen(false);
          setShell(id);
        }}
        align="end"
        portal
        anchor={
          <button
            type="button"
            className="btSelector"
            aria-haspopup="menu"
            aria-expanded={open}
            disabled={!writable}
            onClick={() => setOpen(!open)}
            style={!writable ? { opacity: 0.5, cursor: "not-allowed" } : undefined}
          >
            {t("shell." + shell)}
            <IconChevronDownOutline14 className="btChevron" />
          </button>
        }
      />
    </div>
  );
}

export function apply(ctx) {
  ctx.effect(() => ctx.locale.register(SETTINGS_NS, { zh, en }), "winshell: settings dictionaries");
  const scope = ctx.settingsScope.bind({ namespace: SETTINGS_NAMESPACE });
  const store = defineStore({
    init: () => ({ shell: "powershell", revision: -1, writable: false }),
    actions: {
      sync: (d, shell, revision, writable) => {
        if (revision !== undefined && revision <= d.revision) return;
        if (shell !== undefined) d.shell = shell;
        if (revision !== undefined) d.revision = revision;
        if (writable !== undefined) d.writable = writable;
      }
    }
  });
  let bound;
  const push = (snap) => bound?.sync(snap.value?.defaultShell, snap.revision, snap.writable);
  ctx.slots.inject(
    "settings.general.item",
    () =>
      ctx.slots.register(
        {
          name: "settings.general.item",
          id: "winshell-shell",
          order: 20,
          store,
          locale: SETTINGS_NS,
          inject: (actions) => {
            bound = actions;
            push(scope.getSnapshot());
            return { setShell: (value) => void scope.set("defaultShell", value) };
          }
        },
        ShellPreferenceRow
      ),
    "winshell: settings row"
  );
  ctx.effect(() => scope.subscribe(() => push(scope.getSnapshot())), "winshell: settings watch");
}
