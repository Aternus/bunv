# Bunv

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://github.com/Aternus/bunv/blob/main/LICENSE)
[![GitHub stars](https://img.shields.io/github/stars/Aternus/bunv?style=social)](https://github.com/Aternus/bunv)

Bunv makes Bun versioning effortless.

It automatically downloads, manages, and runs the exact Bun version each project needs, so your tooling is always
correct, reproducible, and fast with near‑zero overhead (see [Benchmark](#benchmark)).

## Quick Start

```sh
curl -sL https://raw.githubusercontent.com/Aternus/bunv/main/install.sh | sh
export PATH="$HOME/.bunv/bin:$PATH"
which bun
```

```sh
bun --version
bun i
bunx oxlint@latest
```

## Features

- Automatic version selection for `bun` and `bunx`
- Manage installed versions with `bunv`
- Read the Bun version from `package.json`'s `packageManager` field, `.bun-version`, or `.tool-versions`

## How Bunv Chooses a Version

Bunv checks for a Bun version in this order:

1. `package.json` (`packageManager: "bun@x.y.z"`)
2. `.bun-version`
3. `.tool-versions`
4. Latest locally installed version
5. Latest remote release (downloaded on first use)

## Installation

### Use Brew

Use the third-party tap:

```sh
brew install simnalamburt/x/bunv
```

### Use Prebuilt Binaries

1. Uninstall [`bun`](https://bun.sh/docs/installation#uninstall) and remove `~/.bun/bin` from your path
2. Run installer:
   ```sh
   curl -sL https://raw.githubusercontent.com/Aternus/bunv/main/install.sh | sh
   ```
3. Add `~/.bunv/bin` to your `PATH`
   ```sh
   export PATH="$HOME/.bunv/bin:$PATH"
   ```
4. Ensure `which bun` outputs `~/.bunv/bin/bun`

### Build from Source

1. Uninstall [`bun`](https://bun.sh/docs/installation#uninstall) and remove `~/.bun/bin` from your path
2. Install [Zig](https://ziglang.org/) (>= 0.15.2)
3. Build the executables (`bun`, `bunx`, `bunv`)
   ```sh
   zig build -Doptimize=ReleaseFast --prefix ~/.bunv
   ```
4. Add `~/.bunv/bin` to your path:
   ```sh
   export PATH="$HOME/.bunv/bin:$PATH"
   ```
5. Ensure `which bun` outputs `~/.bunv/bin/bun`

## Usage

To use `bun` or `bunx`, just use it like normal:

```sh
$ bun i
$ bunx oxlint@latest
```

If you haven't installed the version of Bun required by your project, you'll be prompted to install it when running any
`bun` or `bunx` commands.

```sh
$ bun run main.ts
Bun v1.3.6 is not installed. Do you want to install it? [y/N] y
Installing...
✓ Done! Bun v1.3.6 is installed
```

Bunv also ships its own executable: `bunv`. Right now, it has 4 commands:

1. List installed versions:
   ```sh
   $ bunv
   Installed versions:
     v1.1.26
       │  Directory: ~/.bunv/versions/1.1.26
       │  Global:    ~/.bunv/versions/1.1.26/install/global
       └─ Bin:       ~/.bunv/versions/1.1.26/bin/bun
    v1.3.6
      │  Directory: ~/.bunv/versions/1.3.6
      │  Global:    ~/.bunv/versions/1.3.6/install/global
      └─ Bin:       ~/.bunv/versions/1.3.6/bin/bun
     ...
   ```
2. Remove an installed version:
   ```sh
   bunv rm 1.1.26
   ```
3. Remove Bun installations found on this machine:
   ```sh
   bunv prune
   # or skip confirmation
   bunv prune --yes
   ```
4. Show help:
   ```sh
   bunv help
   ```

If you're not in a project, Bunv will use the newest version installed locally, or if there is none, it will download
and install the latest release.

### Global Installs

Global installs are versioned. When you run `bun -g`, bunv sets Bun's global install directories to live under the
selected version (e.g. `~/.bunv/versions/<version>/install/global`). This keeps global packages isolated per Bun
version.

### Upgrading Bun

With bunv, `bun upgrade` doesn't do anything.

Instead, update the version of bun in your `package.json`, `.bun-version`, or `.tool-versions` file, and it will be
installed the next time you run a `bun` command.

```diff
// package.json
{
  ...
- "packageManager": "bun@1.3.5",
+ "packageManager": "bun@1.3.6",
  ...
}
```

### GitHub Actions

The `oven-sh/setup-bun`
action [already supports all the version files Bunv supports](https://github.com/oven-sh/setup-bun?tab=readme-ov-file#inputs) -
that means you don't have to install Bunv in CI - just use it locally.

```yml
# .github/workflows/validate
on:
  pull_request:

jobs:
  validate:
    runs_on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: oven-sh/setup-bun@v2
        with:
          bun-version-file: "package.json" # or ".tool-versions" or ".bun-version"
      # ...
```

## Benchmark

If you're using Bun, you probably love the CLI's incredible speed - so do I. That's why the only benchmark I focused on
is how much overhead it takes for Bunv to look up and execute the correct version of Bun.

So this benchmark measures the time it takes for `bun --version` to run.

```sh
$ hyperfine -N --warmup 10 --runs 1000 '~/.bunv/versions/1.1.26/bin/bun --version' '~/.bunv/bin/bun  --version'
Benchmark 1: ~/.bunv/versions/1.1.26/bin/bun --version
  Time (mean ± σ):       1.5 ms ±   0.1 ms    [User: 1.0 ms, System: 0.4 ms]
  Range (min … max):     1.3 ms …   2.3 ms    1000 runs

Benchmark 2: ~/.bunv/bin/bun  --version
  Time (mean ± σ):       2.0 ms ±   0.1 ms    [User: 1.0 ms, System: 0.9 ms]
  Range (min … max):     1.7 ms …   2.3 ms    1000 runs

Summary
  ~/.bunv/versions/1.1.26/bin/bun --version ran
  1.37 ± 0.12 times faster than ~/.bunv/bin/bun  --version
```

1.5ms without `bunv` vs 2.0ms with it. While it's technically 1.37x slower, it's only ***0.5ms of overhead*** -
unnoticeable to a human.

> [!NOTE]
> `hyperfine` struggles to accurately benchmark commands that exit in less than 5ms... If anyone knows a better way to
> benchmark this, please open a PR!

## Debugging

To print debug logs, set the `DEBUG` environment variable to `bunv`:

```sh
$ bun --version
1.3.6

$ DEBUG=bunv bun --version
Executable: utils.Cmd.bun
Home Dir: ~
Config Dir: ~/.bunv
Checking dir: ~/path/to/project
Found v1.3.6 in ~/path/to/project/package.json
Original args: { bun, --version }
Modified args: { ~/.bunv/versions/1.3.6/bin/bun, --version }
---
1.3.6
```

## Environment Variables

- `BUNV_AUTO_INSTALL=1` to auto-install missing versions without prompting (useful in non-interactive shells).
- `BUNV_INSTALL` to change the base install directory (defaults to `~/.bunv`).

## Troubleshooting

- `which bun` doesn't show `~/.bunv/bin/bun`: ensure `~/.bunv/bin` is at the front of your `PATH`.
- `bun upgrade` does nothing: update your version file instead (see [Upgrading Bun](#upgrading-bun)).
- No versions installed: run any `bun` command in a project with a version file or use `bun --version` to auto-install.

## Development

```sh
# Build all executables (bun, bunx, bunv) to ./zig-out/bin
$ zig build

# Build and run an executable
$ zig build bun
$ zig build bunx
$ zig build bunv

# Pass args to the executable
$ zig build
$ ./zig-out/bin/bun --version
$ ./zig-out/bin/bunx --version
$ ./zig-out/bin/bunv help

# Build and install production executables to ~/.bunv/bin
$ zig build -Doptimize=ReleaseFast --prefix ~/.bunv
```

## Release

To create a release, run the ["Release" action](https://github.com/Aternus/bunv/actions/workflows/release.yml).

This project uses conventional commits, so the release workflow will bump the version and create the GitHub release
automatically.
