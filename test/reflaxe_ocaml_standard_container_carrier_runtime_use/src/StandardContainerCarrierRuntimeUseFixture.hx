package;

import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Expr.ComplexType;
import haxe.macro.TypeTools;
import reflaxe.ocaml.CompilationContext;
import reflaxe.ocaml.ast.OcamlModuleItem;
import reflaxe.ocaml.ast.OcamlTypeExpr;
import reflaxe.ocaml.ast.OcamlTypeDeclKind;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.lowered.OcamlStandardContainerCarrierModel.OcamlStandardContainerCarrierContract;
import reflaxe.ocaml.lowered.OcamlStandardContainerCarrierModel.OcamlStandardContainerCarrierDecision;
import reflaxe.ocaml.lowered.OcamlStandardContainerCarrierModel.OcamlStandardContainerCarrierKind;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementLedger;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseAuthority;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeReference;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

using StringTools;

/**
	Checks the private OCaml storage type for standard Haxe arrays and bytes.

	A carrier is the concrete OCaml type that holds a Haxe value. For example,
	`Array<Int>` uses `int HxArray.t`. The final typed Haxe declaration must
	authorize that private name before the target prints it.
**/
class StandardContainerCarrierRuntimeUseFixture {
	static inline final PROGRAM_REVISION = "program:standard-container-carrier-runtime-use";
	static inline final PIPELINE_REVISION = "pipeline:standard-container-carrier-runtime-use";
	static final source:OcamlLoweredSourceSpan = {
		file: "test/standard-container-carrier-runtime-use/Main.hx",
		min: 0,
		max: 1
	};

	public static macro function run():Expr {
		final array = seal((macro :Array<Int>), "array", OcamlStandardContainerCarrierKind.ArrayCarrier, "HxArray.t", "Array<Int>", "Int");
		final nestedArray = seal((macro :Array<Array<String>>), "nested-array", OcamlStandardContainerCarrierKind.ArrayCarrier, "HxArray.t",
			"Array<Array<String>>", "Array<String>");
		final bytes = seal((macro :haxe.io.Bytes), "bytes", OcamlStandardContainerCarrierKind.BytesCarrier, "HxBytes.t", "haxe.io.Bytes", "<none>");

		proveRuntimeUse(array, "HxArray");
		proveRuntimeUse(bytes, "HxBytes");
		proveFinalActivation(array, bytes);
		if (array.id == nestedArray.id)
			throw "Nested Array carriers must keep independent owner identities.";

		reject((macro :fixture.Array<Int>), "user Array lookalike");
		reject((macro :fixture.Bytes), "user Bytes lookalike");
		reject((macro :String), "unrelated String type");

		Sys.println("REFLAXE_OCAML_STANDARD_CONTAINER_CARRIER_RUNTIME_USE:PASS");
		return macro null;
	}

	static function seal(type:ComplexType, ownerId:String, expectedKind:OcamlStandardContainerCarrierKind, expectedSymbol:String, expectedSemanticType:String,
			expectedElementType:String):OcamlStandardContainerCarrierDecision {
		final resolved = Context.resolveType(type, Context.currentPos());
		final materialization = OcamlStandardContainerCarrierContract.seal(resolved, ownerId, PROGRAM_REVISION, PIPELINE_REVISION, source);
		if (materialization == null)
			throw '$ownerId did not select a standard container carrier from ${TypeTools.toString(resolved)}.';
		final decision = materialization.decision;
		if (decision.kind != expectedKind
			|| decision.exactSymbol != expectedSymbol
			|| decision.semanticTypeId != expectedSemanticType
			|| decision.elementSemanticTypeId != expectedElementType)
			throw '$ownerId selected the wrong carrier facts: ${haxe.Json.stringify(decision)}.';
		OcamlStandardContainerCarrierContract.requireDecision(decision);
		return decision;
	}

	static function reject(type:ComplexType, label:String):Void {
		final resolved = Context.resolveType(type, Context.currentPos());
		if (OcamlStandardContainerCarrierContract.seal(resolved, label, PROGRAM_REVISION, PIPELINE_REVISION, source) != null)
			throw '$label must not receive standard container carrier authority.';
	}

	static function proveRuntimeUse(decision:OcamlStandardContainerCarrierDecision, expectedRoot:String):Void {
		final requirements = OcamlRuntimeRequirementLedger.requirementsForStandardContainerCarrier(decision);
		if (requirements.length != 1 || requirements[0].rootModules.join(",") != expectedRoot)
			throw 'Carrier ${decision.id} must select one direct $expectedRoot runtime requirement.';
		final occurrence = decision.runtimeUseOccurrences[0];
		final authority = new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements, decision.runtimeUseOccurrences);
		final reference = authority.typeIdentifier(occurrence.id, occurrence.planRevision, occurrence.exactSymbol);
		authority.reconcileType(OcamlTypeExpr.TRuntimeIdent(reference));

