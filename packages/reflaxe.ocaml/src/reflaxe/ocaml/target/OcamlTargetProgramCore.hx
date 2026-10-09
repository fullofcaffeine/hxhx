package reflaxe.ocaml.target;

import haxe.Json;
import haxe.crypto.Sha256;
import haxe.io.Path;
import reflaxe.ocaml.OcamlNameTools;
import reflaxe.ocaml.ast.OcamlASTPrinter;
import reflaxe.ocaml.ast.OcamlLetBinding;
import reflaxe.ocaml.ast.OcamlModuleItem;
import reflaxe.ocaml.runtimegen.OcamlFinalRuntimeUseAuthority;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirement;
import sys.FileSystem;
import sys.io.File;

typedef OcamlTargetProgramFile = {
	final path:String;
	final kind:String;
	final contents:String;
	final sha256:String;
}

typedef OcamlTargetProgramManifestEntry = {
	final path:String;
	final kind:String;
	final sha256:String;
}

typedef OcamlTargetProgramReport = {
	final schemaVersion:Int;
	final route:String;
	final hostProgramRevision:String;
	final targetCoreId:String;
	final normalizedInputIdentity:String;
	final normalizedClassIdentity:String;
	final normalizedClassIdentityFacts:Array<Null<String>>;
	final normalizedFieldIdentities:Array<String>;
	final normalizedFunctionIdentities:Array<String>;
	final loweredPlanIdentity:String;
	final runtimeReasonIdentity:String;
	final outputManifestIdentity:String;
	final mainModuleId:String;
	final dependencyModuleIds:Array<String>;
	final runtimeReasons:Array<String>;
	final files:Array<OcamlTargetProgramManifestEntry>;
}

/** Immutable source and identity plan produced by the shared target core. **/
class OcamlTargetProgramPlan {
	public final hostProgramRevision:String;
	public final mainModuleId:String;
	public final normalizedInputIdentity:String;
	public final normalizedClassIdentity:String;
	public final loweredPlanIdentity:String;
	public final runtimeReasonIdentity:String;
	public final outputManifestIdentity:String;

	final files:Array<OcamlTargetProgramFile>;
	final runtimeReasons:Array<String>;
	final normalizedClassIdentityFacts:Array<Null<String>>;
	final normalizedFieldIdentities:Array<String>;
	final normalizedFunctionIdentities:Array<String>;

	public function new(hostProgramRevision:String, mainModuleId:String, normalizedInputIdentity:String, normalizedClassIdentity:String,
			normalizedClassIdentityFacts:Array<Null<String>>, normalizedFieldIdentities:Array<String>, normalizedFunctionIdentities:Array<String>,
			loweredPlanIdentity:String, runtimeReasonIdentity:String, outputManifestIdentity:String, files:Array<OcamlTargetProgramFile>,
			runtimeReasons:Array<String>) {
		this.hostProgramRevision = hostProgramRevision;
		this.mainModuleId = mainModuleId;
		this.normalizedInputIdentity = normalizedInputIdentity;
		this.normalizedClassIdentity = normalizedClassIdentity;
		this.normalizedClassIdentityFacts = normalizedClassIdentityFacts.copy();
		this.normalizedFieldIdentities = normalizedFieldIdentities.copy();
		this.normalizedFunctionIdentities = normalizedFunctionIdentities.copy();
		this.loweredPlanIdentity = loweredPlanIdentity;
		this.runtimeReasonIdentity = runtimeReasonIdentity;
		this.outputManifestIdentity = outputManifestIdentity;
		this.files = files.copy();
		this.runtimeReasons = runtimeReasons.copy();
	}

	public function copyFiles():Array<OcamlTargetProgramFile>
		return files.copy();

