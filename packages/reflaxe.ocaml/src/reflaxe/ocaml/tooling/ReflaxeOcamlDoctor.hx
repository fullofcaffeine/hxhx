package reflaxe.ocaml.tooling;

import haxe.Json;
import haxe.io.Path;
import reflaxe.ocaml.tooling.DoctorReport.DoctorCapabilities;
import reflaxe.ocaml.tooling.DoctorReport.DoctorSummary;
import reflaxe.ocaml.tooling.DoctorReport.DoctorVerifiedToolchain;

using StringTools;

/**
	Builds a read-only, capability-oriented reflaxe.ocaml environment report.

	The doctor deliberately separates "can emit OCaml", "can build it natively",
	"can use compiler-libs", and "can host through hxhx". This keeps a missing
	optional tool from disguising a healthy stock-Haxe workflow, while
	`--require` still gives CI and advanced users a fail-closed capability gate.
**/
class ReflaxeOcamlDoctor {
	public static inline final SCHEMA_VERSION = 1;
	public static inline final VERIFIED_HAXE = "4.3.7";
	public static inline final VERIFIED_OCAML = "5.2.1";
	public static inline final VERIFIED_DUNE = "3.24.0";

	static inline final MINIMUM_OCAML_MAJOR = 4;
	static inline final MINIMUM_OCAML_MINOR = 13;
	static inline final MINIMUM_DUNE_MAJOR = 2;
	static inline final MINIMUM_DUNE_MINOR = 9;

	public static final REQUIRED_CAPABILITIES = ["source", "native", "compiler", "hxhx"];

