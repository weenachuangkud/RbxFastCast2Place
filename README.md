# RbxFastCast2Place

A Roblox Studio development place for testing, debugging, and benchmarking the refactored FastCast2 implementations.

## FastCast2 source

This project uses two source repositories directly as pinned Git submodules:

- `vendor/FastCast2Serial` — [FastCast2](https://github.com/weenachuangkud/FastCast2), branch `weenachuangkud-refactor`, pinned to the source commit recorded in the submodule.
- `vendor/FastCast2Parallel` — [FastCast2Parallel](https://github.com/weenachuangkud/FastCast2Parallel), branch `main`, pinned to the source commit recorded in the submodule.

These are **not** the published Wally `weenachuangkud/fastcast2@0.1.4` package. Wally provides Iris and ByteNet; Rojo maps both FastCast2 source repositories directly under `ReplicatedStorage`.

After cloning, initialize the submodules:

```powershell
git submodule update --init --recursive
```

To update a dependency deliberately, enter its submodule, check out the intended branch/commit, and commit the changed submodule pointer in this repository.

## Architecture

- `src/shared/FastCast2Wrapper.luau` is the bridge for one caster per Luau context.
- The Serial and Parallel modules are separate implementations with separate shared runtimes.
- Both use the refactor API: initialize the library runtime with `FastCast2.Init(...)`, then create a caster with `FastCast2.new()`.
- Client and server contexts have independent wrapper state. ByteNet synchronizes shared cast settings and relays fire requests to the server.
- StarterPack tools share the wrapper instead of creating their own casters.

The wrapper has explicit `Uninitialized`, `Initializing`, `Ready`, `Failed`, and `Destroyed` states, plus a separate runtime state (`Uninitialized`, `Running`, `Stopped`, or `Destroyed`). It rejects firing while the wrapper or runtime is not ready. Switching between Serial and Parallel stops the old runtime, destroys its caster, and tears down the old Parallel worker pool when applicable before creating the replacement; active casts are not migrated. The default mode is Serial and the default fire context is Client. Parallel Actor count can be changed from ConfigUI by destroying the old worker pool and initializing a new one with the requested count.

### Runtime lifecycle

The library runtime and the wrapper/caster lifecycle are separate concerns:

- **`Init(...)`** initializes the library runtime. Calling it again while the runtime is already running is safe; after `Stop()`, calling `Init(...)` resumes simulation. Initialize the runtime before creating or firing casts.
- **`Stop()`** stops the simulation update loop without destroying the runtime or its active casts. A later `Init(...)` resumes it; this is a pause/resume operation, not a full reset.
- **Parallel `DestroyVMs()`** tears down the Parallel worker VMs and discards active casts and queued fire requests. Existing caster objects and their signals remain, but firing requires `Init(...)` again. Do not treat this as equivalent to `Stop()`.
- **Mode switching** is handled by the wrapper: it destroys the old caster and creates one for the selected implementation. Active casts do not transfer between Serial and Parallel. This is separate from pausing or resuming a library runtime.
- **Movement mode** is configured through the shared library API, `FastCast2.SetMovementModeEnabled(enabled, mode)`, rather than a per-caster method.

ConfigUI exposes lifecycle controls so you can exercise these transitions directly:

- **Stop runtime** pauses the currently selected library while preserving its runtime and active casts.
- **Resume / Init runtime** resumes a stopped runtime, or recreates a destroyed Parallel runtime.
- **Destroy Parallel VMs** tears down the worker pool without discarding the wrapper/caster object. Active casts and queued fire requests are discarded; use Resume / Init runtime to create a fresh worker pool before firing again.

Switching mode and resizing the active Parallel Actor pool use the same lifecycle APIs automatically. These operations are blocked while a benchmark is running.

## Tools

- **ConfigUI** — equip to open the Iris configuration window; unequip to hide it. It edits wrapper behavior, caster mode, and projectile cosmetics, and configures/displays benchmark results locally.
- **BasicFire** — fire a projectile from the local character's head toward the mouse target.
- **Benchmark** — click to benchmark the currently selected cast type in the selected Serial or Parallel mode, using the wrapper’s current movement, cosmetic, velocity, fidelity, and Actor-count settings.
- **PerfBench** — click separately to run the selected Serial or Parallel implementation through the configured Raycast PerFrame/Fixed cases. Its count, sample duration, instancing, simulation modes, and movement cases are configured independently in ConfigUI.

Configure options in ConfigUI, run Benchmark or PerfBench, then equip ConfigUI again to inspect the latest client-side report. Functional tests are maintained and run separately in the FastCast2 source repositories.

## Projectile cosmetics

Place projectile `.rbxmx` assets in the repository's `projectiles/` folder. Rojo syncs that folder to `ReplicatedStorage.Projectiles`. Each selectable projectile must be a `BasePart` directly inside that folder.

In ConfigUI:
- **Instanced** creates a cloned cosmetic part for each cast.
- Select a projectile in `Projectiles` to use it as the cosmetic template.
- If no projectile is selected or the folder has no valid projectile, Instanced mode uses a default `1×1×1` part.
- **Instanceless** sets `CosmeticBulletTemplate = nil`, so casts are simulated without a cosmetic projectile instance.

## Toolchain

Install Rokit, then run from the repository root:

```powershell
rokit install
git submodule update --init --recursive
wally install
rojo plugin install
rojo serve
```

Open Roblox Studio and connect the Rojo plugin.

To build a place file:

```powershell
rojo build default.project.json -o RbxFastCast2Place.rbxlx
```

## Notes

- ConfigUI changes are sent through ByteNet when values change. The server clamps accepted values and remains responsible for authoritative hit detection; client firing is prediction only.
- Parallel `CanPierce` runs in the worker VM and must be supplied through a `FastCastEventsModule`, not a main-thread caster callback.
- Benchmark controls are available in ConfigUI. The Benchmark and PerfBench tools show result summaries in ConfigUI as well as emitting diagnostic output to the client console. PerfBench temporarily switches the selected runtime between PerFrame and Fixed and restores its original mode afterward.
- This change has not been run in Roblox Studio yet.
