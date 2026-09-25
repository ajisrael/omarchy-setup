// opencode -> Omarchy notification bridge (user-scope plugin, auto-discovered
// from ~/.config/opencode/plugins/).
//
// When a session needs the user - permission ask, question, error, or the
// agent going idle after work - raise an Omarchy toast via
// omarchy-notification-send (part of the omarchy.notifications shell daemon,
// so it stacks in history and honors DND like any other popup).
//
// Each toast carries an omarchy-exec hint: Omarchy's daemon runs that command
// detached when the popup is clicked. For most events that jumps the attached
// tmux client to the window containing the notifying session and focuses the
// terminal window showing it. Permission asks go through
// omarchy-permission-menu instead: Omarchy popups have no inline buttons (the
// card renders icon/summary/body only), so the click summons Omarchy's option
// menu and Accept/Reject POST back to the opencode server directly - no jump
// to the session window needed for the mechanical approvals.
//
// Deliberately dependency-free: no npm imports, so the auto-discovery loader
// and a plain plugin file link both work; no extra bun install step.

import { execFile } from "node:child_process";
import { promisify } from "node:util";

const run = promisify(execFile);

// omarchy-notification-send is part of /usr/share/omarchy/bin (package-owned,
// read-only - consumed, never edited).
const NOTIFIER = "/usr/share/omarchy/bin/omarchy-notification-send";

