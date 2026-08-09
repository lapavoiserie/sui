package tools.cli;

/**
    Main entry point for the sui CLI.
    Invoked via `haxelib run sui <command> [args...]`
**/
class CLI {
    static function main() {
        var args = Sys.args();

        // haxelib passes the calling directory as the last argument.
        // Detect this: if the last arg is an existing directory, treat it as CWD.
        var cwd = Sys.getCwd();
        if (args.length > 0) {
            var last = args[args.length - 1];
            if (!StringTools.startsWith(last, "-") && sys.FileSystem.exists(last) && sys.FileSystem.isDirectory(last)) {
                cwd = args.pop();
            }
        }

        if (args.length == 0) {
            printUsage();
            return;
        }

        var command = args[0];
        var commandArgs = args.slice(1);

        switch (command) {
            case "init":
                Init.run(cwd, commandArgs);
            case "build":
                Build.run(cwd, commandArgs);
            case "run":
                Run.run(cwd, commandArgs);
            case "clean":
                clean(cwd);
            case "xcode":
                xcode(cwd, commandArgs);
            case "help" | "--help" | "-h":
                printUsage();
            case "version" | "--version" | "-v":
                Sys.println("sui 0.1.0");
            default:
                Sys.println('Unknown command: $command');
                printUsage();
                Sys.exit(1);
        }
    }

    static function clean(cwd:String) {
        Sys.println("Cleaning build artifacts...");
        var buildDir = '$cwd/build';
        if (sys.FileSystem.exists(buildDir)) {
            removeDirectory(buildDir);
        }
        Sys.println("Done.");
    }

    static function xcode(cwd:String, args:Array<String>) {
        var platform = if (args.length > 0) args[0] else "macos";
        Sys.println('Generating Xcode project for $platform...');
        Build.run(cwd, [platform, "--xcode-only"]);

        var xcprojPath = '$cwd/build/$platform/*.xcodeproj';
        Sys.command("open", ['$cwd/build/$platform/']);
    }

    static function printUsage() {
        Sys.println("
sui — Build native Apple platform apps in Haxe

Usage: sui <command> [options]

Commands:
  init [name]          Scaffold a new sui project
  build [platform]     Build for macos|ios|visionos (default: macos)
  run [platform]       Build and run (simulator for ios/visionos)
  clean                Remove build artifacts
  xcode [platform]     Generate and open Xcode project
  help                 Show this help message
  version              Show version

Platforms:
  macos                macOS (default)
  ios                  iOS (simulator by default)
  visionos             visionOS (simulator by default)

Options:
  --device             Build/run on a real device (requires signing)
  --device=NAME        Target a specific device by name
  --release            Build Release configuration
  --verbose / -v       Show xcodebuild output
  --xcode-only         Generate Xcode project without building
  --static             Build through the decommissioned SwiftUI transpiler

Signing:
  Add \"teamId\" to sui.json for device builds.
  Auto-detected from keychain if available.

Examples:
  sui init MyApp
  sui build macos
  sui run ios
  sui run ios --device
  sui build ios --device=iPhone
");
    }

    static function removeDirectory(path:String) {
        if (sys.FileSystem.isDirectory(path)) {
            for (entry in sys.FileSystem.readDirectory(path)) {
                removeDirectory('$path/$entry');
            }
            sys.FileSystem.deleteDirectory(path);
        } else {
            sys.FileSystem.deleteFile(path);
        }
    }
}