		expectFailure("plain carrier", 'plain private runtime reference ${decision.exactSymbol}',
			() -> new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements,
				decision.runtimeUseOccurrences).reconcileType(OcamlTypeExpr.TIdent(decision.exactSymbol)));
		expectFailure("stale carrier", "stale runtime use",
			() -> new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements,
				decision.runtimeUseOccurrences).typeIdentifier(occurrence.id, occurrence.planRevision + ":stale", occurrence.exactSymbol));
		final metalOnly = copyOccurrence(occurrence, ["metal"]);
		expectFailure("wrong carrier profile", "not eligible for profile portable",
			() -> new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements,
				[metalOnly]).typeIdentifier(metalOnly.id, metalOnly.planRevision, metalOnly.exactSymbol));
	}

	/**
		Proves that only a carrier present in final structured output becomes active.

		The unused Bytes decision represents a temporary type candidate. It must not
		add `HxBytes` to the generated source bundle or create a missing-use error.
	**/
	static function proveFinalActivation(used:OcamlStandardContainerCarrierDecision, unused:OcamlStandardContainerCarrierDecision):Void {
		final unusedContext = new CompilationContext();
		unusedContext.beginRuntimeRequirementProgram(PROGRAM_REVISION, "portable");
		unusedContext.stageStandardContainerCarrierRuntimeUse(unused);
		unusedContext.finalRuntimeUses.finishProgram();
		expectFailure("unused staged carrier", 'lookup is missing "${unused.runtimeRequirementIds[0]}"',
			() -> unusedContext.runtimeRequirementsByIds(unused.runtimeRequirementIds));

		final staleContext = new CompilationContext();
		staleContext.beginRuntimeRequirementProgram(PROGRAM_REVISION + ":next", "portable");
		expectFailure("stale staged carrier", "uses program revision", () -> staleContext.stageStandardContainerCarrierRuntimeUse(used));

		final usedContext = new CompilationContext();
		usedContext.beginRuntimeRequirementProgram(PROGRAM_REVISION, "portable");
		usedContext.stageStandardContainerCarrierRuntimeUse(used);
		final reference = checkedReference(used);
		usedContext.finalRuntimeUses.observeModuleItems([
			OcamlModuleItem.IType([
				{
					name: "used_array",
					params: [],
					kind: OcamlTypeDeclKind.Alias(OcamlTypeExpr.TRuntimeApp(reference, [OcamlTypeExpr.TIdent("int")]))
				}
			], false)
		], "standard-container-carrier-fixture", usedContext.activateStagedTypeRuntimeUse);
		usedContext.finalRuntimeUses.finishProgram();
		if (usedContext.runtimeRequirementsByIds(used.runtimeRequirementIds).length != 1)
			throw "A final standard Array carrier must activate one HxArray requirement.";

		final corruptedContext = new CompilationContext();
		corruptedContext.beginRuntimeRequirementProgram(PROGRAM_REVISION, "portable");
		corruptedContext.stageStandardContainerCarrierRuntimeUse(used);
		final original = used.runtimeUseOccurrences[0];
		final wrongOwner = copyOccurrence(original, original.profileEligibility, original.ownerId + ":wrong");
		final requirements = OcamlRuntimeRequirementLedger.requirementsForStandardContainerCarrier(used);
		final authority = new OcamlRuntimeUseAuthority(used.revision, "portable", requirements, [wrongOwner]);
		final corrupted = authority.typeIdentifier(wrongOwner.id, wrongOwner.planRevision, wrongOwner.exactSymbol);
		authority.reconcileType(OcamlTypeExpr.TRuntimeIdent(corrupted));
		expectFailure("corrupted staged carrier", "no longer matches its staged facts", () -> corruptedContext.finalRuntimeUses.observeModuleItems([
			OcamlModuleItem.IType([
				{
					name: "corrupted_array",
					params: [],
					kind: OcamlTypeDeclKind.Alias(OcamlTypeExpr.TRuntimeIdent(corrupted))
				}
			], false)
		], "corrupted-standard-container-carrier-fixture",
			corruptedContext.activateStagedTypeRuntimeUse));
	}

	static function checkedReference(decision:OcamlStandardContainerCarrierDecision):OcamlRuntimeReference {
		final requirements = OcamlRuntimeRequirementLedger.requirementsForStandardContainerCarrier(decision);
		final occurrence = decision.runtimeUseOccurrences[0];
		final authority = new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements, decision.runtimeUseOccurrences);
		final reference = authority.typeIdentifier(occurrence.id, occurrence.planRevision, occurrence.exactSymbol);
		authority.reconcileType(OcamlTypeExpr.TRuntimeIdent(reference));
		return reference;
	}

	static function copyOccurrence(source:OcamlRuntimeUseOccurrence, profiles:Array<String>, ?ownerId:String):OcamlRuntimeUseOccurrence {
		return {
			id: source.id,
			planRevision: source.planRevision,
			ownerId: ownerId == null ? source.ownerId : ownerId,
			requirementId: source.requirementId,
			domain: source.domain,
			exactSymbol: source.exactSymbol,
			role: source.role,
			order: source.order,
			source: {
				file: source.source.file,
				min: source.source.min,
				max: source.source.max
			},
			profileEligibility: profiles,
			cardinality: source.cardinality
		};
	}

	static function expectFailure(label:String, marker:String, operation:Void->Void):Void {
		var message:Null<String> = null;
		try {
			operation();
		} catch (error:Dynamic) {
			message = Std.string(error);
		}
		if (message == null || !message.contains(marker))
			throw '$label must fail with "$marker", received ${message == null ? "no error" : message}.';
	}
}
