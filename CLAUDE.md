# High Roller

Godot 4.7 (GDScript) co-op casino party game. Design: `docs/design-plan.md`. Code map and module contracts: `docs/ARCHITECTURE.md`.

## Commands

- Run all tests headless: `./tools/test.sh` (filter: `./tools/test.sh heat`). Fails on any failed assert, parse error or runtime script error.
- Godot binary: `godot` on PATH (4.7.2). The test script copies the project to a temp dir, so parallel runs are safe.
- Run the game headless for N frames: `godot --headless --path . --quit-after 600`.

## Conventions

- Static typing everywhere (`var x: int`, `-> void`). Tabs for indentation.
- `scripts/core/` is pure game logic: `RefCounted` classes with `class_name`, no Node, no autoloads, no input, no scene tree. Randomness comes from an injected `RandomNumberGenerator`. This is the host-authoritative simulation that networking will wrap later.
- `scripts/world/` and `scripts/ui/` are Godot nodes that render the simulation and send it requests.
- All tunable numbers live in `scripts/core/tuning.gd`; shared enums in `scripts/core/hr.gd`.
- Every core class has unit tests in `tests/unit/test_<module>.gd` extending `TestCase` (see `tests/test_case.gd`).
- Use `##` doc comments on public classes and non-obvious functions only.
