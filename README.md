# RbxFastCast2Place

A Roblox Studio development place for testing, debugging, and benchmarking [FastCast2](https://github.com/weenachuangkud/FastCast2).

## Architecture

- `src/shared/FastCast2Wrapper.luau` owns one caster per Luau context. Client and server contexts have independent wrapper state.
- StarterPack tools use the shared wrapper instead of creating their own caster.
- `ConfigUI` opens Dear ImGui while equipped and shuts its rendering context down when unequipped.
- `BasicFire` fires a projectile from the local character's head toward the mouse target.
- `Benchmark` and `UnitTest` are tool entry points for the next implementation phase.

The wrapper has explicit `Uninitialized`, `Initializing`, `Ready`, `Failed`, and `Destroyed` states. Calls to fire while it is not ready are rejected. Changing Serial/Parallel mode rebuilds the wrapper's caster; existing casts are not migrated.

## Toolchain

This project pins development tools in `rokit.toml`:

- **Rokit** manages project tool versions.
- **Rojo** syncs source files with Roblox Studio and builds the place.
- **Wally** installs FastCast2 and the ImGui debug UI.

Install Rokit, then run from the repository root:

```powershell
rokit install
wally install
rojo plugin install
rojo serve
```

Open the place in Roblox Studio and connect the Rojo plugin.

To build a place file:

```powershell
rojo build default.project.json -o RbxFastCast2Place.rbxlx
```

## Configuration UI

Equip **ConfigUI** to open the ImGui settings panel. It exposes Serial/Parallel switching, velocity, cast type, and common `FastCastBehavior` settings. Unequipping disconnects the render loop and shuts down the ImGui context.

Settings are shared within that client context and affect future casts. The server has its own wrapper and behavior; client UI edits do not replicate configuration to the server.

## Benchmarking notes

The benchmark tool is currently an entry point only; a real workload runner and comparable client/server result capture are still to be implemented.

For valid performance comparisons:

- Keep the workload, projectile count, cast configuration, and duration identical between Serial and Parallel.
- Record whether the ConfigUI is open.
- Run a second measurement with UI rendering disabled when you need to isolate FastCast2 overhead.
- Do not treat a client-only result as a server benchmark.

## Current limitations

- UnitTest currently reports the wrapper state; existing FastCast2 automated tests have not yet been ported.
- BasicFire is a local testing tool, not a server-authoritative weapon implementation.
- Mode changes destroy the old caster and initialize a new one. Active casts are not transferred between modes.
- This scaffold has not been executed in Roblox Studio in this change.
