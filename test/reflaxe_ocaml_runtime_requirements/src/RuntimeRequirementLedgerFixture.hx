import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin;
import reflaxe.ocaml.lowered.OcamlIMapInterfaceModel.OcamlIMapInterfaceContract;
import reflaxe.ocaml.lowered.OcamlIMapInterfaceModel.OcamlIMapInterfaceConversionDecision;
import reflaxe.ocaml.lowered.OcamlIMapInterfaceModel.OcamlIMapInterfaceConversionRole;
import reflaxe.ocaml.lowered.OcamlIMapInterfaceModel.OcamlIMapInterfaceSourceKind;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDomain;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDecision;
import reflaxe.ocaml.lowered.OcamlStandardIMapCallModel.OcamlStandardIMapCallContract;
import reflaxe.ocaml.lowered.OcamlStandardIMapCallModel.OcamlStandardIMapCallTarget;
import reflaxe.ocaml.lowered.OcamlStandardIMapCallModel.OcamlStandardIMapKeyKind;
import reflaxe.ocaml.lowered.OcamlStandardIMapCallModel.OcamlStandardIMapOperation;
import reflaxe.ocaml.lowered.OcamlStandardIMapCallModel.OcamlStandardIMapResultForm;
import reflaxe.ocaml.lowered.OcamlStandardIMapCallModel.OcamlStandardIMapStringifier;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementLedger;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirement;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirementCause;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirementSourceKind;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirementSubjectKind;

using StringTools;

/** Focused checks for runtime explanations recorded at compiler decision points. **/
class RuntimeRequirementLedgerFixture {
	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function expectFailure(label:String, expectedMessage:String, action:Void->Void):Void {
		var failed = false;
		try {
			action();
		} catch (error:Dynamic) {
			failed = true;
			final message = Std.string(error);
			if (!message.contains(expectedMessage))
				throw '$label failed with an unexpected message: $message';
		}
		if (!failed)
			throw '$label should have failed.';
	}

	static function requirementById(requirements:Array<OcamlRuntimeRequirement>, id:String):OcamlRuntimeRequirement {
		for (requirement in requirements)
			if (requirement.id == id)
				return requirement;
		throw 'Missing runtime requirement "$id".';
	}

	static function exactStringRepresentation():OcamlRepresentationDecision {
		return {
			id: "representation:String:internal-value",
			key: "String|internal-value",
			programRevision: "program:fixture-a",
			revision: "sha256:dd4135006802a036d2a3f27ec92d60af669c5f73d419c9525e2f3297bc2a8504",
			semanticTypeId: "String",
			domain: OcamlRepresentationDomain.InternalValue,
			carrierTypeId: "string",
			nullPolicy: "runtime-sentinel",
			identityPolicy: "primitive-value",
			aliasingPolicy: "no-value-alias",
			storageMutationPolicy: "immutable-binding",
			valueMutationPolicy: "immutable-value",
			boxingPolicy: "nullable-string-carrier",
			implicitDefaultPolicy: "runtime-null-sentinel",
			reason: "Fixture exact String carrier.",
			proof: {
				id: "nullable-string-runtime-sentinel-carrier-v1",
				claim: "Fixture proof for the exact String null sentinel."
			},
			profileEligibility: ["metal", "portable"],
			nominalTargetModuleName: null,
			nominalTargetTypeName: null,
			nominalLayoutRevision: null
		};
	}

	static function standardIMapToStringTarget():OcamlStandardIMapCallTarget {
		final target:OcamlStandardIMapCallTarget = {
			operation: OcamlStandardIMapOperation.ToString,
			keyKind: OcamlStandardIMapKeyKind.StringKey,
			receiverSemanticTypeId: "haxe.IMap<String, Int>",
			receiverCarrierId: "HxMap.string_map",
			keySemanticTypeId: "String",
			valueSemanticTypeId: "Int",
			argumentSemanticTypeIds: [],
			resultSemanticTypeId: "String",
			runtimeModule: "HxMap",
			runtimeFunction: "pairs_string",
			resultForm: OcamlStandardIMapResultForm.FormattedEntries,
			iteratorModule: "HxIterator",
			iteratorFunction: "of_array",
			keyStringifier: OcamlStandardIMapStringifier.ExactString,
			valueStringifier: OcamlStandardIMapStringifier.ExactInt,
			runtimeCapabilities: [
				OcamlStandardIMapCallContract.MAP_RUNTIME_CAPABILITY,
				OcamlStandardIMapCallContract.ITERATOR_RUNTIME_CAPABILITY,
				OcamlStandardIMapCallContract.ARRAY_RUNTIME_CAPABILITY,
				OcamlStandardIMapCallContract.STRING_TEXT_RUNTIME_CAPABILITY
			],
			proofId: OcamlStandardIMapCallContract.PROOF_ID,
			proofClaim: "Fixture proof for a sealed standard IMap String-to-Int text operation."
		};
		OcamlStandardIMapCallContract.require(target);
		return target;
	}