	public static function inspect(probe:DoctorProbe, packageRoot:String, projectRoot:String, packageVersion:String, requiredCapability:String):DoctorReport {
		final checks = new Array<DoctorCheck>();
		final verifiedToolchain:DoctorVerifiedToolchain = {
			haxe: VERIFIED_HAXE,
			ocaml: VERIFIED_OCAML,
			dune: VERIFIED_DUNE,
			hosts: ["linux-x64", "macos-arm64"]
		};

		final platform = probe.systemName();
		final architectureResult = probe.run("uname", ["-m"]);
		final architecture = architectureResult.code == 0 ? firstLine(commandOutput(architectureResult),
			"unknown") : probe.environment("PROCESSOR_ARCHITECTURE") ?? "unknown";
		final normalizedHost = normalizeHost(platform, architecture);
		final verifiedHost = verifiedToolchain.hosts.contains(normalizedHost);
		checks.push(check("platform", "Platform", verifiedHost ? DoctorStatus.Pass : DoctorStatus.Warn, false,
			verifiedHost ? 'Matches hosted package evidence ($normalizedHost).' : 'No hosted package receipt currently covers $normalizedHost.',
			'Verified hosts: ${verifiedToolchain.hosts.join(", ")}.',
			verifiedHost ? null : "Use the toolchain, but do not treat this machine as release-matrix evidence until CI covers it.", null, null));

		final haxeResult = probe.run("haxe", ["--version"]);
		final haxeVersion = successfulVersion(haxeResult);
		final haxeOkay = haxeResult.code == 0 && haxeVersion == VERIFIED_HAXE;
		checks.push(check("haxe", "Stock Haxe", haxeOkay ? DoctorStatus.Pass : DoctorStatus.Fail, true,
			haxeResult.code != 0 ? "Haxe is not runnable." : haxeOkay ? 'Found required Haxe $haxeVersion.' : 'Found Haxe $haxeVersion; this package requires $VERIFIED_HAXE.',
			null, haxeOkay ? null : 'Install or select Haxe $VERIFIED_HAXE, then rerun the doctor.', haxeVersion, probe.findExecutable("haxe")));

		final haxelibResult = probe.run("haxelib", ["version"]);
		final haxelibVersion = successfulVersion(haxelibResult);
		final haxelibOkay = haxelibResult.code == 0;
		checks.push(check("haxelib", "Haxelib", haxelibOkay ? DoctorStatus.Pass : DoctorStatus.Fail, true,
			haxelibOkay ? 'Haxelib is available${haxelibVersion.length > 0 ? " (" + haxelibVersion + ")" : ""}.' : "Haxelib is not runnable.", null,
			haxelibOkay ? null : "Install Haxelib with the selected Haxe toolchain.", haxelibVersion, probe.findExecutable("haxelib")));

		final reflaxeResult = probe.run("haxelib", ["path", "reflaxe"]);
		final reflaxeVersion = parseDefine(commandOutput(reflaxeResult), "reflaxe");
		final reflaxeResolved = reflaxeResult.code == 0 && firstClasspath(commandOutput(reflaxeResult)) != null;
		final reflaxeOkay = reflaxeResolved && (reflaxeVersion == null || reflaxeVersion.startsWith("4."));
		final reflaxeStatus = !reflaxeOkay ? DoctorStatus.Fail : reflaxeVersion == null ? DoctorStatus.Warn : DoctorStatus.Pass;
		checks.push(check("reflaxe", "Reflaxe framework", reflaxeStatus, true,
			!reflaxeResolved ? "Reflaxe could not be resolved through Haxelib." : reflaxeVersion == null ? "Reflaxe resolved, but its version define was not reported." : reflaxeOkay ? 'Resolved supported Reflaxe $reflaxeVersion.' : 'Resolved unsupported Reflaxe $reflaxeVersion.',
			"reflaxe.ocaml currently supports Reflaxe 4.x.", reflaxeOkay ? null : "Install a Reflaxe 4.x release and remove conflicting local overrides.",
			reflaxeVersion, firstClasspath(commandOutput(reflaxeResult))));

		final targetResult = probe.run("haxelib", ["path", "reflaxe.ocaml"]);
		final targetOutput = commandOutput(targetResult);
		final targetVersion = parseDefine(targetOutput, "reflaxe.ocaml");
		final targetClasspath = firstClasspath(targetOutput);
		final targetResolved = targetResult.code == 0 && targetClasspath != null;
		final targetVersionMatches = packageVersion == "unknown" || targetVersion == null || targetVersion == packageVersion;
		final targetOkay = targetResolved && targetVersionMatches;
		final targetStatus = !targetOkay ? DoctorStatus.Fail : targetVersion == null ? DoctorStatus.Warn : DoctorStatus.Pass;
		checks.push(check("target-package", "reflaxe.ocaml package", targetStatus, true,
			!targetResolved ? "The target package could not be resolved through Haxelib." : !targetVersionMatches ? 'The running CLI is $packageVersion, but Haxelib resolves $targetVersion.' : targetVersion == null ? "The target resolved, but its version define was not reported." : 'Resolved reflaxe.ocaml $targetVersion.',
			null, targetOkay ? null : "Remove stale haxelib dev/version overrides so the compiler and CLI resolve the same package.", targetVersion,
			targetClasspath));

		final resolvedPackageRoot = packageRootFromClasspath(probe, targetClasspath);
		final runtimeDirectory = findRuntimeDirectory(probe, [
			resolvedPackageRoot,
			packageRoot,
			Path.join([packageRoot, "packages", "reflaxe.ocaml"])
		]);
		final runtimeOkay = runtimeDirectory != null;
		final runtimeModuleCount = runtimeDirectory == null ? 0 : countRuntimeModules(probe, runtimeDirectory);
		checks.push(check("runtime-sources", "Runtime sources", runtimeOkay ? DoctorStatus.Pass : DoctorStatus.Fail, true,
			runtimeOkay ? 'Found $runtimeModuleCount OCaml runtime source modules.' : "Required runtime sources were not found in the resolved target package.",
			"The current package requires HxRuntime.ml and HxArray.ml in its source or flattened runtime directory.",
			runtimeOkay ? null : "Reinstall the source package or repair the local haxelib override.", null, runtimeDirectory));

		checks.push(check("runtime-manifest", "Semantic runtime manifest", DoctorStatus.Skip, false, "A locked semantic runtime manifest is not shipped yet.",
			"Current builds emit ocaml_runtime_plan_report.json, but syntax-derived reports are not presented as the future semantic manifest.",
			"No action is required for current builds; manifest validation is deferred to the runtime-ledger architecture bead.", null, null));

		final ocamlResult = probe.run("ocamlc", ["-version"]);
		final ocamlVersion = successfulVersion(ocamlResult);
		final ocamlCompatible = ocamlResult.code == 0 && versionAtLeast(ocamlVersion, MINIMUM_OCAML_MAJOR, MINIMUM_OCAML_MINOR);
		final ocamlVerified = ocamlCompatible && ocamlVersion == VERIFIED_OCAML;
		checks.push(check("ocaml", "OCaml compiler", ocamlVerified ? DoctorStatus.Pass : DoctorStatus.Warn, false,
			ocamlResult.code != 0 ? "OCaml is not installed; source emission remains available, but native builds do not." : !ocamlCompatible ? 'OCaml $ocamlVersion is older than the current 4.13 compatibility floor.' : 'OCaml $ocamlVersion is compatible but differs from the hosted $VERIFIED_OCAML evidence lane.',
			ocamlVerified ? "Matches the hosted package toolchain." : null,
			ocamlCompatible ? null : "Install OCaml 4.13 or newer; use 5.2.1 to reproduce the hosted release lane.", ocamlVersion,
			probe.findExecutable("ocamlc")));

		final ocamloptResult = probe.run("ocamlopt", ["-version"]);
		final ocamloptVersion = successfulVersion(ocamloptResult);
		final ocamloptCompatible = ocamloptResult.code == 0 && versionAtLeast(ocamloptVersion, MINIMUM_OCAML_MAJOR, MINIMUM_OCAML_MINOR);
		final ocamloptVerified = ocamloptCompatible && ocamloptVersion == VERIFIED_OCAML;
		checks.push(check("ocamlopt", "OCaml native compiler", ocamloptVerified ? DoctorStatus.Pass : DoctorStatus.Warn, false,
			ocamloptResult.code != 0 ? "ocamlopt is not installed; source emission and bytecode tooling remain available, but native builds do not." : !ocamloptCompatible ? 'ocamlopt $ocamloptVersion is older than the current 4.13 compatibility floor.' : 'ocamlopt $ocamloptVersion is compatible but differs from the hosted $VERIFIED_OCAML evidence lane.',
			ocamloptVerified ? "Matches the hosted package toolchain." : null,
			ocamloptCompatible ? null : "Install the native compiler for OCaml 4.13 or newer; use 5.2.1 to reproduce the hosted release lane.",
			ocamloptVersion, probe.findExecutable("ocamlopt")));

		final duneResult = probe.run("dune", ["--version"]);
		final duneVersion = successfulVersion(duneResult);
		final duneCompatible = duneResult.code == 0 && versionAtLeast(duneVersion, MINIMUM_DUNE_MAJOR, MINIMUM_DUNE_MINOR);
		final duneVerified = duneCompatible && duneVersion == VERIFIED_DUNE;
		checks.push(check("dune", "Dune", duneVerified ? DoctorStatus.Pass : DoctorStatus.Warn, false,
			duneResult.code != 0 ? "Dune is not installed; generated OCaml cannot be built through the standard workflow." : !duneCompatible ? 'Dune $duneVersion is older than the generated project language version 2.9.' : 'Dune $duneVersion is compatible but differs from the hosted $VERIFIED_DUNE evidence lane.',
			duneVerified ? "Matches the hosted package toolchain." : null,
			duneCompatible ? null : "Install Dune 2.9 or newer; use 3.24.0 to reproduce the hosted release lane.", duneVersion, probe.findExecutable("dune")));

		final ocamlfindResult = probe.run("ocamlfind", ["printconf"]);
		final ocamlfindVersion:Null<String> = null;
		final ocamlfindOkay = ocamlfindResult.code == 0;
		checks.push(check("ocamlfind", "OCaml findlib", ocamlfindOkay ? DoctorStatus.Pass : DoctorStatus.Warn, false,
			ocamlfindOkay ? "ocamlfind is available." : "ocamlfind is missing; native package and inferred-interface workflows are incomplete.", null,
			ocamlfindOkay ? null : "Install ocaml-findlib in the active OCaml switch.", ocamlfindVersion, probe.findExecutable("ocamlfind")));

		final opamResult = probe.run("opam", ["--version"]);
		final opamVersion = successfulVersion(opamResult);
		final opamOkay = opamResult.code == 0;
		checks.push(check("opam", "Opam", opamOkay ? DoctorStatus.Pass : DoctorStatus.Skip, false,
			opamOkay ? 'Opam $opamVersion is available for switch and package workflows.' : "Opam is not available; system-installed OCaml tools can still build ordinary projects.",
			null, opamOkay ? null : "Install Opam when you need reproducible switches, package locks, or publishing workflows.", opamVersion,
			probe.findExecutable("opam")));

		final compilerLibsResult = probe.run("ocamlfind", ["query", "compiler-libs.common"]);
		final compilerLibsPath = firstLine(commandOutput(compilerLibsResult));
		final compilerLibsOkay = compilerLibsResult.code == 0 && compilerLibsPath.length > 0;
		checks.push(check("compiler-libs", "OCaml compiler-libs", compilerLibsOkay ? DoctorStatus.Pass : DoctorStatus.Skip, false,
			compilerLibsOkay ? "compiler-libs.common is available for advanced compiler and binding tooling." : "compiler-libs.common is not available in the active findlib environment.",
			"Ordinary application compilation does not require compiler-libs.",
			compilerLibsOkay ? null : "Install compiler-libs/ocamlfind support in the active switch before advanced compiler-authoring work.", null,
			compilerLibsOkay ? compilerLibsPath : null));

		final hxhxResult = probe.run("hxhx", ["--version"]);
		final hxhxVersion = successfulVersion(hxhxResult);
		final hxhxOkay = hxhxResult.code == 0;
		checks.push(check("hxhx", "hxhx host", hxhxOkay ? DoctorStatus.Pass : DoctorStatus.Skip, false,
			hxhxOkay ? 'hxhx $hxhxVersion is available on PATH.' : "hxhx is not on PATH; the stock-Haxe reflaxe.ocaml workflow remains available.",
			"This check does not claim that every planned native plugin or builtin-target ABI is implemented.",
			hxhxOkay ? null : "Build/install hxhx only when you need its host-specific lanes.", hxhxVersion, probe.findExecutable("hxhx")));

		final lockFiles = findDependencyLocks(probe, projectRoot);
		final dependencyLockOkay = lockFiles.length > 0;
		checks.push(check("dependency-lock", "Project dependency lock", dependencyLockOkay ? DoctorStatus.Pass : DoctorStatus.Skip, false,
			dependencyLockOkay ? 'Found ${lockFiles.join(", ")}.' : "No recognized Opam or reflaxe.ocaml dependency lock was found in the project root.",
			dependencyLockOkay ? "This first doctor slice verifies lock presence; typed dependency-manifest validation remains future packaging work." : null,
			dependencyLockOkay ? null : "A lock is optional for local builds and expected for future reproducible packaging workflows.", null,
			dependencyLockOkay ? Path.join([projectRoot, lockFiles[0]]) : null));

		final sourceGeneration = haxeOkay && haxelibOkay && reflaxeOkay && targetOkay && runtimeOkay;
		final nativeBuild = sourceGeneration && ocamlCompatible && ocamloptCompatible && duneCompatible && ocamlfindOkay;
		final compilerAuthoring = nativeBuild && compilerLibsOkay;
		final hxhxHost = sourceGeneration && hxhxOkay;
		final reproduciblePackaging = nativeBuild && opamOkay && dependencyLockOkay;
		final verifiedReleaseLane = sourceGeneration && nativeBuild && verifiedHost && ocamlVerified && ocamloptVerified && duneVerified;
		final capabilities:DoctorCapabilities = {
			sourceGeneration: sourceGeneration,
			nativeBuild: nativeBuild,
			compilerAuthoring: compilerAuthoring,
			hxhxHost: hxhxHost,
			reproduciblePackaging: reproduciblePackaging,
			verifiedReleaseLane: verifiedReleaseLane
		};

		final ready = capabilityReady(capabilities, requiredCapability);
		final summary:DoctorSummary = summarize(checks, requiredCapability, ready);
		return {
			schemaVersion: SCHEMA_VERSION,
			packageName: "reflaxe.ocaml",
			packageVersion: packageVersion,
			projectRoot: probe.absolutePath(projectRoot),
			platform: platform,
			architecture: architecture,
			verifiedToolchain: verifiedToolchain,
			checks: checks,
			capabilities: capabilities,
			summary: summary
		};
	}