export const OmarchyNotifyPlugin = async ({ client, serverUrl, directory }: any) => {
  const log = (level: string, message: string) => {
    client.app
      .log({ body: { service: "omarchy-notify", level, message } })
      .catch(() => {});
  };

  // The opencode process inherits the tmux pane context of the shell that
  // launched it, so at load time the pane + socket give us a stable jump
  // address. Both are captured once here and baked into every toast's click
  // command: by click time the exec runs from Omarchy's shell process, which
  // has no tmux env and couldn't resolve any of this itself.
  const pane = (globalThis.process?.env?.TMUX_PANE ?? "").trim();
  let socket = "";
  if (pane) {
    try {
      const { stdout } = await run("tmux", ["display-message", "-p", "#{socket_path}"]);
      socket = stdout.trim();
    } catch {
      log("warn", "TMUX_PANE set but tmux socket query failed");
    }
  }

  let jumpCmd = "";
  const home = (globalThis.process?.env?.HOME ?? "").trim();
  const jump = `${home}/.local/bin/omarchy-notification-jump`;
  if (home) {
    // --pane targets the exact pane (socket disambiguates which server);
    // outside tmux, --terminal only focuses the terminal window.
    jumpCmd = pane
      ? `${jump}${socket ? " --socket " + shellQuote(socket) : ""} --pane ${shellQuote(pane)}`
      : `${jump} --terminal`;
  }
  if (!pane) log("info", "outside tmux: toasts send without click-to-jump");

  function shellQuote(s: string) {
    return "'" + s.replace(/'/g, `'\\''`) + "'";
  }

  // Permission toasts click through to the respond menu: Accept/Reject POST
  // straight to this opencode server (serverUrl is handed to the plugin
  // itself, so no discovery), Jump still bakes the tmux jump command.
  let permCmd = "";
  const menuScript = `${home}/.local/bin/omarchy-permission-menu`;
  if (home && serverUrl) {
    const base = [
      "--server", shellQuote(String(serverUrl).replace(/\/+$/, "")),
      directory ? "--directory " + shellQuote(String(directory)) : "",
      socket ? "--socket " + shellQuote(socket) : "",
      pane ? "--pane " + shellQuote(pane) : "",
    ].filter(Boolean).join(" ");
    permCmd = `${menuScript} ${base}`;
  } else if (home) {
    log("warn", "no serverUrl: permission toasts will jump instead of offering Accept/Reject");
  }

  // Per-session title cache: the summary opencode generates for the session
  // is the fastest "which window do I go to" answer a toast can carry, so it
  // is the body line of every toast.
  const titles = new Map<string, string>();
  const titleFor = async (sessionID: string) => {
    if (!sessionID) return "";
    if (titles.has(sessionID)) return titles.get(sessionID)!;
    const res = await client.session.get({ path: { id: sessionID } }).catch(() => null);
    const title = String(res?.data?.title ?? "");
    if (title) titles.set(sessionID, title);
    return title;
  };

  const project = (globalThis.process?.cwd?.() ?? "").split("/").pop() ?? "";

  const notify = (headline: string, body: string, execOverride?: string) => {
    // --app-name opencode (not the omarchy-action default): while DND is on
    // the toast is suppressed on screen but still written to notification
    // history, so a burst of agent asks overnight remains catch-up-able.
    // --exec bakes the click command into the omarchy-exec hint, which the
    // daemon runs detached on click - a libnotify action would instead keep
    // this opencode process blocked on the toast and die unanswered whenever
    // the shell restarts underneath it.
    const exec = execOverride ?? jumpCmd;
    const args = [
      "--app-name", "opencode",
      "-u", "normal",
      "-t", "10000",
      ...(exec ? ["--exec", exec] : []),
      headline,
      body,
    ];
    return run(NOTIFIER, args).catch((e) => log("debug", `toast failed: ${e}`));
  };

  // Suppression: if this session's pane sits in the current window of some
  // attached client, the user is looking right at it - no popup. The exact
  // tmux comparison also survives the user dispatching to a different tmux
  // session from a second client.
  const paneIsVisible = async () => {
    if (!pane) return false;
    try {
      const mine = await run("tmux", [
        "display-message", "-p", "-t", pane, "#{session_name}|#{window_index}",
      ]);
      const [mySession, myWindow] = mine.stdout.trim().split("|");
      const { stdout } = await run("tmux", [
        "list-clients", "-F", "#{client_session}|#{window_index}",
      ]);
      return stdout
        .trim()
        .split("\n")
        .some((l) => l.trim() === `${mySession}|${myWindow}`);
    } catch {
      return false;
    }
  };

  // Dedupe window: repeated asks of the same kind back-to-back are the same
  // blocked state, not new ones (permission re-renders, idle firing right
  // behind an error, ...). Cleared when the ask is answered.
  const TTL = 20_000;
  const last = new Map<string, number>();
  const fresh = (key: string) => {
    const t = last.get(key) ?? 0;
    if (Date.now() - t < TTL) return true;
    last.set(key, Date.now());
    return false;
  };

  // Sessions we owe an idle ping to: armed on every user message, spent the
  // first time idle fires after it. Without the arming, an opencode that
  // connects mid-idle (or sits idle we never saw busy) would toast for
  // nothing.
  const busy = new Set<string>();

  const toast = async (sessionID: string, kind: string, headline: string) => {
    if (await paneIsVisible()) return;
    if (fresh(`${sessionID}:${kind}`)) return;
    const title = (await titleFor(sessionID)) || project;
    await notify(`${headline} - ${project}`, title || "session");
  };

  return {
    event: ({ event }: any) =>
      (async () => {
        const props = event.properties ?? {};
        const sid = props.sessionID ?? props.info?.sessionID ?? "";

        switch (event.type) {
          case "message.updated": {
            const info = props.info ?? {};
            if (info.role === "user") busy.add(info.sessionID);
            return;
          }
          case "session.status": {
            if (props.status?.type === "busy") last.clear();
            return;
          }
          case "permission.asked": {
            if (permCmd) {
              if (await paneIsVisible()) return;
              if (fresh(`${sid}:permission`)) return;
              // The menu prompt carries the actual ask ("Bash git push",
              // "Edit <path>", ...) - the toast body keeps the session title.
              const ask = String(props.title ?? "").split("\n")[0].slice(0, 60);
              const title = (await titleFor(sid)) || project;
              await notify(
                `Permission needed - ${project}`,
                title || "session",
                `${permCmd} ${shellQuote(ask)}`,
              );
              return;
            }
            await toast(sid, "permission", "Permission needed");
            return;
          }
          case "question.asked":
            await toast(sid, "question", "Question waiting");
            return;
          case "session.error": {
            if (props.error?.name === "MessageAbortedError") return; // user interrupt
            await toast(sid, "error", "Session error");
            return;
          }
          case "permission.replied":
          case "question.replied": {
            last.delete(`${sid}:permission`);
            last.delete(`${sid}:question`);
            return;
          }
          case "session.idle": {
            if (!busy.has(sid)) return;
            busy.delete(sid);
            await toast(sid, "idle", "Waiting for input");
            return;
          }
        }
      })(),
  };
};
