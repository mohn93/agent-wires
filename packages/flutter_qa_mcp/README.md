# flutter_qa_mcp

MCP server that bridges an LLM agent to a running Flutter app via the Dart VM service.

## Run

```bash
# Terminal 1: start the app
flutter run

# Terminal 2: start the MCP server (paste the VM Service URI printed by `flutter run`)
dart run flutter_qa_mcp --attach ws://127.0.0.1:54321/abc=/ws
```

Configure your MCP client to point at the running server over stdio.

## Tools (v1)

- `snapshot` — denoised semantic tree of the visible screen
- `inspect(element_id)` — full widget chain for one element
- `screenshot` — base64 PNG of the current frame
