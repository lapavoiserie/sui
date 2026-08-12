package tools.cli;

import sys.io.File;
import sys.FileSystem;

using StringTools;

/**
    Build pipeline for sui projects.

    Pipeline:
    1. haxe build.hxml → C++ library (hxcpp) + Swift files (macro) in one step
    2. Assemble Xcode project: copy Swift + runtime, generate project.yml
    3. xcodegen + xcodebuild → native .app

    Flags:
    --device        Build for a real device (requires signing)
    --device=NAME   Build for a specific device name
    --release       Build Release configuration
    --xcode-only    Generate Xcode project without building
    --static        Build through the decommissioned SwiftUI transpiler
    --verbose / -v  Show xcodebuild output
**/
class Build {
    public static function run(cwd:String, args:Array<String>) {
        var platform = if (args.length > 0 && !args[0].startsWith("-")) args[0] else "macos";
        var xcodeOnly = args.indexOf("--xcode-only") != -1;
        var verbose = args.indexOf("--verbose") != -1 || args.indexOf("-v") != -1;
        var release = args.indexOf("--release") != -1;
        // The dynamic renderer is the path. `--watch` and `--hot-reload` are
        // still accepted -- they name what already happens -- and `--static`
        // opts back in to the decommissioned transpiler.
        var staticPath = args.indexOf("--static") != -1;
        var hotReload = !staticPath;
        var configuration = release ? "Release" : "Debug";

        // Device flag: --device or --device=MyiPhone
        var forDevice = false;
        var deviceName:String = null;
        for (arg in args) {
            if (arg == "--device") {
                forDevice = true;
            } else if (arg.startsWith("--device=")) {
                forDevice = true;
                deviceName = arg.substr(9);
            }
        }

        if (platform != "macos" && platform != "ios" && platform != "visionos") {
            Sys.println('Unknown platform: $platform. Use macos, ios, or visionos.');
            Sys.exit(1);
            return;
        }

        var config = readProjectConfig(cwd);
        var target = if (forDevice) '$platform device' else '$platform simulator';
        if (platform == "macos") target = "macos";
        Sys.println('Building ${config.appName} for $target...');

        // Device builds require a team ID for signing
        if (forDevice && config.teamId == null) {
            // Try auto-detecting from keychain
            var detectedTeam = detectTeamId();
            if (detectedTeam != null) {
                config.teamId = detectedTeam;
                Sys.println('Auto-detected team ID: ${config.teamId}');
            } else {
                Sys.println('Error: Device builds require a team ID for code signing.');
                Sys.println('Add "teamId": "YOUR_TEAM_ID" to sui.json');
                Sys.println('Or run: security find-certificate -c "Apple Development" | grep OU');
                Sys.exit(1);
                return;
            }
        }

        var buildDir = '$cwd/build/$platform';
        ensureDirectory(buildDir);
        ensureDirectory('$buildDir/Sources');

        // Step 1: Run Haxe compiler — generates both C++ and Swift via macro
        // Check if we can skip recompilation (incremental rebuild)
        var oldCwd = Sys.getCwd();
        var needsRecompile = !isHxcppUpToDate(cwd, platform, hotReload);

        if (needsRecompile) {
            Sys.println("[1/3] Compiling Haxe (C++ & Swift generation)...");
            Sys.setCwd(cwd);
            // Pass platform define for conditional compilation (#if sui_ios, #if sui_macos, #if sui_visionos)
            var buildFile = resolveBuildFile();
            if (buildFile == null) {
                Sys.println("Error: no build file. Looked for build-sui.hxml, then build.hxml.");
                Sys.exit(1);
            }
            Sys.println('  Compiling $buildFile');
            var haxeArgs = [buildFile, "-D", 'sui_$platform'];
            // Dynamic renderer: SwiftGenerator emits SuiBootC.cpp and force-keeps
            // the bridge classes only under this define.
            if (staticPath) { haxeArgs.push("-D"); haxeArgs.push("sui_static"); }
            // For non-macOS targets, tell hxcpp to cross-compile for the correct platform
            if (platform == "ios") {
                haxeArgs.push("-D");
                haxeArgs.push(forDevice ? "iphoneos" : "iphonesim");
            } else if (platform == "visionos") {
                haxeArgs.push("-D");
                haxeArgs.push(forDevice ? "xros" : "xrsimulator");
            }
            var haxeResult = Sys.command("haxe", haxeArgs);
            Sys.setCwd(oldCwd);
            if (haxeResult != 0) {
                Sys.println("Error: Haxe compilation failed.");
                Sys.exit(1);
            }
            // Record what this output is for, so the next build can tell
            // "nothing changed" from "you asked for something else".
            try {
                File.saveContent(stampPath(cwd), buildStamp(platform, hotReload));
            } catch (_:Dynamic) {}
        } else {
            Sys.println("[1/3] Haxe unchanged, skipping recompilation...");
        }

        // Check for generated files
        var swiftGenDir = '$cwd/build/swift';
        if (!FileSystem.exists(swiftGenDir)) {
            Sys.println("Error: No Swift files generated. Is --macro sui.macros.SwiftGenerator.register() in build.hxml?");
            Sys.exit(1);
        }

        // Auto-detect bridge app: macro generates HaxeBridgeC.cpp when bridge is needed
        var isBridgeApp = FileSystem.exists('$swiftGenDir/HaxeBridgeC.cpp');
        // The dynamic (hot-reload) renderer needs the same native-bridge scaffold
        // — hxcpp static lib + a compiled C bridge — even when the app has no
        // action closures (so no HaxeBridgeC.cpp). Treat both the same way.
        var nativeBridge = isBridgeApp || hotReload;

        if (nativeBridge) {
            ensureDirectory('$buildDir/lib');

            // `ar rcs` *updates* an archive: a member from the previous build
            // stays in it unless something replaces it by name. Switching
            // render paths leaves the other one's bridge object behind, and the
            // two define the same extern "C" entry points -- "duplicate symbol
            // _haxe_bridge_invoke_action", from a file this build never
            // compiled. Start the archive empty instead.
            if (needsRecompile && FileSystem.exists('$buildDir/lib/libhaxe.a')) {
                FileSystem.deleteFile('$buildDir/lib/libhaxe.a');
            }

            if (needsRecompile || !FileSystem.exists('$buildDir/lib/libhaxe.a')) {
                // Step 2: Build hxcpp static library + compile C++ bridge
                Sys.println("[2/4] Building hxcpp static library + C++ bridge...");
            } else {
                Sys.println("[2/4] Bridge unchanged, skipping...");
            }

            // Create static library from hxcpp object files (excluding __main__.o)
            // hxcpp keeps one directory per toolchain under obj/, and a project
            // built for more than one platform keeps them all: darwinarm64
            // beside iphonesim-c11. Archiving the lot mixes arm64 and x86_64
            // objects, and `ar` answers "Inappropriate file type or format" --
            // which reads as a broken build rather than as two builds in one
            // box. Take only the toolchain this target uses.
            var cppObjDir = objDirFor('$cwd/build/cpp/obj', platform, forDevice);
            if (cppObjDir != null && FileSystem.exists(cppObjDir)) {
                // Collect all .o files
                var oFiles:Array<String> = [];
                collectObjectFiles(cppObjDir, oFiles);
                if (oFiles.length > 0) {
                    var arArgs = ["rcs", '$buildDir/lib/libhaxe.a'];
                    for (o in oFiles) arArgs.push(o);
                    Sys.command("ar", arArgs);
                }
            }

            // Find hxcpp include path
            var hxcppDir = findHxcppDir();

            // Compile the C++ bridge against hxcpp headers.
            // Architecture must match hxcpp's output:
            //   macOS / iphoneos (device): arm64
            //   iphonesim (simulator): x86_64 (hxcpp iphonesim-toolchain hardcodes this)
            var isSimulator = !forDevice && (platform == "ios" || platform == "visionos");
            var bridgeArch = isSimulator ? "x86_64" : "arm64";
            var platformDefine = switch (platform) {
                case "ios": forDevice ? "-DHX_IOS" : "-DIPHONESIM=IPHONESIM";
                case "visionos": "-DHX_VISIONOS";
                default: "-DHX_MACOS";
            };
            var clangArgs = [
                "-c", "-std=c++17",
                '-I$hxcppDir/include',
                '-I$cwd/build/cpp/include',
                platformDefine, "-DHXCPP_M64",
                "-DHXCPP_VISIT_ALLOCS", "-DHX_SMART_STRINGS",
                "-DHXCPP_API_LEVEL=430",
                "-arch", bridgeArch,
            ];
            if (bridgeArch == "arm64") clangArgs.push("-DHXCPP_ARM64");
            if (platform != "macos") {
                var sdk = switch (platform) {
                    case "ios": forDevice ? "iphoneos" : "iphonesimulator";
                    case "visionos": forDevice ? "xros" : "xrsimulator";
                    default: "macosx";
                };
                clangArgs.push("-isysroot");
                clangArgs.push(getSdkPath(sdk));
            }
            // The C++ bridge sources to compile into the static library:
            //   - HaxeBridgeC.cpp   — static bridge (@:expose fns, action dispatch)
            //   - ViewNodeBridgeC.cpp + SuiBootC.cpp — dynamic renderer + bootstrap
            var libPath = getLibPath();
            var bridgeSources:Array<{src:String, obj:String}> = [];
            if (isBridgeApp)
                bridgeSources.push({src: '$swiftGenDir/HaxeBridgeC.cpp', obj: '$buildDir/lib/HaxeBridgeC.o'});
            if (hotReload) {
                bridgeSources.push({src: '$libPath/runtime/ViewNodeBridgeC.cpp', obj: '$buildDir/lib/ViewNodeBridgeC.o'});
                bridgeSources.push({src: '$swiftGenDir/SuiBootC.cpp', obj: '$buildDir/lib/SuiBootC.o'});
            }
            for (bs in bridgeSources) {
                if (!FileSystem.exists(bs.src)) {
                    Sys.println('Error: expected C++ bridge source missing: ${bs.src}');
                    Sys.exit(1);
                }
                var cargs = clangArgs.copy();
                cargs.push(bs.src);
                cargs.push("-o");
                cargs.push(bs.obj);
                if (Sys.command("clang++", cargs) != 0) {
                    Sys.println('Error: C++ bridge compilation failed for ${bs.src}.');
                    Sys.exit(1);
                }
                // Add the bridge object to the static library
                Sys.command("ar", ["rcs", '$buildDir/lib/libhaxe.a', bs.obj]);
            }
        }

        // Step N: Assemble Xcode project
        var stepNum = nativeBridge ? 3 : 2;
        var totalSteps = nativeBridge ? 4 : 3;
        Sys.println('[$stepNum/$totalSteps] Assembling Xcode project...');

        // Assembled from scratch: what is left over belongs to another build.
        clearSources(buildDir);

        // Copy Swift files (skip .cpp/.h for bridge — they're in the static lib)
        for (file in FileSystem.readDirectory(swiftGenDir)) {
            if (file.endsWith(".swift")) {
                File.copy('$swiftGenDir/$file', '$buildDir/Sources/$file');
            }
        }
        // Copy bridge header if present
        if (isBridgeApp && FileSystem.exists('$swiftGenDir/HaxeBridgeC.h')) {
            File.copy('$swiftGenDir/HaxeBridgeC.h', '$buildDir/Sources/HaxeBridgeC.h');
        }

        // Copy runtime Swift files from sui library
        copyRuntimeFiles(buildDir);

        // Hot reload mode: include DynamicView renderer and ViewNode bridge
        if (hotReload) {
            copyHotReloadFiles(buildDir);
        }

        // Umbrella bridging header: Xcode exposes exactly one bridging header to
        // Swift, but a hot-reload app may need both the static bridge (actions)
        // and the dynamic ViewNode bridge. Generate one that includes whichever
        // headers are present.
        if (nativeBridge) {
            var umbrella = new StringBuf();
            umbrella.add("// AUTO-GENERATED — Swift ↔ hxcpp bridging umbrella header.\n");
            if (FileSystem.exists('$buildDir/Sources/HaxeBridgeC.h'))
                umbrella.add("#include \"HaxeBridgeC.h\"\n");
            if (FileSystem.exists('$buildDir/Sources/ViewNodeBridgeC.h'))
                umbrella.add("#include \"ViewNodeBridgeC.h\"\n");
            File.saveContent('$buildDir/Sources/SuiBridging.h', umbrella.toString());
        }

        // Copy user-provided Swift files from swift/ directory
        copyUserSwiftFiles(cwd, buildDir);

        // Generate project.yml
        File.saveContent('$buildDir/project.yml', generateProjectYaml(config, platform, forDevice, nativeBridge));

        if (xcodeOnly) {
            runXcodegen(buildDir);
            Sys.println("Xcode project generated at: $buildDir/");
            return;
        }

        // Final step: xcodegen + xcodebuild
        Sys.println('[$totalSteps/$totalSteps] Building with Xcode...');
        runXcodegen(buildDir);

        var xcodeArgs = [
            "build",
            "-project",
            '${config.appName}.xcodeproj',
            "-scheme",
            config.appName,
            "-configuration",
            configuration,
            "-derivedDataPath",
            "./DerivedData",
        ];

        // Add destination
        xcodeArgs = xcodeArgs.concat(destinationArgs(platform, forDevice, deviceName));

        // Device builds need to allow provisioning
        if (forDevice) {
            xcodeArgs = xcodeArgs.concat([
                "-allowProvisioningUpdates",
            ]);
        }

        if (!verbose) xcodeArgs.push("-quiet");

        Sys.setCwd(buildDir);
        var buildResult = Sys.command("xcodebuild", xcodeArgs);
        Sys.setCwd(oldCwd);

        if (buildResult != 0) {
            Sys.println("Error: xcodebuild failed.");
            Sys.exit(1);
        }

        Sys.println("Build successful!");
    }

