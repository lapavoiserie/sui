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
        // The freshness check watches this project's sources and sui's own; it
        // cannot watch every -lib in the build file without resolving them all.
        // So a change in rui, nui, kui or mui is invisible to it, and this is
        // the honest way out rather than a heuristic that is right most days.
        var force = false;
        for (arg in args) {
            if (arg == "--device") {
                forDevice = true;
            } else if (arg.startsWith("--device=")) {
                forDevice = true;
                deviceName = arg.substr(9);
            } else if (arg == "--force") {
                force = true;
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
        // The generated trees are this platform's, not the project's. One
        // build file serves three platforms and can only name one output, so
        // for years all three wrote into build/cpp and build/swift and nothing
        // ever pruned either -- see sui.macros.Output for what that cost.
        //
        // Under build/<platform>/ rather than build/cpp/<platform>/, so that
        // `rm -rf build/ios` is a complete and obvious per-platform clean and
        // the legacy shared tree is left standing alone where it can be
        // deleted without taking anything good with it.
        var cppOut = '$buildDir/cpp';
        var swiftGenDir = '$buildDir/swift';
        // hxcpp's own archive, named by us. Device and simulator differ in
        // architecture and SDK, so they are different files.
        var hxcppLib = '$buildDir/lib/libhxcpp-' + (forDevice ? "device" : "sim") + ".a";
        ensureDirectory(buildDir);
        ensureDirectory('$buildDir/Sources');

        // Step 1: Run Haxe compiler — generates both C++ and Swift via macro
        // Check if we can skip recompilation (incremental rebuild)
        var oldCwd = Sys.getCwd();
        Sys.setCwd(cwd);
        var buildFile = resolveBuildFile();
        Sys.setCwd(oldCwd);
        if (buildFile == null) {
            Sys.println("Error: no build file. Looked for build-sui.hxml, then build.hxml.");
            Sys.exit(1);
        }
        var needsRecompile = force || !isHxcppUpToDate(cwd, platform, hotReload, forDevice, buildFile);

        if (needsRecompile) {
            Sys.println("[1/3] Compiling Haxe (C++ & Swift generation)...");
            Sys.setCwd(cwd);
            // Pass platform define for conditional compilation (#if sui_ios, #if sui_macos, #if sui_visionos)
            Sys.println('  Compiling $buildFile');
            var haxeArgs = [buildFile, "-D", 'sui_$platform', "-D", 'cpp-output=$cppOut', "-D", 'swift-output=$swiftGenDir'];

            // Let hxcpp build the static library, and tell it exactly where.
            //
            // It already builds a correct one: `gcc-toolchain.xml`'s
            // static_link linker carries <recreate value="1"/>, so the archive
            // is made from scratch on every link and CANNOT carry a stale
            // member. The CLI used to ignore it and re-archive an object
            // directory by hand, which is how objects from other builds -- and
            // from other backends -- got in.
            //
            // `finish-setup.xml` sets static_link automatically for the Apple
            // embedded toolchains but not for macOS, where the haxe target then
            // emits `__main__.o` (a C main() that clashes with Swift's @main,
            // which is why the CLI filtered it by name) instead of `__lib__.o`.
            // Setting it here makes all three platforms the same shape.
            //
            // The name is ours, so nothing has to be derived: no LIBEXTRA
            // arithmetic, no glob, and device and simulator archives coexist
            // instead of overwriting each other.
            haxeArgs.push("-D"); haxeArgs.push("static_link=1");
            haxeArgs.push("-D"); haxeArgs.push('HAXE_FULL_OUTPUT_NAME=$hxcppLib');

            // Wipe the Swift tree before every compile. SwiftGenerator writes
            // all of it, so nothing is lost -- and afterwards the presence of
            // `Widget/` or `HaxeBridgeC.cpp` is a statement about THIS compile
            // rather than about some earlier one. Two of this file's tests
            // (hasWidget, isBridgeApp) are file-existence probes, and that is
            // what makes them exact.
            removeDirectoryContents(swiftGenDir);

            // And the kui manifest, so that its existence afterwards means
            // this build wrote it. `kui.macros.Emit` deliberately writes
            // nothing when a build declares no native payload -- a documented
            // contract with a test behind it -- so without this the previous
            // build's file survives and gets read as if it were ours. One line
            // here beats changing another library's contract.
            var kuiSidecar = '$cppOut/kui-payload.json';
            if (FileSystem.exists(kuiSidecar)) FileSystem.deleteFile(kuiSidecar);

            // Dynamic renderer: SwiftGenerator emits SuiBootC.cpp and force-keeps
            // the bridge classes only under this define.
            if (staticPath) { haxeArgs.push("-D"); haxeArgs.push("sui_static"); }
            // For non-macOS targets, tell hxcpp to cross-compile for the correct platform
            if (platform == "ios") {
                haxeArgs.push("-D");
                haxeArgs.push(forDevice ? "iphoneos" : "iphonesim");
            } else if (platform == "visionos") {
                // hxcpp has no visionOS toolchain of its own, so sui ships two
                // and puts them where hxcpp looks: it searches "." — its own
                // working directory, which is the C++ output — for
                // `toolchain/<name>-toolchain.xml`.
                //
                // Without this, `-D xrsimulator` is a define nothing reads:
                // the build falls through to the mac toolchain and the objects
                // land in obj/darwinarm64, after which the CLI used to archive
                // an earlier iPhone build's objects instead. A visionOS app
                // that was never compiled for visionOS, and nothing said so.
                var chain = forDevice ? "xros" : "xrsimulator";
                installToolchain(chain, cppOut);
                haxeArgs.push("-D"); haxeArgs.push(chain);
                haxeArgs.push("-D"); haxeArgs.push('toolchain=$chain');
                // `setDefaultToolchain` is skipped entirely once `toolchain` is
                // set (BuildTool.hx:155), so what it would have set has to be
                // said here, and so does what `finish-setup.xml` conditions on
                // the iPhone toolchains.
                haxeArgs.push("-D"); haxeArgs.push("apple=apple");
                haxeArgs.push("-D"); haxeArgs.push('LIBEXTRA=.$chain-64');
                haxeArgs.push("-D"); haxeArgs.push("HXCPP_M64=1");
                haxeArgs.push("-D"); haxeArgs.push("HXCPP_ARM64=1");
                haxeArgs.push("-D"); haxeArgs.push('SUI_XROS_MIN=' + deploymentTarget(platform));
            }
            var startedAt = Sys.time();
            var haxeResult = Sys.command("haxe", haxeArgs);
            Sys.setCwd(oldCwd);
            if (haxeResult != 0) {
                Sys.println("Error: Haxe compilation failed.");
                Sys.exit(1);
            }
            // The redirect has to be checked, not assumed. One test catches
            // all of: the generator macro missing from the build file, the
            // define ignored, and a haxe that exited 0 without generating.
            if (!FileSystem.exists('$cppOut/Build.xml')
                || FileSystem.stat('$cppOut/Build.xml').mtime.getTime() / 1000 < startedAt - 2) {
                Sys.println('Error: no C++ was generated in $cppOut.');
                Sys.println('  The build file did not honour -D cpp-output. Is');
                Sys.println('    --macro sui.macros.SwiftGenerator.register()');
                Sys.println('  present in $buildFile?');
                Sys.exit(1);
            }
            // Record what this output is for, so the next build can tell
            // "nothing changed" from "you asked for something else".
            try {
                File.saveContent(stampPath(cwd, platform), buildStamp(platform, hotReload, forDevice));
            } catch (_:Dynamic) {}
        } else {
            Sys.println("[1/3] Haxe unchanged, skipping recompilation...");
        }

        // Check for generated files
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

            if (needsRecompile || !FileSystem.exists('$buildDir/lib/libhaxe.a')) {
                Sys.println("[2/4] Assembling the static library + C++ bridge...");
            } else {
                Sys.println("[2/4] Bridge unchanged, skipping...");
            }

            // hxcpp was told where to put its archive; if it is not there, this
            // build did not produce one and nothing downstream can be trusted.
            // The previous version answered a missing object directory by
            // silently archiving nothing -- which is how a visionOS build
            // shipped a library holding only two bridge objects.
            if (!FileSystem.exists(hxcppLib)) {
                Sys.println('Error: hxcpp produced no static library at $hxcppLib.');
                Sys.println("  The build did not honour -D HAXE_FULL_OUTPUT_NAME, or it did not link.");
                Sys.exit(1);
            }

            // Find hxcpp include path
            var hxcppDir = findHxcppDir();

            // Compile the C++ bridge against hxcpp headers.
            //
            // The architecture is READ from hxcpp's archive rather than
            // guessed. The guess was "x86_64 for any simulator", which is what
            // hxcpp's iphonesim toolchain hardcodes -- and wrong for a visionOS
            // simulator, which is arm64 only. Asking the artefact costs one
            // `lipo` and cannot drift.
            var platformDefine = switch (platform) {
                case "ios": forDevice ? "-DHX_IOS" : "-DIPHONESIM=IPHONESIM";
                case "visionos": "-DHX_VISIONOS";
                default: "-DHX_MACOS";
            };
            var bridgeArch = archOf(hxcppLib);
            var clangArgs = [
                "-c", "-std=c++17",
                '-I$hxcppDir/include',
                '-I$cppOut/include',
                platformDefine, "-DHXCPP_M64",
                "-DHXCPP_VISIT_ALLOCS", "-DHX_SMART_STRINGS",
                "-DHXCPP_API_LEVEL=430",
                // `common-defines.xml` adds this to every file hxcpp compiles
                // under static_link, and `hx/CFFI.h` and `hx/Macros.h` read it.
                // The hand-written list here never had it, so the bridge and
                // the library it links into saw different headers.
                "-DSTATIC_LINK",
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
            }

            // One shot, always overwriting: hxcpp's archive plus the bridge
            // objects. `ar r` *updates* an archive -- a member from a previous
            // build survives unless something replaces it by name -- which is
            // what left one render path's bridge object in the other's library
            // and produced "duplicate symbol _haxe_bridge_invoke_action" from
            // a file that build never compiled. `libtool -static -o` has no
            // such history.
            var libtoolArgs = ["-static", "-o", '$buildDir/lib/libhaxe.a', hxcppLib];
            for (bs in bridgeSources) libtoolArgs.push(bs.obj);
            if (Sys.command("libtool", libtoolArgs) != 0) {
                Sys.println("Error: could not assemble libhaxe.a.");
                Sys.exit(1);
            }

            // One architecture, or the link that follows fails somewhere far
            // from here. Cheap, and it is the assertion that would have caught
            // a visionOS library built from iPhone-simulator objects.
            var archs = archOf('$buildDir/lib/libhaxe.a');
            if (archs != bridgeArch) {
                Sys.println('Error: libhaxe.a is "$archs" but the bridge was built "$bridgeArch".');
                Sys.exit(1);
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
        // The widget extension, when the application declared the surface it
        // draws. It is a SEPARATE BINARY with its own sandbox, so it gets its
        // own directory rather than joining Sources — and the two of them can
        // only meet through an App Group, which both must be entitled to.
        //
        // iOS and visionOS. Both are ad-hoc signed on their simulators, which
        // is all an App Group entitlement needs there. **macOS is the one left
        // out, and for signing rather than for WidgetKit**: it refuses to build
        // a target carrying an entitlements file without a provisioning profile
        // ("requires a provisioning profile"). A macOS widget waits for a
        // signing identity, not for more code.
        //
        // The generator has been emitting the widget's Swift for every platform
        // that declares Glance all along; this condition was the only thing
        // throwing it away. Which is worth noting as its own small lesson: the
        // visionOS widget was one boolean from existing, and nothing said so,
        // because a build that quietly produces less than it could looks
        // exactly like a build that produced everything.
        var hasWidget = (platform == "ios" || platform == "visionos")
            && FileSystem.exists('$swiftGenDir/Widget');
        if (!hasWidget) clearWidget(buildDir);
        if (hasWidget) {
            ensureDirectory('$buildDir/Widget');
            // Copied only when the content differs, for the same reason the
            // entitlements below are: touching Widget/Info.plist or the
            // extension's Swift forces a full extension recompile every build,
            // and xcodebuild refuses an entitlements file whose mtime moved.
            for (file in FileSystem.readDirectory('$swiftGenDir/Widget'))
                copyIfDifferent('$swiftGenDir/Widget/$file', '$buildDir/Widget/$file');
            var group = 'group.${config.bundleIdentifier}';
            // Written only when the content changes: xcodebuild refuses an
            // entitlements file whose mtime moved since the last build
            // ("modified during the build"), and rewriting identical bytes
            // every time is exactly that.
            saveIfDifferent('$buildDir/Entitlements.plist', appGroupEntitlements(group));
            // Kept OUT of the Widget directory: that directory is a source
            // group, so anything in it becomes a resource of the extension —
            // and an entitlements file the build copies is an entitlements
            // file "modified during the build".
            saveIfDifferent('$buildDir/WidgetEntitlements.plist', appGroupEntitlements(group));
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
        copyKuiSwiftFiles(cwd, platform, buildDir);

        // Read what kui capabilities need — here, and not beside
        // readProjectConfig where it started. The sidecar is written by the Haxe
        // compilation in step 1, so reading it before that ran meant reading the
        // *previous* build's payload: nothing at all on a first build, and the
        // wrong platform's after switching targets. It cost an iOS build that
        // linked no UIKit while the macOS one linked IOKit correctly, which
        // looked like an iOS problem and was an ordering one.
        mergeKuiPayload(cwd, platform, config);

        // Generate project.yml
        File.saveContent('$buildDir/project.yml', generateProjectYaml(config, platform, forDevice, nativeBridge, hasWidget));

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
            // Xcode can have a platform's SDK without its platform component,
            // and then says "<platform> N.N is not installed" about a
            // destination rather than about what is missing. Worth translating,
            // because everything before this step DID work: the C++ is
            // compiled and the library linked for the right platform. The one
            // thing this family of bugs must never do again is let a partial
            // success read as a full one — or a full one read as a failure.
            if (platform == "visionos" && platformNotInstalled(buildDir, config.appName, "visionOS")) {
                Sys.println("");
                Sys.println("  Xcode has the visionOS SDK but not the visionOS platform component.");
                Sys.println("  Install it from Xcode > Settings > Components.");
                Sys.println("");
                Sys.println('  The Haxe and hxcpp half of this build succeeded: $buildDir/lib/libhaxe.a');
                Sys.println("  is compiled for visionOS. Only Xcode's own step could not run.");
            }
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
    /** Copy only when the bytes differ, so an unchanged file keeps its mtime.
        Same reason as `saveIfDifferent`: on Apple, a moved mtime is not free —
        it recompiles an extension, and on an entitlements file it is an
        outright build failure. **/
    static function copyIfDifferent(from:String, to:String) {
        if (FileSystem.exists(to)) {
            try {
                if (File.getBytes(from).compare(File.getBytes(to)) == 0) return;
            } catch (_:Dynamic) {}
        }
        File.copy(from, to);
    }

    static function clearSources(buildDir:String) {
        // Recursive. Skipping directories left whatever a previous build had
        // put in one -- and the widget extension is a directory, so a Glance
        // surface generated once kept its Swift beside every later build of
        // the same platform.
        removeDirectoryContents('$buildDir/Sources');
    }

    /**
        Take down the widget extension's own files when this build has none.

        `hasWidget` is now exact (the Swift tree is wiped before each compile),
        but the *assembled* side is not swept by `clearSources`: `Widget/` and
        the two entitlements files live beside `Sources/`, not in it. Left
        behind, xcodegen keeps finding an Info.plist for an extension the
        project no longer declares.
    **/
    static function clearWidget(buildDir:String) {
        if (FileSystem.exists('$buildDir/Widget')) removeDirectoryTree('$buildDir/Widget');
        for (plist in ["Entitlements.plist", "WidgetEntitlements.plist"])
            if (FileSystem.exists('$buildDir/$plist')) FileSystem.deleteFile('$buildDir/$plist');
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

    /**
        Fold a kui capability's Xcode payload into the project configuration.

        `sui.json` already carries `frameworks` and `swiftPackages`, and a
        capability wants exactly those two things plus its own Swift sources. So
        nothing downstream has to learn anything: the payload is merged here and
        the project generator sees one list, however it was declared.

        The sidecar is what `kui` writes beside the generated C++, with every path
        already absolute. It is read rather than `Build.xml`, because Xcode never
        opens that file and a `${haxelib:x}` path would reach it unexpanded.

        A project with no capabilities finds no sidecar and nothing changes.
    **/
    static function mergeKuiPayload(cwd:String, platform:String, config:ProjectConfig):Void {
        var payload = readKuiPayload(cwd, platform);
        if (!payload.any()) return;

        var frameworks = payload.strings("xcode", "frameworks");
        if (frameworks.length > 0) {
            if (config.frameworks == null) config.frameworks = [];
            for (framework in frameworks)
                if (config.frameworks.indexOf(framework) < 0) config.frameworks.push(framework);
        }

        var packages = payload.objects("xcode", "packages");
        if (packages.length > 0) {
            if (config.swiftPackages == null) config.swiftPackages = [];
            for (pkg in packages)
                config.swiftPackages.push({
                    url: Std.string(Reflect.field(pkg, "url")),
                    from: Std.string(Reflect.field(pkg, "from")),
                    product: Std.string(Reflect.field(pkg, "product")),
                });
        }

        Sys.println("  [kui] " + payload.names().join(", "));
    }

    /**
        The kui manifest for THIS build, refusing one that is not.

        The CLI deletes the file before every compile, so its presence here
        means this build wrote it. The platform check is therefore unreachable
        — which is exactly what makes it worth having: it fires only when one
        of the isolation assumptions has broken, and it names both platforms
        instead of quietly linking another one's frameworks.

        Before the trees were separated, that is precisely what happened: a
        visionOS project.yml inherited `-framework Foundation` from an iOS
        build, because `kui.macros.Emit` writes nothing when a build declares
        no payload and the previous file was still lying there.
    **/
    static function readKuiPayload(cwd:String, platform:String):kui.build.Sidecar {
        var payload = kui.build.Sidecar.read('$cwd/build/$platform/cpp');
        if (!payload.any()) return payload;

        var declared = payload.platform();
        if (declared != null && declared != platform) {
            Sys.println('Error: build/$platform/cpp/kui-payload.json was written for "$declared".');
            Sys.println('  A capability manifest from another platform would link that');
            Sys.println("  platform's frameworks into this one. Run `sui clean` and rebuild.");
            Sys.exit(1);
        }
        return payload;
    }

    /** Swift a capability ships, copied beside the application's own. **/
    static function copyKuiSwiftFiles(cwd:String, platform:String, buildDir:String) {
        var payload = readKuiPayload(cwd, platform);
        for (source in payload.strings("xcode", "sources")) {
            if (!FileSystem.exists(source)) {
                Sys.println('  [kui] missing source: $source');
                continue;
            }
            File.copy(source, '$buildDir/Sources/' + haxe.io.Path.withoutDirectory(source));
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

    /**
        The single architecture of a Mach-O archive, asked of the file itself.

        `lipo -archs` answers with a space-separated list; anything but one
        entry means the archive mixes architectures, and the caller says so
        rather than letting the link fail somewhere unrecognisable.
    **/
    static function archOf(path:String):String {
        var proc = new sys.io.Process("lipo", ["-archs", path]);
        var out = StringTools.trim(proc.stdout.readAll().toString());
        proc.close();
        return out;
    }

    /**
        Put sui's own hxcpp toolchain where hxcpp will find it.

        hxcpp resolves `toolchain/<name>-toolchain.xml` through an include path
        whose only project-relative entry is `.` — its working directory, which
        is the C++ output directory. Copying rather than pointing at the
        library keeps that resolution simple and means an updated sui ships an
        updated toolchain without anyone re-running anything.

        Refuses by name when the file is missing, because the alternative is
        hxcpp's own "Could not find include file", which names a relative path
        inside a generated directory and tells nobody where it should come
        from.
    **/
    static function installToolchain(name:String, cppOut:String) {
        var source = getLibPath() + '/toolchain/$name-toolchain.xml';
        if (!FileSystem.exists(source)) {
            Sys.println('Error: sui ships no hxcpp toolchain for "$name".');
            Sys.println('  Looked for: $source');
            Sys.exit(1);
        }
        ensureDirectory(cppOut);
        ensureDirectory('$cppOut/toolchain');
        copyIfDifferent(source, '$cppOut/toolchain/$name-toolchain.xml');
    }

    /**
        Whether Xcode reports a platform as not installed for this project.

        Asked of `xcodebuild -showdestinations`, which is where the real reason
        appears: with the SDK present but the platform component missing it
        lists every destination as ineligible and says "<platform> N.N is not
        installed". The SDK list is no help -- the SDK is there in the broken
        case too, which is exactly what makes the failure confusing.
    **/
    static function platformNotInstalled(buildDir:String, scheme:String, name:String):Bool {
        return try {
            var oldCwd = Sys.getCwd();
            Sys.setCwd(buildDir);
            var proc = new sys.io.Process("xcodebuild", ["-scheme", scheme, "-showdestinations"]);
            var out = proc.stdout.readAll().toString() + proc.stderr.readAll().toString();
            proc.close();
            Sys.setCwd(oldCwd);
            out.indexOf(name) >= 0 && out.indexOf("is not installed") >= 0;
        } catch (_:Dynamic) false;
    }

    static function ensureDirectory(path:String) {
        if (!FileSystem.exists(path)) {
            FileSystem.createDirectory(path);
        }
    }

    /**
        Empty a directory, keeping the directory itself.

        Used on the Swift tree before every compile. The generator writes all
        of it, so nothing is lost -- and what is *not* rewritten is precisely
        the problem this removes: `hasWidget` and `isBridgeApp` are
        file-existence probes, and a file from an earlier compile made them
        answer about a build that is no longer happening. A widget generated
        once for iOS kept the flag true for macOS for as long as the tree
        stood.
    **/
    static function removeDirectoryContents(path:String) {
        if (!FileSystem.exists(path)) return;
        for (entry in FileSystem.readDirectory(path)) {
            var child = '$path/$entry';
            if (FileSystem.isDirectory(child)) removeDirectoryTree(child);
            else FileSystem.deleteFile(child);
        }
    }

    static function removeDirectoryTree(path:String) {
        for (entry in FileSystem.readDirectory(path)) {
            var child = '$path/$entry';
            if (FileSystem.isDirectory(child)) removeDirectoryTree(child);
            else FileSystem.deleteFile(child);
        }
        FileSystem.deleteDirectory(path);
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

    /**
        What the output in `build/<platform>/` was produced for.

        `forDevice` is in it because it changes everything: `-D iphoneos` and
        `-D iphonesim` are a different SDK and a different architecture, and
        without it `sui build ios --device` right after `sui build ios` was
        judged "up to date" and shipped a simulator binary signed for a phone.

        The leading version means an older stamp can never accidentally match a
        newer format; bump it whenever what is in here changes.
    **/
    static function buildStamp(platform:String, hotReload:Bool, forDevice:Bool):String {
        return "2|" + platform + "|" + (hotReload ? "dynamic" : "static") + "|" + (forDevice ? "device" : "sim");
    }

    /** Beside the platform's own tree, not at the root of `build/`: two
        platforms had one stamp between them, so each switch invalidated the
        other's perfectly good output. **/
    static function stampPath(cwd:String, platform:String):String {
        return '$cwd/build/$platform/.sui-build-stamp';
    }

    static function isHxcppUpToDate(cwd:String, platform:String, hotReload:Bool, forDevice:Bool, buildFile:Null<String>):Bool {
        var swiftDir = '$cwd/build/$platform/swift';
        var cppDir = '$cwd/build/$platform/cpp';

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
        var stamp = stampPath(cwd, platform);
        if (!FileSystem.exists(stamp)) return false;
        try {
            if (StringTools.trim(File.getContent(stamp)) != buildStamp(platform, hotReload, forDevice)) return false;
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
        // The build file that will actually be compiled -- which may be
        // `build-sui.hxml`. Statting `build.hxml` unconditionally meant editing
        // the one this project uses did not trigger a rebuild.
        if (buildFile != null && FileSystem.exists('$cwd/$buildFile')) {
            var stat = FileSystem.stat('$cwd/$buildFile');
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

        // Against Build.xml, which hxcpp writes at the end of a successful
        // generation. The previous version took the NEWEST .swift as the
        // baseline while its comment said "oldest" -- so a source edited after
        // some outputs but before others read as up to date. One file written
        // once, at a known moment, has no such gap.
        //
        // Not covered, and worth saying rather than pretending: a change in
        // `rui`, `nui`, `kui` or `mui` is not seen, because resolving those
        // would mean resolving every -lib in the build file. `sui build
        // --force` is the honest way out.
        var generated = '$cppDir/Build.xml';
        if (!FileSystem.exists(generated)) return false;
        return newestSource < FileSystem.stat(generated).mtime.getTime();
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

    /**
        The one thing an app and its widget extension can share.

        Two binaries, two sandboxes: the only sanctioned way for the
        application to leave a snapshot where the widget can read it is an App
        Group both are entitled to. The name follows the bundle identifier, so
        each side computes it from its own — the extension's is the app's plus
        a suffix — and neither has to be told.
    **/
    /** Write only when the bytes differ, so an unchanged file keeps its
        timestamp. **/
    static function saveIfDifferent(path:String, content:String):Void {
        if (FileSystem.exists(path) && File.getContent(path) == content) return;
        File.saveContent(path, content);
    }

    static function appGroupEntitlements(group:String):String {
        return '<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
\t<key>com.apple.security.application-groups</key>
\t<array>
\t\t<string>$group</string>
\t</array>
</dict>
</plist>
';
    }

    static function generateProjectYaml(config:ProjectConfig, platform:String, forDevice:Bool, nativeBridge:Bool = false, hasWidget:Bool = false):String {
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
        if (hasWidget) depsBlock = '    dependencies:\n      - target: ${config.appName}GlanceWidget\n';
        if (config.swiftPackages != null && config.swiftPackages.length > 0) {
            packagesBlock = "packages:\n";
            depsBlock = "    dependencies:\n";
            for (pkg in config.swiftPackages) {
                packagesBlock += '  ${pkg.product}:\n    url: ${pkg.url}\n    from: ${pkg.from}\n';
                depsBlock += '      - package: ${pkg.product}\n';
            }
        }

        // The widget extension is a second target, and the app depends on it
        // so that building the app embeds it. Both carry the App Group
        // entitlement: without it on BOTH sides the container is not shared
        // and the widget reads nothing, silently.
        var widgetBlock = "";
        var widgetTarget = "";
        if (hasWidget) {
            // The extension links the SAME hxcpp static library the app does.
            // That is what makes the widget's buttons work: a tap arrives as an
            // AppIntent in THIS process, so the closures have to exist here --
            // the extension boots the runtime headless, builds its own instance
            // of the application, samples, and invokes.
            //
            // It costs the extension the runtime's size, which is why step 0 of
            // the durable-state plan measured it before anything was built on
            // it: booting and sampling came to under a megabyte of heap.
            widgetBlock = "      CODE_SIGN_ENTITLEMENTS: Entitlements.plist\n";
            widgetTarget = '  ${config.appName}GlanceWidget:
    type: app-extension
    platform: $pk
    sources:
      - path: Widget
        type: group
        excludes:
          - "Info.plist"
      - path: Sources/SuiGlanceShim.swift
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: ${config.bundleIdentifier}.glancewidget
      INFOPLIST_FILE: Widget/Info.plist
      CODE_SIGN_ENTITLEMENTS: WidgetEntitlements.plist
      SKIP_INSTALL: true
      LIBRARY_SEARCH_PATHS:
        - "$(PROJECT_DIR)/lib"
      OTHER_LDFLAGS:
        - "-lhaxe"
        - "-lc++"
';
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
$networking$signing$bridge$widgetBlock$depsBlock$widgetTarget';
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
