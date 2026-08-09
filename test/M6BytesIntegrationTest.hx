import haxe.Json;
import haxe.crypto.Sha256;
import reflaxe.ocaml.lowered.OcamlFloatRepresentationModel.OcamlFloatRepresentationContract;
import reflaxe.ocaml.lowered.OcamlInt64RepresentationModel.OcamlInt64RepresentationContract;
import reflaxe.ocaml.tooling.ReflaxeOcamlInspection;

class M6BytesIntegrationTest {
	/**
		Updates the report's outer checksum after a test deliberately changes one
		representation. Without this step, inspection stops at the checksum and
		never reaches the deeper carrier rule that the test is meant to exercise.
	**/
	static function refreshRepresentationRevision(report:Dynamic):Void {
		final representations:Array<Dynamic> = cast Reflect.field(report, "representations");
		Reflect.setField(report, "representationRevision", "sha256:" + Sha256.encode(Json.stringify(representations)));
	}

	static function assertContains(haystack:String, needle:String, label:String):Void {
		if (haystack.indexOf(needle) < 0) {
			throw label + ": expected to find '" + needle + "'";
		}
	}

	static function assertBeforeAfter(haystack:String, marker:String, first:String, second:String, label:String):Void {
		final startIndex = haystack.indexOf(marker);
		final firstIndex = startIndex < 0 ? -1 : haystack.indexOf(first, startIndex);
		final secondIndex = startIndex < 0 ? -1 : haystack.indexOf(second, startIndex);
		if (startIndex < 0 || firstIndex < 0 || secondIndex < 0 || firstIndex >= secondIndex)
			throw label + ": expected '" + first + "' before '" + second + "' after '" + marker + "'";
	}

	static function hasCommand(cmd:String):Bool {
		try {
			final p = new sys.io.Process(cmd, ["--version"]);
			final code = p.exitCode();
			p.close();
			return code == 0;
		} catch (_) {
			return false;
		}
	}