	public static function renderHuman(report:DoctorReport):String {
		final lines = [
			'reflaxe.ocaml doctor ${report.packageVersion}',
			'Project: ${report.projectRoot}',
			'Host: ${report.platform} ${report.architecture}',
			'Hosted evidence: Haxe ${report.verifiedToolchain.haxe}, OCaml ${report.verifiedToolchain.ocaml}, Dune ${report.verifiedToolchain.dune}',
			""
		];
		for (entry in report.checks) {
			lines.push('[${Std.string(entry.status).toUpperCase()}] ${entry.label}: ${entry.summary}');
			if (entry.remediation != null && entry.status != DoctorStatus.Pass) {
				lines.push('       Next: ${entry.remediation}');
			}
		}
		lines.push("");
		lines.push("Capabilities:");
		lines.push('  Source generation: ${yesNo(report.capabilities.sourceGeneration)}');
		lines.push('  Native build: ${yesNo(report.capabilities.nativeBuild)}');
		lines.push('  Compiler authoring: ${yesNo(report.capabilities.compilerAuthoring)}');
		lines.push('  hxhx host: ${yesNo(report.capabilities.hxhxHost)}');
		lines.push('  Reproducible packaging: ${yesNo(report.capabilities.reproduciblePackaging)}');
		lines.push('  Exact hosted lane: ${yesNo(report.capabilities.verifiedReleaseLane)}');
		lines.push("");
		lines.push('Requested `${report.summary.requestedCapability}` capability: ${report.summary.ready ? "READY" : "NOT READY"}');
		lines.push('Checks: ${report.summary.pass} pass, ${report.summary.warn} warning, ${report.summary.fail} failure, ${report.summary.skip} informational skip.');
		return lines.join("\n") + "\n";
	}