	public function report(route:String):OcamlTargetProgramReport {
		final normalizedRoute = route == null ? "" : StringTools.trim(route);
		if (normalizedRoute.length == 0)
			throw "OCaml target program report requires a route";
		return {
			schemaVersion: 1,
			route: normalizedRoute,
			hostProgramRevision: hostProgramRevision,
			targetCoreId: OcamlTargetProgramCore.CORE_ID,
			normalizedInputIdentity: normalizedInputIdentity,
			normalizedClassIdentity: normalizedClassIdentity,
			normalizedClassIdentityFacts: normalizedClassIdentityFacts.copy(),
			normalizedFieldIdentities: normalizedFieldIdentities.copy(),
			normalizedFunctionIdentities: normalizedFunctionIdentities.copy(),
			loweredPlanIdentity: loweredPlanIdentity,
			runtimeReasonIdentity: runtimeReasonIdentity,
			outputManifestIdentity: outputManifestIdentity,
			mainModuleId: mainModuleId,
			// Admitted calls remain inside the selected class, so no selected
			// expression can depend on another source module.
			dependencyModuleIds: [],
			runtimeReasons: runtimeReasons.copy(),
			files: [
				for (file in files)
					{
						path: file.path,
						kind: file.kind,
						sha256: file.sha256
					}
			]
		};
	}

	public function reportJson(route:String):String
		return Json.stringify(report(route), null, "  ") + "\n";
}

/**
	The first host-independent, executable standalone `reflaxe.ocaml` core.

	The core owns OCaml syntax, naming, entrypoint, Dune, runtime-reason, and
	output-manifest decisions for the admitted program family. Host wrappers only
	copy typed facts and publish the returned files. Unsupported program shapes
	fail before any file is written.
**/
class OcamlTargetProgramCore {
	public static inline final CORE_ID = "reflaxe.ocaml.target-program-core.v3";
	public static inline final REPORT_FILE = "ocaml_shared_target_report.json";
	public static inline final MANIFEST_FILE = "ocaml_shared_target_manifest.json";
	public static inline final ENTRY_NAME = "reflaxe_ocaml_entry";

	/** The admitted program family currently has portable-profile execution evidence. **/
	public static function requireProfile(profile:String):Void {
		if (profile != "portable")
			throw 'OCaml target program core does not support profile "$profile"';
	}