	/**
		Builds a plain saved IMap conversion without any live compiler objects.

		The runtime ledger consumes this report-shaped value after target planning.
		Keeping the fixture at this boundary proves that validating saved runtime
		facts does not accidentally require the active Reflaxe compiler request.
	**/
	static function standardStringMapInterfaceConversion(runtimeCapabilities:Array<String>):OcamlIMapInterfaceConversionDecision {
		return {
			id: "imap-interface-conversion:runtime-fixture",
			source: {file: "src/Main.hx", min: 20, max: 36},
			role: OcamlIMapInterfaceConversionRole.CallArgument,
			roleIdentity: "call-argument:0",
			sourceKind: OcamlIMapInterfaceSourceKind.StandardStringMap,
			sourceSemanticTypeId: "HxMap<Int>",
			sourceCarrierTypeId: OcamlStandardIMapCallContract.carrierId(OcamlStandardIMapKeyKind.StringKey),
			targetSemanticTypeId: "haxe.IMap<String, Int>",
			targetCarrierTypeId: OcamlIMapInterfaceContract.TARGET_CARRIER_ID,
			keySemanticTypeId: "String",
			valueSemanticTypeId: "Int",
			standardKeyKind: OcamlStandardIMapKeyKind.StringKey,
			keyStringifier: OcamlStandardIMapCallContract.stringifierForSemanticTypeId("String"),
			valueStringifier: OcamlStandardIMapCallContract.stringifierForSemanticTypeId("Int"),
			methods: [],
			runtimeCapabilities: runtimeCapabilities,
			proofId: OcamlIMapInterfaceContract.CONVERSION_PROOF_ID,
			proofClaim: OcamlIMapInterfaceContract.CONVERSION_PROOF_CLAIM,
			functionId: "Main|Main|static|main",
			programRevision: "program:runtime-fixture",
			bodyRevision: "body:runtime-fixture",
			pipelineRevision: "pipeline:runtime-fixture"
		};
	}