    public static function destinationArgs(platform:String, forDevice:Bool, ?deviceName:String):Array<String> {
        if (platform == "macos") return [];

        if (forDevice) {
            // Use specific device UUID so Xcode registers it and creates the right provisioning profile
            var udid = findConnectedDeviceUdid(deviceName);
            if (udid != null)
                return ["-destination", 'platform=${platform == "ios" ? "iOS" : "visionOS"},id=$udid'];
            // Fallback to generic
            return ["-destination", 'generic/platform=${platform == "ios" ? "iOS" : "visionOS"}'];
        }

        // Simulator. The arch is x86_64 to match hxcpp's iphonesim toolchain,
        // which builds for it whatever the host.
        //
        // The device is *asked for*, not named here. A hardcoded "iPhone 16"
        // fails on any machine whose Xcode ships a different set -- with
        // "Unable to find a device matching the provided destination
        // specifier", which points at the destination rather than at the fact
        // that the name is a guess about someone else's install.
        return switch (platform) {
            case "ios":
                var device = firstAvailableSimulator("iPhone");
                device == null
                    ? ["-destination", "generic/platform=iOS Simulator"]
                    : ["-destination", 'platform=iOS Simulator,id=$device,arch=x86_64'];
            case "visionos":
                var device = firstAvailableSimulator("Apple Vision");
                device == null
                    ? ["-destination", "generic/platform=visionOS Simulator"]
                    : ["-destination", 'platform=visionOS Simulator,id=$device'];
            default: [];
        }
    }