	public static function lower(request:OcamlTargetProgramRequest, ?runtimeSources:Void->OcamlTargetRuntimeSources):OcamlTargetProgramPlan {
		if (request == null)
			throw "OCaml target program core requires a normalized request";
		final printer = new OcamlASTPrinter();
		final finalUses = new OcamlFinalRuntimeUseAuthority();
		finalUses.beginProgram(request.hostProgramRevision, "portable");
		final requirements = new Array<OcamlRuntimeRequirement>();
		final bindings = new Array<OcamlLetBinding>();
		for (field in request.copyFieldInitializers()) {
			final lowered = OcamlTargetExpressionLowerer.lower(field.initializer, field.getTargetIdentity(), "portable", finalUses);
			for (requirement in lowered.runtimeRequirements)
				requirements.push(requirement);
			bindings.push({
				name: targetValueName(field.moduleId, field.sourceTypeName, field.sourceFieldName),
				expr: lowered.expression
			});
		}
		final functionBindings = new Array<OcamlLetBinding>();
		for (fn in request.copyFunctions()) {
			final lowered = OcamlTargetFunctionLowerer.lower(fn, "portable", finalUses);
			for (requirement in lowered.runtimeRequirements)
				requirements.push(requirement);
			functionBindings.push({
				name: targetValueName(fn.moduleId, fn.sourceTypeName, fn.sourceFunctionName),
				expr: lowered.expression,
				signature: lowered.signature
			});
		}
		bindings.sort((left, right) -> compareText(left.name, right.name));
		functionBindings.sort((left, right) -> compareText(left.name, right.name));

		final modulePath = moduleFile(request.mainModuleId);
		final items = new Array<OcamlModuleItem>();
		if (bindings.length != 0)
			items.push(OcamlModuleItem.ILet(bindings, false));
		// Every admitted function is an OCaml lambda. A function-only recursive
		// group permits forward references without moving field initialization.
		var hasCalls = false;
		for (fn in request.copyFunctions())
			if (fn.body.copyStaticCalls().length != 0)
				hasCalls = true;
		items.push(OcamlModuleItem.ILet(functionBindings, hasCalls));
		finalUses.observeModuleItems(items, modulePath);
		finalUses.finishProgram();
		requirements.sort((left, right) -> compareText(left.id, right.id));
		final runtimeRoots = new Array<String>();
		for (requirement in requirements)
			for (root in requirement.rootModules)
				if (!runtimeRoots.contains(root))
					runtimeRoots.push(root);
		final runtimeFiles = if (runtimeRoots.length == 0) {
			new Array<OcamlTargetProgramFile>();
		} else {
			if (runtimeSources == null)
				throw "OCaml target program requires a checked runtime source provider.";
			runtimeSources().select(runtimeRoots, "portable");
		};
		final moduleContents = printer.printModule(items) + "\n";
		final entryContents = "let () = ignore (" + moduleName(request.mainModuleId) + ".main ())\n";
		final duneProject = [
			"(lang dune 2.9)",
			"(name reflaxe_ocaml_shared_target)",
			"(wrapped_executables false)",
			"",
			"; Generated by reflaxe.ocaml"
		].join("\n") + "\n";
		final dune = [
			"(executable",
			" (name " + ENTRY_NAME + ")",
			" (modules :standard)",
			runtimeFiles.length == 0 ? "" : " (libraries hx_runtime)",
			// Unused Haxe locals are valid. Keep OCaml warning 26 visible without
			// promoting it to a build error; other diagnostics retain Dune's policy.
			" (flags (:standard -warn-error -26))",
			" (modes (native exe) (byte exe)))",
			"",
			"; Generated by reflaxe.ocaml"
		].join("\n") + "\n";
		final files = [
			file(modulePath, "haxe-module-source", moduleContents),
			file(ENTRY_NAME + ".ml", "entry-source", entryContents),
			file("dune-project", "dune-project", duneProject),
			file("dune", "dune-stanza", dune)
		];
		for (runtimeFile in runtimeFiles)
			files.push(runtimeFile);
		files.sort((left, right) -> compareText(left.path, right.path));

		final loweredParts:Array<Null<String>> = [CORE_ID, request.getCanonicalIdentity(), modulePath, moduleContents];
		final loweredPlanIdentity = Sha256.encode(OcamlTargetDeclarationCodec.encode(loweredParts));
		final runtimeReasons = [
			for (requirement in requirements)
				requirement.sourceId + ": " + requirement.explanation
		];
		final runtimeParts:Array<Null<String>> = [CORE_ID, "runtime-reasons-v2", Std.string(runtimeReasons.length)];
		for (requirement in requirements) {
			// Explicit field order keeps identity equal across macro, eval, and native hosts.
			for (part in [
				requirement.id,
				requirement.sourceKind,
				requirement.sourceId,
				requirement.source.file,
				Std.string(requirement.source.min),
				Std.string(requirement.source.max),
				requirement.semanticCapability,
				requirement.cause,
				requirement.decisionId,
				requirement.subject.kind,
				requirement.subject.id,
				requirement.implementationFeature,
				requirement.explanation,
				Std.string(requirement.rootModules.length)
			])
				runtimeParts.push(part);
			for (root in requirement.rootModules)
				runtimeParts.push(root);
			runtimeParts.push(Std.string(requirement.profileEligibility.length));
			for (profile in requirement.profileEligibility)
				runtimeParts.push(profile);
		}
		final runtimeReasonIdentity = Sha256.encode(OcamlTargetDeclarationCodec.encode(runtimeParts));
		final manifestParts:Array<Null<String>> = [CORE_ID, "output-manifest-v1", Std.string(files.length)];
		for (output in files) {
			manifestParts.push(output.path);
			manifestParts.push(output.kind);
			manifestParts.push(output.sha256);
		}
		final outputManifestIdentity = Sha256.encode(OcamlTargetDeclarationCodec.encode(manifestParts));
		return new OcamlTargetProgramPlan(request.hostProgramRevision, request.mainModuleId, request.getCanonicalIdentity(), request.getMainClassIdentity(),
			request.copyMainClassIdentityFacts(), request.copyFieldIdentities(), request.copyFunctionIdentities(), loweredPlanIdentity, runtimeReasonIdentity,
			outputManifestIdentity, files, runtimeReasons);
	}

	static function file(path:String, kind:String, contents:String):OcamlTargetProgramFile
		return {
			path: path,
			kind: kind,
			contents: contents,
			sha256: Sha256.make(haxe.io.Bytes.ofString(contents)).toHex()
		};

	/** Apply the same OCaml value-name contract regardless of compiler host. **/
	static function targetValueName(moduleId:String, typeName:String, memberName:String):String
		return OcamlNameTools.normalizeValueIdentifier(OcamlNameTools.scopedValueName(moduleId, typeName, memberName));

