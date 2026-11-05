# dsh-winshell

[![test](https://github.com/IGrock88/dsh-winshell/actions/workflows/test.yml/badge.svg)](https://github.com/IGrock88/dsh-winshell/actions/workflows/test.yml)
[![npm](https://img.shields.io/npm/v/dsh-winshell.svg)](https://www.npmjs.com/package/dsh-winshell)
[![license](https://img.shields.io/npm/l/dsh-winshell.svg)](LICENSE)

A DeepSeek Harness (DSH) plugin for Windows: one `shell` tool that runs commands in
**PowerShell**, **Git Bash**, or **WSL** - whichever terminal you choose - plus a
persistent **`terminal`** tool with real PTY sessions and SSH support.

## Highlights

- **You choose the terminal; the model cannot.** Pick `powershell`, `gitbash` or
  `wsl` for the `shell` tool in the plugin config. The tool description follows the
  active backend, so the model writes the right syntax, and every call uses the
  configured executable/path.
- **Byte-exact script delivery.** The command text never crosses the Windows command
  line as one raw argv element. Bash backends read the script from stdin
  (`bash -ls`); PowerShell receives it base64-encoded via `-EncodedCommand`. Heredocs,
  quotes, `$`, backslashes, and scripts far larger than the 32 KB Windows
  command-line limit arrive unchanged. The stdin pipe is written and closed in one
  step, so a command that reads stdin (`cat`, `read`, a pager) sees EOF instead of
  hanging - including inside background jobs.
- **Background jobs.** `run_in_background: true` returns a job id immediately;
  `job_output` pages the collected output (full output spills to a file when large),
  and `job_kill` terminates the process tree. Background jobs have no timeout.
- **Persistent terminal sessions.** The `terminal` tool opens a real PTY and keeps
  state across commands: `open`, `send`, `read`, `signal`, `close`, `list`, plus
  `ssh` - one login reused for every later command on a remote server.
- **DSH sandbox honored.** In confined modes PowerShell argv is wrapped through
  `ctx.sandbox` with fail-closed semantics. Git Bash and WSL run unconfined for
  platform reasons documented below. `sandbox_permissions` + `justification`
  escalation is supported.
- **Windows only.** The plugin registers no tools on other platforms.

## Requirements

- Windows 10/11.
- DSH 0.2.x (the declared DSH peer range is `>=0.1.5-rc.1 <0.3.0`).
- Node.js 20 or newer for the host.
- PowerShell 7 (`pwsh`) recommended; Windows PowerShell 5.1 is supported for
  one-shot commands.
- Git for Windows for the `gitbash` backend.
- WSL for the `wsl` backend and for the default SSH backend.

## Install

```powershell
npm install -g dsh-winshell
dsh plugin --profile web add dsh-winshell
# restart the DSH web process
```

The package ships its own `cordis.patch.yml` bundle layer. Listing
`dsh-winshell` in a profile's `dsh.profile.bundles` mounts the plugin's
`tool-winshell` row automatically - no manual profile patch is required for the
mount itself.

### Upgrading from `dsh-bash-terminal`

Both packages register the same tool names (`shell` and `terminal`), so do not
mount them in the same profile. Remove the old package from the profile first
(remove it from `dsh.profile.bundles`, delete
`node_modules/dsh-bash-terminal`, or run its uninstall script), then install
`dsh-winshell`. The DSH plugin row id changes from `tool-bash-terminal` to
`tool-winshell`, so configuration kept under the old row id does not carry over;
copy the values to the new row (see below).

## Configuration

The plugin's `Config` is its DSH settings section. The row id is `tool-winshell`.

| Field | Default | Meaning |
|---|---|---|
| `defaultShell` | `powershell` | Backend used by the `shell` tool: `powershell`, `gitbash` or `wsl`. |
| `sshShell` | `wsl` | Backend that hosts `terminal` sessions opened with `ssh`. Kept separate because SSH aliases and keys usually live in the WSL `~/.ssh/config`. |
| `timeoutMs` | `120000` | Default foreground command timeout. |
| `maxTimeoutMs` | `600000` | Upper bound for a caller's `timeoutMs`. |
| `pwshPath` | auto | Explicit PowerShell executable. |
| `gitBashPath` | auto | Explicit Git Bash executable. |
| `wslPath` | auto | Explicit `wsl.exe`. |

Set values in the profile patch:

```yaml
- id: tool-winshell
  config:
    defaultShell: wsl
    timeoutMs: 180000
```

DSH 0.2.x exposes a plugin's config as its settings section; the legacy
"Settings -> General -> Default terminal" row from the pre-0.2 client half is not
shipped in this release.

## The `shell` tool

Each call spawns a fresh shell; no state (cwd, variables, aliases) survives
between calls. Pass `workdir` instead of using `cd`, and use the `terminal` tool
when state must persist or when the command needs interactive input.

```powershell
# PowerShell backend
Get-ChildItem C:\Users
```

```bash
# Git Bash backend
git status
```

```bash
# WSL backend
ls /mnt/c/Users
```

Parameters: `command`, `description`, optional `distro` (WSL), `workdir`,
`timeoutMs`, `run_in_background`, and the sandbox escalation pair
`sandbox_permissions` + `justification`.

### Heredocs and multiline scripts

Heredocs work as typed, including quoted delimiters and multiline bodies:

```bash
cat >> notes.txt <<'EOF'
double: "x"
single: 'y'
dollar: $HOME stays literal
backslash: \\ and \n stay literal
EOF
```

Bash reads the script from stdin, so the file receives exactly those bytes; there
is no extra shell level to re-parse the text. On PowerShell the script is passed
through `-EncodedCommand`, which preserves newlines and quotes in the same way.

### Background jobs

```text
run_in_background: true  ->  { kind: "background", jobId: "shell/wsl-…" }
job_output(jobId)        ->  incremental output + exit status
job_kill(jobId)          ->  terminate the process tree
```

No timeout applies to background jobs. Their stdin is closed immediately after the
script is written, so a job cannot be left waiting on an open stdin handle.

## The `terminal` tool

| Action | Purpose |
|---|---|
| `open` | Start a local persistent session on the configured backend. |
| `ssh` | Start a session already logged in to a remote host (`sshHost`: an `~/.ssh/config` alias, `user@host`, or an address). |
| `send` | Write input and read new output. End command input with `\r` (Enter). |
| `read` | Read output produced since this reader's cursor. |
| `signal` | Send SIGINT (Ctrl+C) and other supported signals to the foreground process. |
| `close` | Close the session. |
| `list` | List live sessions. |

Sessions are real PTYs backed by node-pty and are managed as background jobs, so
`job_kill` works. Idle sessions close automatically (30 minutes for SSH sessions,
10 minutes for local ones). Reads are incremental and terminal-rendered: each reply
carries only new output, with `nextOffset`, `pending`, `more`, `waiting`, and
`elided` markers, and one reply is capped at 32 KB of UTF-8 bytes and pages the
rest.

`ssh` uses the `sshShell` backend (default `wsl`) because that is where SSH
aliases and keys usually live. A single login is reused for every later `send`, so
the remote cwd, exported variables, and shell state persist between commands.

## Output

- stdout and stderr are collected separately; stderr is rendered after a
  `[stderr]` marker.
- A non-zero exit status renders `[exit code: N]`; a signal renders
  `[killed by signal: N]`; a timeout renders `[timed out after Nms]`.
- Large streams keep a bounded in-memory tail and spill the complete stream to a
  file whose path is reported in the result.

## Sandbox

- `danger-full-access` calls run directly.
- In confined modes (`read-only`, `workspace-write`) PowerShell argv is wrapped
  through `ctx.sandbox`; when no sandbox backend is usable the call fails closed
  with the official sandbox error.
- Git Bash is never wrapped: the DSH Windows ACL restricted-token runner cannot
  host Cygwin/MSYS2 (`CreateFileMapping … Win32 error 5`). Results report
  `enforcement: gitbash-unconfined`.
- WSL is never wrapped: its VM isolation is the sandbox. Results report
  `enforcement: wsl-isolation`.
- A denied call renders the official
  `[sandbox: file access denied under <mode> mode]` marker plus an escalation
  hint. The model may retry once with `sandbox_permissions` + `justification`
  (approved through `ctx.approval`).
- This plugin does not use the official `pwsh` tool's ConstrainedLanguage
  executor. For a PowerShell command that must run inside that surface, keep using
  the official `pwsh` tool.

## PowerShell notes and known limits

- `-EncodedCommand` is UTF-16LE base64, so the encoded payload has its own
  Windows command-line budget (practically ~12K characters of script). Split very
  large scripts into a file and run the file instead.
- Windows PowerShell 5.1 serializes its own cmdlet error records on stderr as
  CLIXML when `-EncodedCommand` is used. Native program stderr is unaffected, exit
  codes are unchanged, and PowerShell 7 does not exhibit this behavior. Use `pwsh`
  when plain-text PowerShell errors matter.
- The encoded route keeps `-NoLogo -NoProfile -NonInteractive`; `-l` is preserved
  for bash, so PATH and login environment match the previous behavior.

## Interactive terminal limits (ConPTY)

- Windows PowerShell 5.1 cannot start in a ConPTY (0x8009001d); install PowerShell
  7 for interactive PowerShell. One-shot commands are unaffected.
- `wsl.exe` interactive mode may hit a WSL service RPC error under ConPTY
  (0x8007072c, intermittent); one-shot shell commands work.
- On Windows, node-pty has no named signals: `SIGINT` is delivered as Ctrl+C;
  other signals degrade to terminating the session.
- Git Bash interactive sessions work fully.

## Development

```powershell
git clone https://github.com/IGrock88/dsh-winshell.git
cd dsh-winshell
npm install
npm test
```

For a live profile install from a checkout, `install.ps1 install` links the
checkout into the profile and adds the bundle. The client bundle is retained for
older/compatible DSH versions and can be rebuilt with
`node scripts/build-client.mjs` (esbuild is a dev dependency); DSH 0.2.x does not
load it.

`npm test` runs, in order:

- `test/unit.mjs` - pure helpers, argv/stdin construction, descriptions;
- `test/apply.mjs` - plugin registration and mock-spawn integration;
- `test/buffer.mjs` - incremental PTY delivery and rendering;
- `test/terminal.mjs` - a real node-pty session (skipped on GitHub-hosted Windows
  runners, where ConPTY is unstable; run it locally);
- `test/settle.mjs` - settle windows and the SSH session surface;
- `test/e2e.mjs` - real subprocess provider: WSL/Git Bash heredocs byte-for-byte
  (foreground and background), stdin EOF, PowerShell multiline/exit codes, and an
  80 KB heredoc. It skips when the DSH subprocess provider is not installed.

`node test/client.mjs` separately exercises the client bundle logic (requires
React/React DOM).

## License

MIT. See [LICENSE](LICENSE).