    /**
        A simulator that actually exists on this machine, preferring a booted one.

        `simctl` answers with what is installed rather than what we hoped for,
        and a booted device is almost always the one the developer is looking at.
    **/
    static function firstAvailableSimulator(nameContains:String):Null<String> {
        for (onlyBooted in [true, false]) {
            try {
                var args = ["simctl", "list", "devices", "available"];
                if (onlyBooted) args.push("booted");
                var proc = new sys.io.Process("xcrun", args);
                var out = proc.stdout.readAll().toString();
                proc.close();
                var udid = ~/\(([0-9A-F]{8}-[0-9A-F-]{27})\)/i;
                for (line in out.split("\n")) {
                    if (line.indexOf(nameContains) < 0) continue;
                    if (line.indexOf("unavailable") >= 0) continue;
                    if (udid.match(line)) return udid.matched(1);
                }
            } catch (_:Dynamic) {}
        }
        return null;
    }

    /** Find a connected device UUID by parsing xcodebuild destination list. **/
    public static function findConnectedDeviceUdid(?name:String):String {
        try {
            // Use xcodebuild to list destinations — its device IDs are the ones xcodebuild accepts
            var proc = new sys.io.Process("xcrun", ["xctrace", "list", "devices"]);
            var output = proc.stdout.readAll().toString();
            proc.close();

            // Parse lines like: "iPhone (2) (18.3.2) (00008110-001A59A83621801E)"
            for (line in output.split("\n")) {
                // Skip simulators (they appear after "== Simulators ==" header)
                if (line.indexOf("Simulator") != -1) break;
                if (line.indexOf("== ") != -1) continue;

                // Extract UUID in parentheses at end of line
                var udid = extractParenUuid(line);
                if (udid == null) continue;

                if (name != null) {
                    if (line.toLowerCase().indexOf(name.toLowerCase()) != -1) return udid;
                } else {
                    // Return first real device (skip Mac)
                    if (line.indexOf("Mac") == -1) return udid;
                }
            }
        } catch (e:Dynamic) {}
        return null;
    }