	static function moduleFile(moduleId:String):String
		return moduleName(moduleId) + ".ml";

	static function moduleName(moduleId:String):String {
		final normalized = moduleId.split(".").join("_");
		if (normalized.length == 0)
			throw "OCaml target program core requires a module name";
		final first = normalized.charCodeAt(0);
		if (first == null)
			throw "OCaml target program core cannot inspect its normalized module name";
		return first >= 97 && first <= 122 ? String.fromCharCode(first - 32) + normalized.substr(1) : normalized;
	}

	static function compareText(left:String, right:String):Int
		return left < right ? -1 : (left > right ? 1 : 0);
}

/** Publishes and optionally builds one already validated shared-target plan. **/
class OcamlTargetProgramPublisher {
	public static function publish(plan:OcamlTargetProgramPlan, outputDirectory:String, route:String, build:Bool):String {
		if (plan == null)
			throw "OCaml target program publisher requires a plan";
		final output = Path.normalize(FileSystem.absolutePath(required(outputDirectory, "output directory")));
		ensureDirectory(output);
		assertOutputOwned(output, plan);
		for (file in plan.copyFiles()) {
			ensureDirectory(Path.directory(Path.join([output, file.path])));
			File.saveContent(Path.join([output, file.path]), file.contents);
		}
		File.saveContent(Path.join([output, OcamlTargetProgramCore.MANIFEST_FILE]), manifestJson(plan));
		File.saveContent(Path.join([output, OcamlTargetProgramCore.REPORT_FILE]), plan.reportJson(route));
		if (build) {
			final exitCode = Sys.command("dune", ["build", "--root", output, OcamlTargetProgramCore.ENTRY_NAME + ".exe"]);
			if (exitCode != 0)
				throw "OCaml target program Dune build failed with exit code " + exitCode;
		}
		return Path.join([output, "_build", "default", OcamlTargetProgramCore.ENTRY_NAME + ".exe"]);
	}

	static function manifestJson(plan:OcamlTargetProgramPlan):String {
		final manifest = {
			schemaVersion: 1,
			targetCoreId: OcamlTargetProgramCore.CORE_ID,
			outputManifestIdentity: plan.outputManifestIdentity,
			files: [
				for (file in plan.copyFiles())
					{
						path: file.path,
						kind: file.kind,
						sha256: file.sha256
					}
			]
		};
		return Json.stringify(manifest, null, "  ") + "\n";
	}

	static function assertOutputOwned(output:String, plan:OcamlTargetProgramPlan):Void {
		final allowed:Map<String, Bool> = [];
		for (file in plan.copyFiles())
			allowed.set(file.path, true);
		allowed.set(OcamlTargetProgramCore.MANIFEST_FILE, true);
		allowed.set(OcamlTargetProgramCore.REPORT_FILE, true);
		checkOwnedDirectory(output, "", allowed);
	}

	/** Inspect nested runtime paths before writing, preserving the existing no-unowned-output rule. **/
	static function checkOwnedDirectory(output:String, relative:String, allowed:Map<String, Bool>):Void {
		for (entry in FileSystem.readDirectory(Path.join([output, relative]))) {
			if (relative.length == 0 && entry == "_build")
				continue;
			final child = relative.length == 0 ? entry : relative + "/" + entry;
			if (FileSystem.isDirectory(Path.join([output, child]))) {
				var expected = false;
				for (path in allowed.keys())
					if (StringTools.startsWith(path, child + "/"))
						expected = true;
				if (!expected)
					throw 'OCaml target program output contains an unexpected directory "$child"';
				checkOwnedDirectory(output, child, allowed);
			} else if (!allowed.exists(child)) {
				throw 'OCaml target program output contains unowned path "$child"; choose an empty output directory';
			}
		}
	}

	static function ensureDirectory(path:String):Void {
		if (FileSystem.exists(path)) {
			if (!FileSystem.isDirectory(path))
				throw 'OCaml target program output "$path" is not a directory';
			return;
		}
		final parent = Path.directory(path);
		if (parent != path && parent.length > 0)
			ensureDirectory(parent);
		FileSystem.createDirectory(path);
	}

	static function required(value:String, label:String):String {
		final normalized = value == null ? "" : StringTools.trim(value);
		if (normalized.length == 0)
			throw "OCaml target program publisher requires " + label;
		return normalized;
	}
}