	static function main():Void {
		final macHaxePath = ["", "Users", "alice", "haxe", "versions", "4.3.7", "std", "haxe", "Exception.hx"].join("/");
		assertTrue(OcamlLoweredOrigin.normalizeSourcePath(macHaxePath) == "haxe-stdlib/haxe/Exception.hx",
			"upstream Haxe paths should not retain a home-directory prefix");
		assertTrue(OcamlLoweredOrigin.normalizeSourcePath("C:\\HaxeToolkit\\haxe\\std\\haxe\\Exception.hx") == "haxe-stdlib/haxe/Exception.hx",
			"Windows Haxe paths should use the same stable standard-library identity");
		assertTrue(OcamlLoweredOrigin.normalizeSourcePath("/opt/cache/acme/src/acme/Thing.hx") == "external-source/acme/Thing.hx",
			"external libraries should keep useful package context without a machine-local prefix");
		assertTrue(OcamlLoweredOrigin.normalizeSourcePath(Sys.getCwd() + "/src/Main.hx") == "src/Main.hx",
			"project source should retain its repository-relative path");
		assertTrue(OcamlLoweredOrigin.normalizeSourcePath("../../private/acme/Thing.hx") == "external-source/acme/Thing.hx",
			"parent-directory segments should not leak a path outside the project");
		final source:OcamlLoweredSourceSpan = {file: "../../private/acme/Thing.hx", min: 10, max: 18};
		expectFailure("record before program", "before the program revision begins", () -> {
			final unbound = new OcamlRuntimeRequirementLedger();
			unbound.recordPlacePlan("place:a:int-update", "place:a", source, "Int", ["place:a:runtime:haxe-int32-add"]);
		});
		final ledger = new OcamlRuntimeRequirementLedger();
		ledger.beginProgram("program:fixture-a");
		final exactIMapCapabilities = OcamlStandardIMapCallContract.adapterRuntimeCapabilities("String", "Int");
		final iMapRequirements = OcamlRuntimeRequirementLedger.requirementsForIMapInterfaceConversion(standardStringMapInterfaceConversion(exactIMapCapabilities));
		assertTrue(iMapRequirements.length == exactIMapCapabilities.length,
			"a saved IMap conversion should expand through the framework-free validation contract");
		final rejectedIMapLedger = new OcamlRuntimeRequirementLedger();
		rejectedIMapLedger.beginProgram("program:invalid-imap-fixture");
		expectFailure("invalid saved IMap conversion", "conflicting source kind, method surface, or runtime inventory",
			() -> rejectedIMapLedger.recordIMapInterfaceConversion(standardStringMapInterfaceConversion([OcamlRuntimeRequirementLedger.HAXE_MAP])));
		assertTrue(rejectedIMapLedger.requirementsSorted().length == 0,
			"a malformed saved IMap conversion should fail before any runtime requirement is accepted");
		final stringRepresentation = exactStringRepresentation();
		ledger.recordRepresentationDecision(stringRepresentation);
		ledger.recordPlacePlan("place:a:int-update", "place:a", source, "Int", ["place:a:runtime:haxe-int32-add"]);
		ledger.recordPlacePlan("place:b:array-update", "place:b", source, "Int", [
			"place:b:runtime:haxe-array-element-get",
			"place:b:runtime:haxe-int32-add",
			"place:b:runtime:haxe-array-element-set"
		]);
		ledger.recordCompilerInfrastructure(OcamlRuntimeRequirementLedger.CORE_RUNTIME);
		ledger.recordCompilerInfrastructure(OcamlRuntimeRequirementLedger.TYPE_REGISTRY);
		ledger.recordCompilerInfrastructure(OcamlRuntimeRequirementLedger.TYPE_REGISTRY_DYNAMIC_ARGS);
		ledger.recordCompilerInfrastructure(OcamlRuntimeRequirementLedger.TYPE_REGISTRY_OPTIONAL_NULL);
		ledger.recordCompilerInfrastructure(OcamlRuntimeRequirementLedger.TYPE_REGISTRY_OPTIONAL_STRING_NULL);
		ledger.recordCompilerInfrastructure(OcamlRuntimeRequirementLedger.TYPE_REGISTRY_RUNTIME_UNBOX);
		ledger.recordNativeBoundary(OcamlRuntimeRequirementLedger.HAXE_STANDARD_IO, "sys.io.Stdio::sys.io._Stdio.NativeHxStdio.read_byte", source,
			"HxStdio.read_byte");
		ledger.recordNativeBoundary(OcamlRuntimeRequirementLedger.HAXE_STACK_TRACES, "haxe.CallStack::haxe._CallStack.NativeHxBacktrace.callstack_lines",
			source, "HxBacktrace.callstack_lines");
		ledger.recordNativeBoundary(OcamlRuntimeRequirementLedger.HAXE_FLOAT_BIT_CONVERSIONS, "haxe.io.FPHelper::haxe.io._FPHelper.NativeFPHelper.i32ToFloat",
			source, "HxFPHelper.i32ToFloat");
		ledger.recordNativeBoundary(OcamlRuntimeRequirementLedger.HAXE_PROCESS, "sys.io.Process::sys.io._Process.NativeHxProcess.spawn", source,
			"HxProcess.spawn");
		ledger.recordNativeBoundary(OcamlRuntimeRequirementLedger.HAXE_FILE, "sys.io.File::sys.io._File.NativeHxFile.getContent", source, "HxFile.getContent");
		ledger.recordNativeBoundary(OcamlRuntimeRequirementLedger.HAXE_FILE_STREAM, "sys.io.File::sys.io._File.NativeHxFileStream.open_in", source,
			"HxFileStream.open_in");
		ledger.recordNativeBoundary(OcamlRuntimeRequirementLedger.HAXE_THREAD, "sys.thread.NativeHxThread::sys.thread.NativeHxThread.thread_current", source,
			"HxThread.thread_current");
		ledger.recordNativeBoundary(OcamlRuntimeRequirementLedger.HAXE_FILE_SYSTEM, "sys.FileSystem::sys.FileSystem.stat", source, "HxFileSystem.stat");
		ledger.recordNativeBoundary(OcamlRuntimeRequirementLedger.HAXE_SYSTEM, "Sys::Sys.args", source, "HxSys.args");
		ledger.recordNativeBoundary(OcamlRuntimeRequirementLedger.HAXE_MAP, "haxe.ds.NativeHxMap::haxe.ds.NativeHxMap.set_string", source, "HxMap.set_string");
		ledger.recordNativeBoundary(OcamlRuntimeRequirementLedger.HAXE_ITERATOR, "haxe.ds.NativeHxMapIterator::haxe.ds.NativeHxMapIterator.of_array", source,
			"HxIterator.of_array");
		final standardIMapTarget = standardIMapToStringTarget();
		ledger.recordStandardIMapCall("call:imap-to-string", source, ["metal", "portable"], standardIMapTarget);
		final requirements = ledger.requirementsSorted();
		assertTrue(requirements.length == 26,
			"each representation, lowering, compiler, and declared native-boundary decision should retain its own runtime explanation");
		assertTrue(requirements[0].id == "call:imap-to-string:runtime:haxe-array", "requirements should be sorted by stable identity");
		final selectedRequirements = ledger.requirementsByIds(["place:b:runtime:haxe-array-element-set", "place:a:runtime:haxe-int32-add"]);
		assertTrue(selectedRequirements.length == 2
			&& selectedRequirements[0].id == "place:b:runtime:haxe-array-element-set"
			&& selectedRequirements[1].id == "place:a:runtime:haxe-int32-add",
			"a sealed plan should receive only its exact runtime requirements in plan order");
		expectFailure("repeated exact requirement lookup", 'lookup repeats "place:a:runtime:haxe-int32-add"',
			() -> ledger.requirementsByIds(["place:a:runtime:haxe-int32-add", "place:a:runtime:haxe-int32-add"]));
		expectFailure("missing exact requirement lookup", 'lookup is missing "place:missing:runtime:haxe-int32-add"',
			() -> ledger.requirementsByIds(["place:missing:runtime:haxe-int32-add"]));
		final placeRequirement = requirementById(requirements, "place:a:runtime:haxe-int32-add");
		assertTrue(placeRequirement.sourceId == "place:a", "the requirement should retain its Haxe-expression identity");
		assertTrue(placeRequirement.subject.kind == OcamlRuntimeRequirementSubjectKind.HaxeType && placeRequirement.subject.id == "Int",
			"a Haxe operation should identify the semantic type it supports");
		assertTrue(placeRequirement.source.file == "external-source/acme/Thing.hx",
			"the ledger should remove machine-local parent paths before retaining a source location");
		assertTrue(placeRequirement.decisionId == "place:a:int-update", "the requirement should name the lowering decision that caused it");
		assertTrue(placeRequirement.rootModules[0] == "HxInt", "Haxe Int addition should select the HxInt implementation root");
		final stringRequirement = requirementById(requirements, "representation:String:internal-value:runtime:haxe-string-null-sentinel");
		assertTrue(stringRequirement.sourceKind == OcamlRuntimeRequirementSourceKind.RepresentationDecision
			&& stringRequirement.cause == OcamlRuntimeRequirementCause.RepresentationDecision,
			"the exact String sentinel should identify its sealed representation as the cause");
		final reflectedStringNullRequirement = requirementById(requirements, "compiler:generated:HxTypeRegistry:optional-string-null");
		assertTrue(reflectedStringNullRequirement.rootModules.join(",") == "HxString",
			"the generated registry's optional String sentinel should have its own exact HxString requirement");
		assertTrue(stringRequirement.sourceId == stringRepresentation.id + "@" + stringRepresentation.revision,
			"the String requirement should bind the exact representation revision");
		assertTrue(stringRequirement.subject.kind == OcamlRuntimeRequirementSubjectKind.HaxeType
			&& stringRequirement.subject.id == "String",
			"the String sentinel requirement should identify the Haxe type it supports");
		assertTrue(stringRequirement.rootModules[0] == "HxString", "the exact String null sentinel should select the HxString implementation root");
		final registryRequirement = requirementById(requirements, "compiler:generated:HxTypeRegistry:type-registry");
		assertTrue(registryRequirement.subject.kind == OcamlRuntimeRequirementSubjectKind.GeneratedModule
			&& registryRequirement.subject.id == "HxTypeRegistry",
			"compiler-generated output should identify the module it supports");
		assertTrue(registryRequirement.rootModules[0] == "HxType", "the generated type registry should select the HxType implementation root");
		final coreRequirement = requirementById(requirements, "compiler:runtime-packaging:core");
		assertTrue(coreRequirement.subject.kind == OcamlRuntimeRequirementSubjectKind.CompilerPolicy
			&& coreRequirement.subject.id == "runtime-packaging",
			"the runtime core should name the compiler policy that requires it");
		final stdioRequirement = requirementById(requirements, "native:sys.io.Stdio::sys.io._Stdio.NativeHxStdio.read_byte:runtime:haxe-standard-io");
		assertTrue(stdioRequirement.sourceKind == OcamlRuntimeRequirementSourceKind.NativeBoundary
			&& stdioRequirement.subject.kind == OcamlRuntimeRequirementSubjectKind.NativeBoundary,
			"a typed extern should identify its native boundary as the runtime source and subject");
		assertTrue(stdioRequirement.subject.id.indexOf("HxStdio.read_byte") >= 0, "the native-boundary subject should name the checked target symbol");
		assertTrue(stdioRequirement.rootModules[0] == "HxStdio", "Haxe standard I/O should select the HxStdio implementation root");
		final stackRequirement = requirementById(requirements,
			"native:haxe.CallStack::haxe._CallStack.NativeHxBacktrace.callstack_lines:runtime:haxe-stack-traces");
		assertTrue(stackRequirement.subject.id.indexOf("HxBacktrace.callstack_lines") >= 0, "the stack-trace boundary should name the checked target symbol");
		assertTrue(stackRequirement.rootModules[0] == "HxBacktrace", "Haxe stack traces should select the HxBacktrace implementation root");
		final floatBitsRequirement = requirementById(requirements,
			"native:haxe.io.FPHelper::haxe.io._FPHelper.NativeFPHelper.i32ToFloat:runtime:haxe-float-bit-conversions");
		assertTrue(floatBitsRequirement.subject.id.indexOf("HxFPHelper.i32ToFloat") >= 0,
			"the floating-point bit-conversion boundary should name the checked target symbol");
		assertTrue(floatBitsRequirement.rootModules[0] == "HxFPHelper", "Haxe floating-point bit conversions should select the HxFPHelper implementation root");
		final processRequirement = requirementById(requirements, "native:sys.io.Process::sys.io._Process.NativeHxProcess.spawn:runtime:haxe-process");
		assertTrue(processRequirement.subject.id.indexOf("HxProcess.spawn") >= 0, "the process boundary should name the checked target symbol");
		assertTrue(processRequirement.rootModules[0] == "HxProcess", "Haxe process operations should select the HxProcess implementation root");
		final fileRequirement = requirementById(requirements, "native:sys.io.File::sys.io._File.NativeHxFile.getContent:runtime:haxe-file");
		assertTrue(fileRequirement.subject.id.indexOf("HxFile.getContent") >= 0, "the whole-file boundary should name the checked target symbol");
		assertTrue(fileRequirement.rootModules[0] == "HxFile", "Haxe whole-file operations should select the HxFile implementation root");
		final fileStreamRequirement = requirementById(requirements, "native:sys.io.File::sys.io._File.NativeHxFileStream.open_in:runtime:haxe-file-stream");
		assertTrue(fileStreamRequirement.subject.id.indexOf("HxFileStream.open_in") >= 0, "the file-stream boundary should name the checked target symbol");
		assertTrue(fileStreamRequirement.rootModules[0] == "HxFileStream", "Haxe file streams should select the HxFileStream implementation root");
		final threadRequirement = requirementById(requirements,
			"native:sys.thread.NativeHxThread::sys.thread.NativeHxThread.thread_current:runtime:haxe-thread");
		assertTrue(threadRequirement.subject.id.indexOf("HxThread.thread_current") >= 0, "the thread boundary should name the checked target symbol");
		assertTrue(threadRequirement.rootModules[0] == "HxThread", "Haxe thread operations should select the HxThread implementation root");
		final fileSystemRequirement = requirementById(requirements, "native:sys.FileSystem::sys.FileSystem.stat:runtime:haxe-file-system");
		assertTrue(fileSystemRequirement.subject.id.indexOf("HxFileSystem.stat") >= 0, "the filesystem boundary should name the checked target symbol");
		assertTrue(fileSystemRequirement.rootModules[0] == "HxFileSystem", "Haxe filesystem operations should select the HxFileSystem implementation root");
		final systemRequirement = requirementById(requirements, "native:Sys::Sys.args:runtime:haxe-system");
		assertTrue(systemRequirement.subject.id.indexOf("HxSys.args") >= 0, "the system boundary should name the checked target symbol");
		assertTrue(systemRequirement.rootModules[0] == "HxSys", "Haxe system operations should select the HxSys implementation root");
		final mapRequirement = requirementById(requirements, "native:haxe.ds.NativeHxMap::haxe.ds.NativeHxMap.set_string:runtime:haxe-map");
		assertTrue(mapRequirement.subject.id.indexOf("HxMap.set_string") >= 0, "the Map boundary should name the checked target symbol");
		assertTrue(mapRequirement.rootModules[0] == "HxMap", "typed Haxe Map operations should select the HxMap implementation root");
		final iteratorRequirement = requirementById(requirements,
			"native:haxe.ds.NativeHxMapIterator::haxe.ds.NativeHxMapIterator.of_array:runtime:haxe-iterator");
		assertTrue(iteratorRequirement.subject.id.indexOf("HxIterator.of_array") >= 0, "the iterator boundary should name the checked target symbol");
		assertTrue(iteratorRequirement.rootModules[0] == "HxIterator", "typed Haxe iterators should select the HxIterator implementation root");
		final standardIMapRequirement = requirementById(requirements, "call:imap-to-string:runtime:haxe-map");
		assertTrue(standardIMapRequirement.sourceKind == OcamlRuntimeRequirementSourceKind.HaxeExpression
			&& standardIMapRequirement.sourceId == "call:imap-to-string",
			"one standard IMap requirement should remain bound to the exact typed call occurrence");
		assertTrue(standardIMapRequirement.subject.kind == OcamlRuntimeRequirementSubjectKind.HaxeType
			&& standardIMapRequirement.subject.id == "haxe.IMap<String, Int>",
			"one standard IMap requirement should identify the sealed typed receiver");
		assertTrue(standardIMapRequirement.rootModules[0] == "HxMap", "the typed standard IMap carrier selection should explain its HxMap runtime root");
		assertTrue(ledger.rootModulesSorted()
			.join(",") == "HxArray,HxBacktrace,HxFPHelper,HxFile,HxFileStream,HxFileSystem,HxInt,HxIterator,HxMap,HxProcess,HxRuntime,HxStdio,HxString,HxSys,HxThread,HxType",
			"root modules should be deduplicated and sorted");
		final firstRevision = ledger.revision();
		ledger.recordPlacePlan("place:a:int-update", "place:a", source, "Int", ["place:a:runtime:haxe-int32-add"]);
		assertTrue(ledger.revision() == firstRevision, "recording the same facts twice should be deterministic");

		expectFailure("unscoped requirement", "is not scoped to origin",
			() -> ledger.recordPlacePlan("place:c:update", "place:c", source, "Int", ["haxe-int32-add"]));
		expectFailure("unknown capability", "Unknown place runtime capability",
			() -> ledger.recordPlacePlan("place:c:update", "place:c", source, "Int", ["place:c:runtime:not-supported"]));
		expectFailure("unknown compiler capability", "Unknown compiler runtime capability",
			() -> ledger.recordCompilerInfrastructure("compiler-not-supported"));
		expectFailure("unknown native capability", "Unknown native runtime capability",
			() -> ledger.recordNativeBoundary("native-not-supported", "fixture.Native.call", source, "HxStdio.call"));
		expectFailure("native module mismatch", "requires \"HxStdio\"",
			() -> ledger.recordNativeBoundary(OcamlRuntimeRequirementLedger.HAXE_STANDARD_IO, "fixture.Native.call", source, "OtherRuntime.call"));
		expectFailure("process native module mismatch", "requires \"HxProcess\"",
			() -> ledger.recordNativeBoundary(OcamlRuntimeRequirementLedger.HAXE_PROCESS, "fixture.NativeProcess.spawn", source, "OtherRuntime.spawn"));
		expectFailure("whole-file native module mismatch", "requires \"HxFile\"",
			() -> ledger.recordNativeBoundary(OcamlRuntimeRequirementLedger.HAXE_FILE, "fixture.NativeFile.getContent", source, "OtherRuntime.getContent"));
		expectFailure("file-stream native module mismatch", "requires \"HxFileStream\"",
			() -> ledger.recordNativeBoundary(OcamlRuntimeRequirementLedger.HAXE_FILE_STREAM, "fixture.NativeFileStream.open_in", source,
				"OtherRuntime.open_in"));
		expectFailure("thread native module mismatch", "requires \"HxThread\"",
			() -> ledger.recordNativeBoundary(OcamlRuntimeRequirementLedger.HAXE_THREAD, "fixture.NativeThread.current", source,
				"OtherRuntime.thread_current"));
		expectFailure("filesystem native module mismatch", "requires \"HxFileSystem\"",
			() -> ledger.recordNativeBoundary(OcamlRuntimeRequirementLedger.HAXE_FILE_SYSTEM, "fixture.NativeFileSystem.stat", source, "OtherRuntime.stat"));
		expectFailure("system native module mismatch", "requires \"HxSys\"",
			() -> ledger.recordNativeBoundary(OcamlRuntimeRequirementLedger.HAXE_SYSTEM, "fixture.Sys.args", source, "OtherRuntime.args"));
		expectFailure("map native module mismatch", "requires \"HxMap\"",
			() -> ledger.recordNativeBoundary(OcamlRuntimeRequirementLedger.HAXE_MAP, "fixture.NativeMap.set_string", source, "OtherRuntime.set_string"));
		expectFailure("iterator native module mismatch", "requires \"HxIterator\"",
			() -> ledger.recordNativeBoundary(OcamlRuntimeRequirementLedger.HAXE_ITERATOR, "fixture.NativeIterator.of_array", source, "OtherRuntime.of_array"));
		final invalidStandardIMapTarget:Dynamic = OcamlStandardIMapCallContract.copy(standardIMapTarget);
		invalidStandardIMapTarget.runtimeCapabilities = standardIMapTarget.runtimeCapabilities.concat(["not-supported"]);
		expectFailure("invalid standard IMap runtime inventory", "invalid runtime-capability inventory",
			() -> ledger.recordStandardIMapCall("call:invalid-imap", source, ["metal", "portable"], cast invalidStandardIMapTarget));
		final invalidStringRepresentation:Dynamic = Reflect.copy(stringRepresentation);
		invalidStringRepresentation.carrierTypeId = "Obj.t";
		expectFailure("invalid String representation", "does not match the sealed exact String null-sentinel contract",
			() -> ledger.recordRepresentationDecision(cast invalidStringRepresentation));
		expectFailure("subject/source mismatch", "does not match source kind", () -> ledger.record({
			id: "invalid:subject",
			sourceKind: OcamlRuntimeRequirementSourceKind.HaxeExpression,
			sourceId: "place:invalid",
			source: source,
			semanticCapability: "invalid-subject-fixture",
			cause: OcamlRuntimeRequirementCause.LoweringDecision,
			decisionId: "fixture:invalid-subject",
			subject: {
				kind: OcamlRuntimeRequirementSubjectKind.GeneratedModule,
				id: "WrongOwner"
			},
			implementationFeature: "invalid-fixture-v1",
			rootModules: ["HxRuntime"],
			profileEligibility: ["portable"],
			explanation: "This intentionally invalid record proves subject ownership is checked."
		}));
		ledger.beginProgram("program:fixture-b");
		assertTrue(ledger.requirementsSorted().length == 0, "a new program must not inherit requirements from the previous compile");
		assertTrue(ledger.revision() != firstRevision, "the requirement revision must identify its normalized program");
		Sys.println("REFLAXE_OCAML_RUNTIME_REQUIREMENT_LEDGER_FIXTURE:PASS");
	}
}