    /** Extract a UUID/UDID from parentheses at end of a line. **/
    static function extractParenUuid(line:String):String {
        var lastParen = line.lastIndexOf("(");
        if (lastParen == -1) return null;
        var endParen = line.indexOf(")", lastParen);
        if (endParen == -1) return null;
        var content = line.substring(lastParen + 1, endParen);
        // Must look like a device ID (contains hex and dashes, 16+ chars)
        if (content.length >= 16 && content.indexOf("-") != -1) return content;
        return null;
    }

    static function extractUuid(line:String):String {
        var i = 0;
        while (i < line.length - 35) {
            if (isHexBlock(line, i, 8) && line.charAt(i + 8) == "-" &&
                isHexBlock(line, i + 9, 4) && line.charAt(i + 13) == "-" &&
                isHexBlock(line, i + 14, 4) && line.charAt(i + 18) == "-" &&
                isHexBlock(line, i + 19, 4) && line.charAt(i + 23) == "-" &&
                isHexBlock(line, i + 24, 12)) {
                return line.substr(i, 36);
            }
            i++;
        }
        return null;
    }

    static function isHexBlock(s:String, start:Int, len:Int):Bool {
        for (j in 0...len) {
            var c = s.charCodeAt(start + j);
            if (!((c >= 48 && c <= 57) || (c >= 65 && c <= 70) || (c >= 97 && c <= 102))) return false;
        }
        return true;
    }

