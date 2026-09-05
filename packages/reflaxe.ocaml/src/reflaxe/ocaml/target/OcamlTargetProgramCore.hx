package reflaxe.ocaml.target;

import haxe.Json;
import haxe.crypto.Sha256;
import haxe.io.Path;
import reflaxe.ocaml.OcamlNameTools;
import reflaxe.ocaml.ast.OcamlASTPrinter;
import reflaxe.ocaml.ast.OcamlLetBinding;
import reflaxe.ocaml.ast.OcamlModuleItem;
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
	final normalizedClassIdentityFacts:Array<Null<String>>;
	final normalizedFieldIdentities:Array<String>;
	final normalizedFunctionIdentities:Array<String>;

	public function new(hostProgramRevision:String, mainModuleId:String, normalizedInputIdentity:String, normalizedClassIdentity:String,
			normalizedClassIdentityFacts:Array<Null<String>>, normalizedFieldIdentities:Array<String>, normalizedFunctionIdentities:Array<String>,
			loweredPlanIdentity:String, runtimeReasonIdentity:String, outputManifestIdentity:String, files:Array<OcamlTargetProgramFile>) {
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
			// Revision 1 admits only primitive literals and source-local reads.
			// No selected expression can depend on another source module.
			dependencyModuleIds: [],
			runtimeReasons: [],
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
	public static inline final CORE_ID = "reflaxe.ocaml.target-program-core.v1";
	public static inline final REPORT_FILE = "ocaml_shared_target_report.json";
	public static inline final MANIFEST_FILE = "ocaml_shared_target_manifest.json";
	public static inline final ENTRY_NAME = "reflaxe_ocaml_entry";

	/** Revision 1 is a runtime-free portable tracer and must not imply metal support. **/
	public static function requireProfile(profile:String):Void {
		if (profile != "portable")
			throw 'OCaml target program core revision 1 does not support profile "$profile"';
	}

	public static function lower(request:OcamlTargetProgramRequest):OcamlTargetProgramPlan {
		if (request == null)
			throw "OCaml target program core requires a normalized request";
		final printer = new OcamlASTPrinter();
		final bindings = new Array<OcamlLetBinding>();
		for (field in request.copyFieldInitializers())
			bindings.push({
				name: targetValueName(field.moduleId, field.sourceTypeName, field.sourceFieldName),
				expr: OcamlTargetExpressionLowerer.build(field.initializer)
			});
		for (fn in request.copyFunctions())
			bindings.push({
				name: targetValueName(fn.moduleId, fn.sourceTypeName, fn.sourceFunctionName),
				expr: OcamlTargetFunctionLowerer.build(fn)
			});
		bindings.sort((left, right) -> compareText(left.name, right.name));

		final modulePath = moduleFile(request.mainModuleId);
		final moduleContents = printer.printModule([OcamlModuleItem.ILet(bindings, false)]) + "\n";
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
		files.sort((left, right) -> compareText(left.path, right.path));

		final loweredParts:Array<Null<String>> = [CORE_ID, request.getCanonicalIdentity(), modulePath, moduleContents];
		final loweredPlanIdentity = Sha256.encode(OcamlTargetDeclarationCodec.encode(loweredParts));
		final runtimeReasonIdentity = Sha256.encode(OcamlTargetDeclarationCodec.encode([CORE_ID, "runtime-reasons-v1", "none"]));
		final manifestParts:Array<Null<String>> = [CORE_ID, "output-manifest-v1", Std.string(files.length)];
		for (output in files) {
			manifestParts.push(output.path);
			manifestParts.push(output.kind);
			manifestParts.push(output.sha256);
		}
		final outputManifestIdentity = Sha256.encode(OcamlTargetDeclarationCodec.encode(manifestParts));
		return new OcamlTargetProgramPlan(request.hostProgramRevision, request.mainModuleId, request.getCanonicalIdentity(), request.getMainClassIdentity(),
			request.copyMainClassIdentityFacts(), request.copyFieldIdentities(), request.copyFunctionIdentities(), loweredPlanIdentity, runtimeReasonIdentity,
			outputManifestIdentity, files);
	}

	static function file(path:String, kind:String, contents:String):OcamlTargetProgramFile
		return {
			path: path,
			kind: kind,
			contents: contents,
			sha256: Sha256.encode(contents)
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
		for (file in plan.copyFiles())
			File.saveContent(Path.join([output, file.path]), file.contents);
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
		for (entry in FileSystem.readDirectory(output)) {
			if (entry == "_build")
				continue;
			if (!allowed.exists(entry))
				throw 'OCaml target program output contains unowned path "$entry"; choose an empty output directory';
			final path = Path.join([output, entry]);
			if (FileSystem.isDirectory(path))
				throw 'OCaml target program output contains an unexpected directory "$entry"';
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
