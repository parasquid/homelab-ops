# Workspace browser tool

Use a project-scoped Playwright MCP server when agents need rendered-page
inspection, screenshots, or browser interaction across tasks. Keep the runtime,
browser cache, output, and machine-specific Codex registration in ignored local
files. Pin the reviewed package version and retain its lockfile so starting a
task does not silently install a different tool.

## Install and register

1. Select an ignored runtime directory on a disk-backed filesystem. Check the
   runtime, browser cache, and temporary paths with `findmnt`. Set `TMPDIR`,
   `TMP`, and `TEMP` to disk-backed directories before installing or launching.
2. Install a reviewed version of the official `@playwright/mcp` package with an
   exact version and npm lockfile. Install its matching Chromium through the
   packaged Playwright CLI, using `PLAYWRIGHT_BROWSERS_PATH` for the browser
   cache. Check the package's documented Node requirement and launch the
   browser to verify that its system dependencies are available.
3. Create a local launcher that resolves its own runtime directory and starts
   the installed MCP entrypoint with `--headless`, `--isolated`, and an explicit
   `--output-dir`. Set the cache and temporary paths in the launcher. Use stdio
   transport; omit `--port`. Keep browser contexts separate from an operator's
   attended browser and login profile.
4. Register the launcher as a project MCP server in the ignored
   `.codex/config.toml`. Use the actual absolute launcher path locally, preserve
   other settings, and leave existing approval and sandbox policies intact.
   Project configuration loads only for a trusted workspace.
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

Browser installation and a successful protocol check establish that the
runtime works. Confirm client registration separately before reporting that a
future task can discover its tools. Keep the reusable runtime and browser cache;
remove disposable verification contexts and output when no longer needed.

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

Update the MCP package and its browser together only after reviewing a chosen
version. Re-run the protocol, navigation, and screenshot checks after updating.
Keep the prior lockfile until the replacement passes. Remove the project MCP
entry before deleting the runtime if uninstalling, and preserve unrelated
settings and browser profiles.

## References

- [Playwright MCP](https://github.com/microsoft/playwright-mcp)
- [Codex MCP configuration](https://learn.chatgpt.com/docs/extend/mcp?surface=cli)
- [Codex project configuration](https://learn.chatgpt.com/docs/config-file/config-basic)
- [Codex app-server protocol and MCP reload](https://learn.chatgpt.com/docs/app-server)
