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
| `--watch` | Build the [dynamic renderer](dynamic-renderer.md) (runtime tree walk) instead of compiled Swift |

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

```
MyApp/
  src/
    MyApp.hx          # App entry point
  build.hxml           # Haxe compiler configuration
  project.yml          # xcodegen project specification
```

After `build`, additional artifacts are created:

```
MyApp/
  export/              # hxcpp C++ output
  generated/           # Generated Swift files
  build/               # Xcode build products
  project.xcodeproj/   # Generated Xcode project
```

Use `clean` to remove all generated artifacts.