	public static function renderJson(report:DoctorReport):String {
		return Json.stringify(report, null, "  ") + "\n";
	}

	static function check(id:String, label:String, status:DoctorStatus, requiredForSource:Bool, summary:String, detail:Null<String>, remediation:Null<String>,
			version:Null<String>, path:Null<String>):DoctorCheck {
		return {
			id: id,
			label: label,
			status: status,
			requiredForSource: requiredForSource,
			summary: summary,
			detail: detail,
			remediation: remediation,
			version: version != null && version.length > 0 ? version : null,
			path: path != null && path.length > 0 ? path : null};
	}

	static function summarize(checks:Array<DoctorCheck>, requiredCapability:String, ready:Bool):DoctorSummary {
		var pass = 0;
		var warn = 0;
		var fail = 0;
		var skip = 0;
		for (entry in checks) {
			switch (entry.status) {
				case DoctorStatus.Pass:
					pass++;
				case DoctorStatus.Warn:
					warn++;
				case DoctorStatus.Fail:
					fail++;
				case DoctorStatus.Skip:
					skip++;
			}
		}
		return {
			pass: pass,
			warn: warn,
			fail: fail,
			skip: skip,
			requestedCapability: requiredCapability,
			ready: ready,
			exitCode: ready ? 0 : 1
		};
	}