    static function runXcodegen(buildDir:String) {
        var oldCwd = Sys.getCwd();
        Sys.setCwd(buildDir);
        var result = Sys.command("xcodegen", ["generate"]);
        Sys.setCwd(oldCwd);
        if (result != 0) {
            Sys.println("Error: xcodegen failed. Is it installed? (brew install xcodegen)");
            Sys.exit(1);
        }
    }

    /** Empty the Sources directory before assembling it.

        Every file in there is copied or generated by this build, so nothing is
        lost -- and what is *not* re-copied is precisely the problem: the static
        path's `AppState.swift` and `HaxeBridgeC.swift` stayed behind in a
        dynamic project, referring to symbols the dynamic library does not
        export. Xcode compiled them because they were on disk, not because
        anything asked for them. **/
    static function clearSources(buildDir:String) {
        var dir = '$buildDir/Sources';
        if (!FileSystem.exists(dir)) return;
        for (entry in FileSystem.readDirectory(dir)) {
            var path = '$dir/$entry';
            if (!FileSystem.isDirectory(path)) FileSystem.deleteFile(path);
        }
    }

    static function copyRuntimeFiles(buildDir:String) {
        var libPath = getLibPath();
        var runtimeDir = '$libPath/runtime/swift';

        if (FileSystem.exists(runtimeDir)) {
            for (file in FileSystem.readDirectory(runtimeDir)) {
                if (file.endsWith(".swift")) {
                    File.copy('$runtimeDir/$file', '$buildDir/Sources/$file');
                }
            }
        } else {
            Sys.println("Warning: Runtime Swift files not found at $runtimeDir");
        }
    }

    static function copyHotReloadFiles(buildDir:String) {
        var libPath = getLibPath();

        // Copy DynamicView.swift (the runtime SwiftUI renderer)
        var dynamicView = '$libPath/runtime/DynamicView.swift';
        if (FileSystem.exists(dynamicView)) {
            File.copy(dynamicView, '$buildDir/Sources/DynamicView.swift');
        }

        // Copy ViewNode bridge header
        var bridgeHeader = '$libPath/runtime/ViewNodeBridgeC.h';
        if (FileSystem.exists(bridgeHeader)) {
            File.copy(bridgeHeader, '$buildDir/Sources/ViewNodeBridgeC.h');
        }

        // Point ContentView at the runtime renderer rather than generated views
        var contentView = '$buildDir/Sources/ContentView.swift';
        if (FileSystem.exists(contentView)) {
            var content = File.getContent(contentView);
            // Replace the body of MainScreen with HotReloadRootView
            // The generated ContentView has a MainScreen() function — wrap it
            // App.swift instantiates ContentView() — replace the generated
            // static view with one that hosts the runtime DynamicView renderer.
            var hotReloadWrapper = "// Hot reload mode — uses DynamicView renderer\n"
                + "import SwiftUI\n\n"
                + "struct ContentView: View {\n"
                + "    var body: some View {\n"
                + "        HotReloadRootView()\n"
                + "    }\n"
                + "}\n";
            File.saveContent(contentView, hotReloadWrapper);
        }

        Sys.println("  [renderer] DynamicView walks the tree at runtime");
    }

    static function copyUserSwiftFiles(cwd:String, buildDir:String) {
        var swiftDir = '$cwd/swift';
        if (FileSystem.exists(swiftDir)) {
            for (file in FileSystem.readDirectory(swiftDir)) {
                if (file.endsWith(".swift")) {
                    File.copy('$swiftDir/$file', '$buildDir/Sources/$file');
                }
            }
        }
    }

