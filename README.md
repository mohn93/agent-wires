# ai_mobile_eyes — Flutter QA MCP

A runtime SDK + MCP server that lets LLM agents perceive and (eventually) drive Flutter apps for QA.

## Status

- **Plan 1 (Perception):** complete — see `docs/superpowers/plans/2026-05-21-flutter-qa-mcp-plan-1-perception.md`
- **Plan 2 (Drive):** not started — action and sync tools
- **Plan 3 (Augmentation):** not started — persistent map, dashboard, VLM proposals

## Layout

- `packages/flutter_qa_probe/` — Dart Flutter package, added as a dev dep in the app under test
- `packages/flutter_qa_mcp/` — Standalone MCP server
- `examples/demo_app/` — Tiny Flutter app for integration tests
- `docs/superpowers/specs/` — Design specs
- `docs/superpowers/plans/` — Implementation plans