	static function capabilityReady(capabilities:DoctorCapabilities, requiredCapability:String):Bool {
		return switch (requiredCapability) {
			case "source": capabilities.sourceGeneration;
			case "native": capabilities.nativeBuild;
			case "compiler": capabilities.compilerAuthoring;
			case "hxhx": capabilities.hxhxHost;
			case _: false;
		};
	}

	static function commandOutput(result:CommandResult):String {
		final stdout = result.stdout == null ? "" : result.stdout.trim();
		if (stdout.length > 0) {
			return stdout;
		}
		return result.stderr == null ? "" : result.stderr.trim();
	}

	static function successfulVersion(result:CommandResult):String {
		return result.code == 0 ? firstLine(commandOutput(result)) : "";
	}

	static function firstLine(value:String, fallback:String = ""):String {
		if (value == null || value.length == 0) {
			return fallback;
		}
		for (line in value.split("\n")) {
			final trimmed = line.trim();
			if (trimmed.length > 0) {
				return trimmed;
			}
		}
		return fallback;
	}

	static function parseDefine(output:String, name:String):Null<String> {
		if (output == null) {
			return null;
		}
		final prefix = '-D $name=';
		for (line in output.split("\n")) {
			final trimmed = line.trim();
			if (trimmed.startsWith(prefix)) {
				return trimmed.substr(prefix.length).trim();
			}
		}
		return null;
	}

