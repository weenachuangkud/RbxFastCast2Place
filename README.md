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

The wrapper has explicit `Uninitialized`, `Initializing`, `Ready`, `Failed`, and `Destroyed` states. It rejects firing while not ready. Switching modes destroys the current caster and creates one using the other implementation; active casts are not migrated.

## Tools

- **ConfigUI** — equip to open the Iris configuration window; unequip to hide it. It edits wrapper behavior, caster mode, and projectile cosmetics.
- **BasicFire** — fire a projectile from the local character's head toward the mouse target.
- **Benchmark** — currently a tool entry point; workload and result collection still need implementation.
- **UnitTest** — currently a tool entry point; porting the serial and parallel automated suites is still future work.

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
- Benchmark runs must use identical workload/configuration across Serial and Parallel. Record whether Iris is enabled and use UI-disabled runs to isolate FastCast overhead.
- This change has not been run in Roblox Studio yet.
