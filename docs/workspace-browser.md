# Workspace browser tool

Reuse an existing host-wide Playwright MCP runtime when agents need rendered-page
inspection, screenshots, or browser interaction across tasks. Share the pinned
runtime and Playwright's default browser store across tools and projects. Keep
each caller's output, temporary files, caches, and machine-specific registration
in its own ignored local directory. Retain the runtime's lockfile so starting a
task does not silently install a different tool.

## Reuse and register

1. Locate the host's existing shared runtime, launcher, config, and lockfile.
   Do not install a project copy of Playwright, `@playwright/mcp`, or Chromium;
   do not use npm install or npx to obtain a separate runtime. If the host has
   none, arrange a host-wide setup before registering a project.
2. Use Playwright's default browser store. Never set `PLAYWRIGHT_BROWSERS_PATH`
   to a project, task, or temporary directory, including during installation.
   If a browser is needed, run `node_modules/.bin/playwright install chromium`
   from the shared runtime with the default store selected. Verify that the
   runtime is registered in the store's `.links` directory so cleanup retains
   its matching revision. Check the runtime's Node and system dependencies.
3. Select an ignored caller state directory on a disk-backed filesystem. Check
   the runtime, browser store, and temporary paths with `findmnt`. Pass the
   state directory through `PLAYWRIGHT_MCP_STATE_DIR`; the shared launcher must
   use it for `TMPDIR`, `TMP`, `TEMP`, caches, and output, and change directory
   there so relative screenshot filenames stay with the caller. Launch with
   `--headless`, `--isolated`, and an explicit `--output-dir`. Use stdio
   transport; omit `--port`. Keep contexts separate from an operator's attended
   browser and login profile.
4. Register the launcher as a project MCP server in the ignored
   `.codex/config.toml`. Use the actual absolute launcher path locally, preserve
   other settings, and leave existing approval and sandbox policies intact.
   Project configuration loads only for a trusted workspace.
   For access across projects, register the shared launcher in user-level
   `~/.codex/config.toml` and arrange caller-specific state selection. Do not
   carry one project's fixed state or output paths into the global entry.
5. Restart the MCP connection or start a new task to load the registration.
   Confirm that the client lists the browser tools.

## Acceptance checks

- Initialize the MCP connection and list its tools.
- Navigate to an approved public page or local test page through the MCP tool.
- Capture and inspect a screenshot; verify any requested viewport or layout
  measurement from the rendered page.
- Close the browser and confirm that the launcher does not leave an unintended
  listening endpoint or browser process.
- Record the installed versions, local paths, connection result, maintenance
  procedure, and any remaining client activation step in an ignored handoff.

Browser launch and a successful protocol check establish that the
runtime works. Confirm client registration separately before reporting that a
future task can discover its tools. Keep the reusable runtime and browser cache;
remove disposable verification contexts and output when no longer needed.

Use the MCP tools for browser work. A one-off script may require Playwright from
the shared runtime's `node_modules`, or launch with `executablePath` pointing to
Chromium in the default store. It must not download another runtime or browser.

## Activate in a remote workspace

Reload MCP on the host running the workspace's Codex app server. Connect to its
existing control endpoint using the documented transport. A Unix control socket
uses WebSocket framing with an HTTP Upgrade handshake; send JSON-RPC messages
as WebSocket text frames after initialization.

Verify that the running server has the intended task loaded before requesting
`config/mcpServer/reload`. Check the task-scoped MCP status and tool discovery,
then invoke a small browser command to confirm the client can use the tools.
Close any disposable browser context afterward. This reload queues connection
refreshes while preserving the running remote-control service.

## Maintenance

Ask the operator before upgrading the shared MCP runtime: all callers, including
other agent tools, use the same installation. Update it in place with an exact
package pin and lockfile; use its packaged CLI and the default store for matching
browsers. Re-run the acceptance checks after updating and keep the prior lockfile
until the replacement passes. Disconnect a project by removing its registration;
retain the shared runtime and browsers while other callers use them. Preserve
unrelated settings and browser profiles.

## References

- [Playwright MCP](https://github.com/microsoft/playwright-mcp)
- [Codex MCP configuration](https://learn.chatgpt.com/docs/extend/mcp?surface=cli)
- [Codex project configuration](https://learn.chatgpt.com/docs/config-file/config-basic)
- [Codex app-server protocol and MCP reload](https://learn.chatgpt.com/docs/app-server)