	static function firstClasspath(output:String):Null<String> {
		if (output == null) {
			return null;
		}
		for (line in output.split("\n")) {
			final trimmed = line.trim();
			if (trimmed.length > 0 && !trimmed.startsWith("-")) {
				return Path.removeTrailingSlashes(trimmed);
			}
		}
		return null;
	}

	static function packageRootFromClasspath(probe:DoctorProbe, classpath:Null<String>):Null<String> {
		if (classpath == null || classpath.length == 0) {
			return null;
		}
		var root = probe.absolutePath(classpath);
		if (Path.withoutDirectory(root) == "src") {
			root = Path.directory(root);
		}
		return root;
	}

	static function findRuntimeDirectory(probe:DoctorProbe, roots:Array<Null<String>>):Null<String> {
		final seen:Map<String, Bool> = [];
		for (root in roots) {
			if (root == null || root.length == 0) {
				continue;
			}
			for (candidate in [Path.join([root, "std", "runtime"]), Path.join([root, "src", "runtime"])]) {
				final absolute = probe.absolutePath(candidate);
				if (seen.exists(absolute)) {
					continue;
				}
				seen.set(absolute, true);
				if (probe.isDirectory(absolute)
					&& probe.exists(Path.join([absolute, "HxRuntime.ml"]))
					&& probe.exists(Path.join([absolute, "HxArray.ml"]))) {
					return absolute;
				}
			}
		}
		return null;
	}

	static function countRuntimeModules(probe:DoctorProbe, runtimeDirectory:String):Int {
		var count = 0;
		for (entry in probe.readDirectory(runtimeDirectory)) {
			if (entry.endsWith(".ml") || entry.endsWith(".mli")) {
				count++;
			}
		}
		return count;
	}

	static function findDependencyLocks(probe:DoctorProbe, projectRoot:String):Array<String> {
		final locks = new Array<String>();
		if (!probe.isDirectory(projectRoot)) {
			return locks;
		}
		for (entry in probe.readDirectory(projectRoot)) {
			if (entry == "reflaxe.ocaml.lock.json" || entry == "opam.locked" || entry.endsWith(".opam.locked")) {
				locks.push(entry);
			}
		}
		locks.sort(compareStrings);
		return locks;
	}

	static function versionAtLeast(version:String, major:Int, minor:Int):Bool {
		if (version == null) {
			return false;
		}
		final expression = ~/^([0-9]+)\.([0-9]+)/;
		if (!expression.match(version.trim())) {
			return false;
		}
		final parsedMajor = Std.parseInt(expression.matched(1));
		final parsedMinor = Std.parseInt(expression.matched(2));
		if (parsedMajor == null || parsedMinor == null) {
			return false;
		}
		final actualMajor:Int = parsedMajor;
		final actualMinor:Int = parsedMinor;
		return actualMajor > major || (actualMajor == major && actualMinor >= minor);
	}

	static function normalizeHost(platform:String, architecture:String):String {
		final os = switch (platform.toLowerCase()) {
			case "mac", "macos", "darwin": "macos";
			case "linux": "linux";
			case other: other;
		};
		final arch = switch (architecture.toLowerCase()) {
			case "x86_64", "amd64", "x64": "x64";
			case "aarch64", "arm64": "arm64";
			case other: other;
		};
		return '$os-$arch';
	}

	static function yesNo(value:Bool):String {
		return value ? "yes" : "no";
	}

	static function compareStrings(left:String, right:String):Int {
		return left < right ? -1 : (left > right ? 1 : 0);
	}
}