    public static function readProjectConfig(cwd:String):ProjectConfig {
        var configPath = '$cwd/sui.json';
        if (FileSystem.exists(configPath)) {
            var content = File.getContent(configPath);
            var json = haxe.Json.parse(content);
            var packages:Array<SwiftPackage> = null;
            if (json.swiftPackages != null) {
                packages = [];
                var arr:Array<Dynamic> = json.swiftPackages;
                for (pkg in arr) {
                    packages.push({url: pkg.url, from: pkg.from, product: pkg.product});
                }
            }
            var frameworks:Array<String> = null;
            if (json.frameworks != null) {
                frameworks = [];
                var fw:Array<Dynamic> = json.frameworks;
                for (f in fw) frameworks.push(Std.string(f));
            }
            return {
                appName: json.appName,
                bundleIdentifier: json.bundleIdentifier,
                bundleIdPrefix: json.bundleIdPrefix != null ? json.bundleIdPrefix : "com.example",
                teamId: json.teamId,
                swiftPackages: packages,
                frameworks: frameworks,
            };
        }

        // Fallback: derive from directory name
        var dirName = haxe.io.Path.withoutDirectory(cwd.endsWith("/") ? cwd.substr(0, cwd.length - 1) : cwd);
        return {
            appName: dirName,
            bundleIdentifier: 'com.example.${dirName.toLowerCase()}',
            bundleIdPrefix: "com.example",
            teamId: null,
        };
    }

    public static function findBuiltApp(cwd:String, appName:String, platform:String, forDevice:Bool = false):String {
        var buildDir = '$cwd/build/$platform';

        // Order matters: device paths first when --device, simulator paths first otherwise
        var devicePaths = [
            '$buildDir/DerivedData/Build/Products/Debug-iphoneos/$appName.app',
            '$buildDir/DerivedData/Build/Products/Release-iphoneos/$appName.app',
            '$buildDir/DerivedData/Build/Products/Debug-xros/$appName.app',
            '$buildDir/DerivedData/Build/Products/Release-xros/$appName.app',
        ];
        var simPaths = [
            '$buildDir/DerivedData/Build/Products/Debug-iphonesimulator/$appName.app',
            '$buildDir/DerivedData/Build/Products/Debug-xrsimulator/$appName.app',
            '$buildDir/DerivedData/Build/Products/Debug/$appName.app',
            '$buildDir/DerivedData/Build/Products/Release/$appName.app',
        ];

        var paths = if (forDevice) devicePaths.concat(simPaths) else simPaths.concat(devicePaths);
        for (p in paths) {
            if (FileSystem.exists(p)) return p;
        }
        return null;
    }

    /** Auto-detect Apple Development team ID from keychain. **/
    static function detectTeamId():String {
        try {
            var proc = new sys.io.Process("security", ["find-certificate", "-c", "Apple Development", "-p"]);
            var pem = proc.stdout.readAll().toString();
            proc.close();
            if (pem.length > 0) {
                var proc2 = new sys.io.Process("openssl", ["x509", "-noout", "-subject"]);
                proc2.stdin.writeString(pem);
                proc2.stdin.close();
                var subject = proc2.stdout.readAll().toString();
                proc2.close();
                // Extract OU=XXXXXXXXXX from subject
                var ouIdx = subject.indexOf("OU = ");
                if (ouIdx != -1) {
                    var ouEnd = subject.indexOf(",", ouIdx);
                    if (ouEnd == -1) ouEnd = subject.length;
                    return subject.substring(ouIdx + 5, ouEnd).trim();
                }
            }
        } catch (e:Dynamic) {}
        return null;
    }

    static function getLibPath():String {
        try {
            var proc = new sys.io.Process("haxelib", ["libpath", "sui"]);
            var path = proc.stdout.readAll().toString().trim();
            proc.close();
            if (path.length > 0 && FileSystem.exists('$path/runtime/swift')) return path;
        } catch (e:Dynamic) {}

        var dir = Sys.getCwd();
        for (_ in 0...5) {
            if (FileSystem.exists('$dir/runtime/swift')) return dir;
            dir = haxe.io.Path.directory(dir);
        }

        return Sys.getCwd();
    }

    static function ensureDirectory(path:String) {
        if (!FileSystem.exists(path)) {
            FileSystem.createDirectory(path);
        }
    }

    /** Check if hxcpp output is up-to-date (all .hx source files are older than build output). **/
    /** What the output in `build/` was produced for. **/
    /**
        The build file to compile: this backend's own, or the generic one.

        Compiling `build.hxml` unconditionally is right for a project targeting
        one backend, and quietly wrong for one targeting several. `mui`'s
        kitchen sink has three, and the generic name could only belong to one of
        them -- so the other two tools compiled *this* one's target, packaged
        whatever artefact was already lying about, and reported success. A
        backend that had not compiled in months looked healthy.

        A backend now prefers the file named after it. The generic name still
        works, and is what a single-target project keeps.
    **/
    static function resolveBuildFile():Null<String> {
        for (name in ["build-sui.hxml", "build.hxml"]) {
            if (FileSystem.exists(name)) return name;
        }
        return null;
    }

    static function buildStamp(platform:String, hotReload:Bool):String {
        return platform + "|" + (hotReload ? "dynamic" : "static");
    }

    static function stampPath(cwd:String):String {
        return '$cwd/build/.sui-build-mode';
    }

