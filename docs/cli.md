# CLI Reference

The sui CLI manages project creation, building, and running.

## Usage

```bash
haxelib run sui <command> [options]
```

## Commands

| Command | Description |
|---------|-------------|
| `init [name]` | Create a new project |
| `build [platform]` | Build for a platform |
| `run [platform]` | Build and run |
| `clean` | Remove build artifacts |
| `xcode [platform]` | Generate and open Xcode project |
| `help` | Show help |
| `version` | Show version |

## Platforms

| Platform | Description |
|----------|-------------|
| `macos` | macOS (default) |
| `ios` | iOS / iPadOS |
| `visionos` | visionOS |

## Options

| Flag | Description |
|------|-------------|
| `--device` | Build/run on a real device (requires signing) |
| `--device=NAME` | Target a specific device by name |
| `--release` | Build in Release configuration |
| `--verbose` / `-v` | Show xcodebuild output |
| `--xcode-only` | Generate Xcode project without building |
| `--watch` | Accepted, and a no-op: the [dynamic renderer](dynamic-renderer.md) is the default |
| `--static` | Build through the [decommissioned](render-paths.md) SwiftUI transpiler |

## Examples

```bash
# Create a new project
haxelib run sui init MyApp

# Build and run on macOS
haxelib run sui run macos

# Build for iOS simulator
haxelib run sui run ios

# Run on a connected iPhone
haxelib run sui run ios --device

# Run on a specific device
haxelib run sui run ios --device="iPhone 15 Pro"

# Build release configuration
haxelib run sui build macos --release

# Generate and open Xcode project
haxelib run sui xcode ios

# Clean build artifacts
haxelib run sui clean

# Verbose build output
haxelib run sui run macos --verbose
```

## Project Structure

After `init`, a project contains:

> **Which build file.** The tool reads `build-sui.hxml` if it is there, and
> `build.hxml` otherwise, and prints the one it compiled. A single-target
> project keeps the generic name; a project targeting several backends gives
> each its own, because that name can only belong to one of them -- and the
> tools that read it unconditionally compiled another backend's target,
> packaged whatever artefact was already lying about, and reported success.


```
MyApp/
  src/
    MyApp.hx          # App entry point
  build-sui.hxml       # Haxe compiler configuration (build.hxml also works)
  project.yml          # xcodegen project specification
```

After `build`, everything a platform needs lives under one directory named
after it:

```
MyApp/
  build/
    ios/
      cpp/             # generated C++, Build.xml, obj/, kui-payload.json
      swift/           # generated Swift
      lib/             # libhxcpp-sim.a (hxcpp's) and libhaxe.a (that + the bridge)
      Sources/         # what Xcode compiles
      Widget/          # the widget extension, when one is declared
      MyApp.xcodeproj/
      DerivedData/
      .sui-build-stamp
    macos/  visionos/  # the same shape, one per platform built
```

One directory per platform, so `rm -rf build/ios` is a complete per-platform
clean and no two platforms can see each other's output. They used to share
`build/cpp` and `build/swift`, which is how one platform's objects — and
another *backend*'s — ended up inside a library.

`clean` removes the whole `build/` tree.

A hand-run `haxe build-sui.hxml` still writes wherever its own `-cpp` says,
usually `build/cpp`. That tree belongs to whoever runs haxe directly; `sui
build` neither reads nor writes it.