	static function exeNameFromOutDir(outDir:String):String {
		final base = haxe.io.Path.withoutDirectory(haxe.io.Path.normalize(outDir));
		final out = new StringBuf();
		for (i in 0...base.length) {
			final c = base.charCodeAt(i);
			final isAlphaNum = (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || (c >= 48 && c <= 57);
			out.add(isAlphaNum ? String.fromCharCode(c) : "_");
		}
		var s = out.toString();
		if (s.length == 0)
			s = "ocaml_app";
		if (s.charCodeAt(0) >= 48 && s.charCodeAt(0) <= 57)
			s = "_" + s;
		return s.toLowerCase();
	}

	static function main() {
		final outDir = "out_ocaml_m6_bytes_" + Std.string(Std.int(Date.now().getTime()));
		sys.FileSystem.createDirectory(outDir);

		final args = [
			"-cp",
			"test",
			"-main",
			"BytesMain",
			"--no-output",
			"-lib",
			"reflaxe.ocaml",
			"-D",
			"no-traces",
			"-D",
			"no_traces",
			"-D",
			"ocaml_no_build",
			"-D",
			"ocaml_lowering_report",
			"-D",
			"ocaml_output=" + outDir
		];

		final exitCode = Sys.command("haxe", args);
		if (exitCode != 0)
			throw "haxe compile failed: " + exitCode;

		final runtimePath = outDir + "/runtime/HxBytes.ml";
		if (!sys.FileSystem.exists(runtimePath))
			throw "missing runtime: " + runtimePath;

		final mainPath = outDir + "/BytesMain.ml";
		if (!sys.FileSystem.exists(mainPath))
			throw "missing output: " + mainPath;

		final content = sys.io.File.getContent(mainPath);
		assertContains(content, "HxBytes.alloc", "alloc");
		assertContains(content, "HxBytes.ofString", "ofString");
		assertContains(content, "HxBytes.length", "length");
		assertContains(content, "HxBytes.get", "get");
		assertContains(content, "HxBytes.fastGet", "fastGet");
		assertContains(content, "HxBytes.set", "set");
		assertContains(content, "HxBytes.getUInt16", "getUInt16");
		assertContains(content, "HxBytes.setUInt16", "setUInt16");
		assertContains(content, "HxBytes.getInt32", "getInt32");
		assertContains(content, "HxBytes.setInt32", "setInt32");
		assertContains(content, "HxBytes.getInt64", "planned getInt64");
		assertContains(content, "HxBytes.setInt64", "planned setInt64");
		assertContains(content, "HxBytes.getFloat", "planned getFloat");
		assertContains(content, "HxBytes.setFloat", "planned setFloat");
		assertContains(content, "HxBytes.getDouble", "planned getDouble");
		assertContains(content, "HxBytes.setDouble", "planned setDouble");
		assertContains(content, "Haxe_Int64.___int64_create", "exact generated Int64 constructor");
		assertContains(content, "HxBytes.blit", "blit");
		assertContains(content, "HxBytes.sub", "sub");
		assertContains(content, "HxBytes.compare", "compare");
		assertContains(content, "HxBytes.getString", "getString");
		assertContains(content, "HxBytes.toString", "toString");
		assertContains(content, "HxBytes.toHex", "toHex");
		assertContains(content, "HxBytes.fill", "fill");
		assertContains(content, "HxBytes.create", "internal constructor");
		assertContains(content, "let __bytes_receiver_", "planned Bytes receiver materialization");
		assertContains(content, "let __bytes_receiver_input_", "planned typed Bytes receiver input");
		assertContains(content, "HxRuntime.is_null (Obj.repr __bytes_receiver_input_", "planned nullable Bytes receiver check");
		assertContains(content, 'HxRuntime.hx_throw_typed (Obj.repr "Null Access") ["String"; "Dynamic"]', "planned nullable Bytes receiver failure");
		assertContains(content, "let __bytes_arg_0_", "planned Bytes first argument materialization");
		assertContains(content, "let __bytes_arg_1_", "planned Bytes second argument materialization");
		assertContains(content, "let __bytes_destination_", "planned Bytes mutation receiver materialization");
		assertContains(content, "let __bytes_mutation_arg_0_", "planned Bytes mutation first argument materialization");
		assertContains(content, "let __bytes_access_receiver_", "planned Bytes access receiver materialization");
		assertContains(content, "let __bytes_access_arg_0_", "planned Bytes access argument materialization");
		assertContains(content, "let __bytes_access_converted_arg_0_", "planned converted Bytes access argument materialization");
		assertContains(content, "HxRuntime.nullable_int_unwrap", "planned nullable Int mutation crossing");
		assertContains(content, "HxBytes.requireMultiByteInt", "planned nullable multi-byte Int crossing");
		assertBeforeAfter(content, '"uint16-null-position-receiver"', '"uint16-null-position-value"', "HxBytes.requireMultiByteInt",
			"raw multi-byte inputs must run before conversion");
		assertBeforeAfter(content, '"byte-null-position-receiver"', '"byte-null-position-value"', "HxRuntime.nullable_int_unwrap",
			"raw single-byte inputs must run before conversion");
		assertBeforeAfter(content, '"float32-null-position-receiver"', '"float32-null-position-value"', "HxBytes.requireMultiByteInt",
			"raw Float32 inputs must run before nullable position conversion");

		final requirementReportPath = outDir + "/ocaml_runtime_requirement_report.json";
		if (!sys.FileSystem.exists(requirementReportPath))
			throw "missing runtime requirement report: " + requirementReportPath;
		final requirementReport = sys.io.File.getContent(requirementReportPath);
		assertContains(requirementReport, '"semanticCapability": "haxe-bytes-read"', "Bytes read runtime capability");
		assertContains(requirementReport, '"implementationFeature": "haxe-bytes-read-v1"', "Bytes read runtime explanation");
		assertContains(requirementReport, '"semanticCapability": "haxe-bytes-mutation"', "Bytes mutation runtime capability");
		assertContains(requirementReport, '"implementationFeature": "haxe-bytes-mutation-v1"', "Bytes mutation runtime explanation");
		assertContains(requirementReport, '"semanticCapability": "haxe-bytes-access"', "Bytes access runtime capability");
		assertContains(requirementReport, '"implementationFeature": "haxe-bytes-access-v5"', "Bytes access runtime explanation");
		assertContains(requirementReport, "2-byte access", "UInt16 access width explanation");
		assertContains(requirementReport, "4-byte access", "Int32 access width explanation");
		assertContains(requirementReport, "8-byte access", "Int64 access width explanation");
		assertContains(requirementReport, "little-endian ordering", "multi-byte ordering explanation");
		assertContains(requirementReport, "ieee-754-binary32", "Float32 value explanation");
		assertContains(requirementReport, "ieee-754-binary64", "Float64 value explanation");
		assertContains(requirementReport, "deterministic OutsideBounds policy", "nullable multi-byte failure explanation");

		final loweringReportPath = outDir + "/ocaml_lowering_report.json";
		if (!sys.FileSystem.exists(loweringReportPath))
			throw "missing lowering report: " + loweringReportPath;
		final loweringReportText = sys.io.File.getContent(loweringReportPath);
		final loweringReport:Dynamic = Json.parse(loweringReportText);
		final representations:Array<Dynamic> = cast Reflect.field(loweringReport, "representations");
		final int64Representation = Lambda.find(representations,
			decision -> Reflect.field(decision, "id") == OcamlInt64RepresentationContract.INTERNAL_REPRESENTATION_ID);
		if (int64Representation == null
			|| Reflect.field(int64Representation, "boxingPolicy") != "direct-nominal-value-carrier"
			|| Reflect.field(int64Representation, "nominalTargetModuleName") != OcamlInt64RepresentationContract.TARGET_MODULE_NAME
			|| Reflect.field(int64Representation, "nominalTargetTypeName") != OcamlInt64RepresentationContract.TARGET_TYPE_NAME
			|| Reflect.field(int64Representation, "nominalLayoutRevision") != OcamlInt64RepresentationContract.LAYOUT_REVISION) {
			throw "lowering report did not seal the exact Int64 nominal value carrier";
		}
		final floatRepresentation = Lambda.find(representations,
			decision -> Reflect.field(decision, "id") == OcamlFloatRepresentationContract.INTERNAL_REPRESENTATION_ID);
		if (floatRepresentation == null
			|| Reflect.field(floatRepresentation, "semanticTypeId") != OcamlFloatRepresentationContract.SEMANTIC_TYPE_ID
			|| Reflect.field(floatRepresentation, "carrierTypeId") != OcamlFloatRepresentationContract.CARRIER_TYPE_ID
			|| Reflect.field(floatRepresentation, "domain") != "internal-value"
			|| Reflect.field(floatRepresentation, "boxingPolicy") != "direct-unboxed"
			|| Reflect.field(Reflect.field(floatRepresentation, "proof"), "id") != OcamlFloatRepresentationContract.PROOF_ID) {
			throw "lowering report did not seal the exact internal Float carrier";
		}
		final inspection = ReflaxeOcamlInspection.inspect(Sys.getCwd(), outDir, true);
		if (inspection.lowering.status != "present" || !inspection.summary.valid)
			throw "public inspection rejected valid exact Int64 or Float representations";
		Reflect.setField(int64Representation, "nominalLayoutRevision", "sha256:" + StringTools.lpad("", "0", 64));
		refreshRepresentationRevision(loweringReport);
		sys.io.File.saveContent(loweringReportPath, Json.stringify(loweringReport, null, "  ") + "\n");
		final corruptedInspection = ReflaxeOcamlInspection.inspect(Sys.getCwd(), outDir, true);
		sys.io.File.saveContent(loweringReportPath, loweringReportText);
		if (corruptedInspection.lowering.status != "invalid"
			|| corruptedInspection.lowering.message.indexOf("sealed exact Int64 nominal value carrier") < 0) {
			throw 'public inspection accepted a corrupted Int64 carrier layout: status=${corruptedInspection.lowering.status} message=${corruptedInspection.lowering.message}';
		}
		Reflect.setField(int64Representation, "nominalLayoutRevision", OcamlInt64RepresentationContract.LAYOUT_REVISION);
		final floatProof:Dynamic = Reflect.field(floatRepresentation, "proof");
		Reflect.setField(floatProof, "id", "corrupted-float-proof");
		refreshRepresentationRevision(loweringReport);
		sys.io.File.saveContent(loweringReportPath, Json.stringify(loweringReport, null, "  ") + "\n");
		final corruptedFloatInspection = ReflaxeOcamlInspection.inspect(Sys.getCwd(), outDir, true);
		sys.io.File.saveContent(loweringReportPath, loweringReportText);
		if (corruptedFloatInspection.lowering.status != "invalid"
			|| corruptedFloatInspection.lowering.message.indexOf("sealed exact Float internal value carrier") < 0) {
			throw "public inspection accepted a corrupted Float carrier proof";
		}

		// Best-effort: if dune+ocamlc are available, ensure dune build + run succeeds.
		if (hasCommand("dune") && hasCommand("ocamlc")) {
			final exeName = exeNameFromOutDir(outDir);
			final prev = Sys.getCwd();
			Sys.setCwd(outDir);
			final exit = Sys.command("dune", ["build", "./" + exeName + ".exe"]);
			if (exit == 0) {
				final builtExe = "_build/default/" + exeName + ".exe";
				if (sys.FileSystem.exists(builtExe)) {
					final runExit = Sys.command("./" + builtExe, []);
					if (runExit != 0)
						throw "built exe failed: " + runExit;
				}
			}
			Sys.setCwd(prev);
			if (exit != 0)
				throw "dune build failed: " + exit;
		}
	}
}