    static function isHxcppUpToDate(cwd:String, platform:String, hotReload:Bool):Bool {
        var swiftDir = '$cwd/build/swift';
        var cppDir = '$cwd/build/cpp';

        // Must have previous build output
        if (!FileSystem.exists(swiftDir) || !FileSystem.exists(cppDir)) return false;

        // Output produced for a different platform or render path is not "up to
        // date" -- it is output for another build.
        //
        // Timestamps alone said it was: switching from a static build to
        // `--watch` touches no source file, so the compile was skipped and the
        // static build's Swift was copied into a dynamic project. That failed as
        // "cannot find 'AppState' in scope" -- a name from a mode the developer
        // had just left, in a file they never wrote.
        var stamp = stampPath(cwd);
        if (!FileSystem.exists(stamp)) return false;
        try {
            if (StringTools.trim(File.getContent(stamp)) != buildStamp(platform, hotReload)) return false;
        } catch (_:Dynamic) {
            return false;
        }

        // Find newest .hx source file across all source directories
        var newestSource:Float = 0;
        var srcDir = '$cwd/src';
        if (FileSystem.exists(srcDir)) newestSource = Math.max(newestSource, newestModTime(srcDir, ".hx"));
        // Also check the sui library source
        var libSrc = getLibPath() + "/src";
        if (FileSystem.exists(libSrc)) newestSource = Math.max(newestSource, newestModTime(libSrc, ".hx"));
        // Check build.hxml
        if (FileSystem.exists('$cwd/build.hxml')) {
            var stat = FileSystem.stat('$cwd/build.hxml');
            newestSource = Math.max(newestSource, stat.mtime.getTime());
        }
        // Check sui.json
        if (FileSystem.exists('$cwd/sui.json')) {
            var stat = FileSystem.stat('$cwd/sui.json');
            newestSource = Math.max(newestSource, stat.mtime.getTime());
        }
        // Check user Swift files
        var userSwiftDir = '$cwd/swift';
        if (FileSystem.exists(userSwiftDir)) newestSource = Math.max(newestSource, newestModTime(userSwiftDir, ".swift"));

        if (newestSource == 0) return false;

        // Find oldest Swift output file
        var oldestOutput = newestModTime(swiftDir, ".swift");
        if (oldestOutput == 0) return false;

        return newestSource < oldestOutput;
    }

    /** Get the newest modification time of files with given extension in a directory (recursive). **/
    static function newestModTime(dir:String, ext:String):Float {
        var newest:Float = 0;
        if (!FileSystem.exists(dir)) return 0;
        for (entry in FileSystem.readDirectory(dir)) {
            var path = '$dir/$entry';
            if (FileSystem.isDirectory(path)) {
                var sub = newestModTime(path, ext);
                if (sub > newest) newest = sub;
            } else if (entry.endsWith(ext)) {
                var stat = FileSystem.stat(path);
                var time = stat.mtime.getTime();
                if (time > newest) newest = time;
            }
        }
        return newest;
    }

    /** Recursively collect .o files, excluding __main__.o **/
    /**
        The hxcpp toolchain directory this target's objects are in.

        Named by hxcpp, not by us: `darwinarm64` / `darwin64` for macOS,
        `iphonesim-*` for the simulator, `iphoneos-*` for a device. Matching by
        prefix rather than listing exact names keeps this working when hxcpp
        changes a suffix, which is where the `-c11` comes from.

        Returns null when nothing matches, so the caller reports a missing build
        rather than archiving another platform's objects.
    **/
    static function objDirFor(objRoot:String, platform:String, forDevice:Bool):Null<String> {
        if (!FileSystem.exists(objRoot)) return null;

        var prefixes = switch (platform) {
            case "ios": forDevice ? ["iphoneos"] : ["iphonesim"];
            case "visionos": forDevice ? ["xros", "appletvos"] : ["xrsim", "iphonesim"];
            default: ["darwin", "mac"];
        };

        for (entry in FileSystem.readDirectory(objRoot)) {
            var path = '$objRoot/$entry';
            if (!FileSystem.isDirectory(path)) continue;
            for (prefix in prefixes) {
                if (StringTools.startsWith(entry, prefix)) return path;
            }
        }
        return null;
    }

    static function collectObjectFiles(dir:String, result:Array<String>) {
        for (entry in FileSystem.readDirectory(dir)) {
            var path = '$dir/$entry';
            if (FileSystem.isDirectory(path)) {
                collectObjectFiles(path, result);
            } else if (entry.endsWith(".o") && entry.indexOf("__main__") == -1) {
                result.push(path);
            }
        }
    }

