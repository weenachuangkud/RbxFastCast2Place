# RbxFastCast2Place

A Roblox Studio place for testing, debugging, and benchmarking [FastCast2](https://github.com/weenachuangkud/FastCast2).

The place is intended to make it easy to change cast behavior and configuration while testing. The debug UI is part of the development workflow; use a separate console-only run when measuring FastCast2 without UI overhead.

## Toolchain

This project pins its development tools in `rokit.toml`:

- **Rokit** manages project tool versions.
- **Rojo** syncs source files with Roblox Studio and builds the place.
- **Wally** installs FastCast2 and the ImGui debug UI.

## Setup

Install Rokit using the instructions in the [Rokit README](https://github.com/rojo-rbx/rokit), then run these commands from the repository root:

```powershell
rokit install
wally install
rojo plugin install
rojo serve
```

Open the place in Roblox Studio, then connect the Rojo plugin to the running server.

To build a place file instead:

```powershell
rojo build default.project.json -o RbxFastCast2Place.rbxlx
```

## Packages

Dependencies are declared in `wally.toml` and locked in `wally.lock`. Do not edit the lockfile manually; regenerate it with `wally install` after changing dependencies.

- FastCast2 is the projectile implementation under test.
- ImGui is the immediate-mode debug UI used to inspect and modify benchmark settings.

## Benchmarking notes

- Keep the UI available for interactive tests and tuning.
- Record whether a benchmark run includes the debug UI.
- For clean performance comparisons, run equivalent scenarios with the UI disabled and avoid changing multiple settings between runs.
- Compare serial and parallel behavior using the same projectile count, cast configuration, and duration.