    /** Find the hxcpp include directory. **/
    static function findHxcppDir():String {
        try {
            var proc = new sys.io.Process("haxelib", ["libpath", "hxcpp"]);
            var path = StringTools.trim(proc.stdout.readAll().toString());
            proc.close();
            if (path.length > 0 && FileSystem.exists('$path/include')) return path;
        } catch (e:Dynamic) {}

        // Fallback: common location
        var common = "/usr/local/lib/haxe/lib/hxcpp/4,3,2";
        if (FileSystem.exists(common)) return common;

        return "/usr/local/lib/haxe/lib/hxcpp";
    }

    static function getSdkPath(sdk:String):String {
        try {
            var proc = new sys.io.Process("xcrun", ["--sdk", sdk, "--show-sdk-path"]);
            var path = StringTools.trim(proc.stdout.readAll().toString());
            proc.close();
            if (path.length > 0) return path;
        } catch (e:Dynamic) {}
        return "";
    }

    // --- Project generation ---

    static function deploymentTarget(platform:String):String {
        return switch (platform) {
            case "macos": "14.0";
            case "ios": "17.0";
            case "visionos": "2.0";
            default: "14.0";
        };
    }

    static function platformKey(platform:String):String {
        return switch (platform) {
            case "macos": "macOS";
            case "ios": "iOS";
            case "visionos": "visionOS";
            default: "macOS";
        };
    }

    static function generateProjectYaml(config:ProjectConfig, platform:String, forDevice:Bool, nativeBridge:Bool = false):String {
        var pk = platformKey(platform);
        var dt = deploymentTarget(platform);

        var signing = "";
        if (forDevice && config.teamId != null) {
            signing = '      CODE_SIGN_IDENTITY: "Apple Development"
      DEVELOPMENT_TEAM: "${config.teamId}"
      CODE_SIGN_STYLE: Automatic
';
        }

        // Compose the target settings: the native-bridge scaffold (bridging
        // header + hxcpp static lib) plus any system frameworks the *app*
        // declares in sui.json — dependencies belong to the app, not the core.
        var ldflags:Array<String> = [];
        if (nativeBridge) {
            ldflags.push("-lhaxe");
            ldflags.push("-lc++");
        }
        if (config.frameworks != null)
            for (fw in config.frameworks) {
                ldflags.push("-framework");
                ldflags.push(fw);
            }
        var bridge = "";
        if (nativeBridge) {
            bridge += '      SWIFT_OBJC_BRIDGING_HEADER: Sources/SuiBridging.h
      LIBRARY_SEARCH_PATHS:
        - "$$(PROJECT_DIR)/lib"
';
        }
        if (ldflags.length > 0) {
            bridge += "      OTHER_LDFLAGS:\n";
            for (f in ldflags)
                bridge += '        - "$f"\n';
        }

        // iOS/visionOS: connecting to a device's LAN (e.g. a local dev server)
        // triggers the iOS 14+ local-network privacy prompt; without a usage
        // description the connection is denied. macOS doesn't gate this.
        var networking = "";
        if (platform != "macos") {
            networking = '      INFOPLIST_KEY_NSLocalNetworkUsageDescription: "Connect to a local development server on your network."
';
        }

        var packagesBlock = "";
        var depsBlock = "    dependencies: []\n";
        if (config.swiftPackages != null && config.swiftPackages.length > 0) {
            packagesBlock = "packages:\n";
            depsBlock = "    dependencies:\n";
            for (pkg in config.swiftPackages) {
                packagesBlock += '  ${pkg.product}:\n    url: ${pkg.url}\n    from: ${pkg.from}\n';
                depsBlock += '      - package: ${pkg.product}\n';
            }
        }

        return '${packagesBlock}name: ${config.appName}
options:
  bundleIdPrefix: ${config.bundleIdPrefix}
  deploymentTarget:
    $pk: "$dt"
  xcodeVersion: "15.0"
settings:
  SWIFT_VERSION: "5.9"
targets:
  ${config.appName}:
    type: application
    platform: $pk
    sources:
      - path: Sources
        type: group
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: ${config.bundleIdentifier}
      GENERATE_INFOPLIST_FILE: true
      INFOPLIST_KEY_UILaunchScreen_Generation: true
      INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone: UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight
      INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad: UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight
$networking$signing$bridge$depsBlock';
    }
}

typedef ProjectConfig = {
    appName:String,
    bundleIdentifier:String,
    bundleIdPrefix:String,
    ?teamId:String,
    ?swiftPackages:Array<SwiftPackage>,
    /** System frameworks the app links (e.g. ["AVKit"]) — declared per-app in
        sui.json, not baked into the framework. */
    ?frameworks:Array<String>,
}

typedef SwiftPackage = {
    url:String,
    from:String,
    product:String,
}
