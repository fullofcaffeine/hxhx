package;

import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Expr.ComplexType;
import haxe.macro.Type;
import haxe.macro.TypeTools;
import reflaxe.ocaml.CompilationContext;
import reflaxe.ocaml.ast.OcamlModuleItem;
import reflaxe.ocaml.ast.OcamlTypeExpr;
import reflaxe.ocaml.ast.OcamlTypeDeclKind;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.lowered.OcamlStandardMapCarrierModel.OcamlStandardMapCarrierContract;
import reflaxe.ocaml.lowered.OcamlStandardMapCarrierModel.OcamlStandardMapCarrierDecision;
import reflaxe.ocaml.lowered.OcamlStandardMapCarrierModel.OcamlStandardMapCarrierKind;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementLedger;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseAuthority;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeReference;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

using StringTools;

/**
	Checks the private OCaml type selected for each standard Haxe Map family.

	A carrier is the concrete OCaml storage type. For example, `StringMap<Int>`
	uses `int HxMap.string_map`. The fixture proves that the typed Haxe Map
	decision authorizes this private name before the target type is printed.
**/
class StandardMapCarrierRuntimeUseFixture {
	static inline final PROGRAM_REVISION = "program:standard-map-carrier-runtime-use";
	static inline final PIPELINE_REVISION = "pipeline:standard-map-carrier-runtime-use";
	static final source:OcamlLoweredSourceSpan = {
		file: "test/standard-map-carrier-runtime-use/Main.hx",
		min: 0,
		max: 1
	};

	public static macro function run():Expr {
		final decisions = [
			seal((macro :haxe.ds.StringMap<Int>), "string-class", OcamlStandardMapCarrierKind.StringKeys, "HxMap.string_map", "String", "Int"),
			seal((macro :haxe.ds.IntMap<String>), "int-class", OcamlStandardMapCarrierKind.IntKeys, "HxMap.int_map", "Int", "String"),
			seal((macro :haxe.ds.ObjectMap<{
				id:Int
			}
				, String>),
				"object-class", OcamlStandardMapCarrierKind.ObjectIdentityKeys, "HxMap.obj_map", "{ id : Int }", "String"),
			seal((macro :Map<String, Int>), "string-abstract", OcamlStandardMapCarrierKind.StringKeys, "HxMap.string_map", "String", "Int"),
			seal((macro :Map<Int, String>), "int-abstract", OcamlStandardMapCarrierKind.IntKeys, "HxMap.int_map", "Int", "String"),
			seal((macro :Map<{
				id:Int
			}
				, String>),
				"object-abstract", OcamlStandardMapCarrierKind.ObjectIdentityKeys, "HxMap.obj_map", "{ id : Int }", "String"),
			seal((macro :Map<String, Map<Int, String>>), "nested-abstract", OcamlStandardMapCarrierKind.StringKeys, "HxMap.string_map", "String",
				"Map<Int, String>")
		];
		for (decision in decisions)
			proveRuntimeUse(decision);
		proveFinalActivation(decisions[0], decisions[1]);

		final notMap = Context.resolveType((macro :Array<Int>), Context.currentPos());
		if (OcamlStandardMapCarrierContract.seal(notMap, "not-map", PROGRAM_REVISION, PIPELINE_REVISION, source) != null)
			throw "Array<Int> must not receive standard Map carrier authority.";

		Sys.println("REFLAXE_OCAML_STANDARD_MAP_CARRIER_RUNTIME_USE:PASS");
		return macro null;
	}

	static function seal(type:ComplexType, ownerId:String, expectedKind:OcamlStandardMapCarrierKind, expectedSymbol:String, expectedKey:String,
			expectedValue:String):OcamlStandardMapCarrierDecision {
		final resolved = Context.resolveType(type, Context.currentPos());
		final materialization = OcamlStandardMapCarrierContract.seal(resolved, ownerId, PROGRAM_REVISION, PIPELINE_REVISION, source);
		if (materialization == null)
			throw '$ownerId did not select a standard Map carrier from ${TypeTools.toString(resolved)} (${Std.string(resolved)}).';
		final decision = materialization.decision;
		if (decision.kind != expectedKind
			|| decision.exactSymbol != expectedSymbol
			|| decision.keySemanticTypeId != expectedKey
			|| decision.valueSemanticTypeId != expectedValue)
			throw '$ownerId selected the wrong carrier facts: ${haxe.Json.stringify(decision)}.';
		OcamlStandardMapCarrierContract.requireDecision(decision);
		return decision;
	}

	static function proveRuntimeUse(decision:OcamlStandardMapCarrierDecision):Void {
		final requirements = OcamlRuntimeRequirementLedger.requirementsForStandardMapCarrier(decision);
		if (requirements.length != 1 || requirements[0].rootModules.join(",") != "HxMap")
			throw 'Carrier ${decision.id} must select one direct HxMap runtime requirement.';
		if (decision.runtimeUseOccurrences.length != 1)
			throw 'Carrier ${decision.id} must own one checked type identifier.';

		final occurrence = decision.runtimeUseOccurrences[0];
		final authority = new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements, decision.runtimeUseOccurrences);
		final reference = authority.typeIdentifier(occurrence.id, occurrence.planRevision, occurrence.exactSymbol);
		authority.reconcileType(OcamlTypeExpr.TRuntimeIdent(reference));

		expectFailure("plain carrier", 'plain private runtime reference ${decision.exactSymbol}',
			() -> new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements,
				decision.runtimeUseOccurrences).reconcileType(OcamlTypeExpr.TApp(decision.exactSymbol, [OcamlTypeExpr.TIdent("int")])));
		expectFailure("missing carrier", "missing runtime use",
			() -> new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements,
				decision.runtimeUseOccurrences).reconcileType(OcamlTypeExpr.TIdent("unit")));
		expectFailure("stale carrier", "stale runtime use",
			() -> new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements,
				decision.runtimeUseOccurrences).typeIdentifier(occurrence.id, occurrence.planRevision + ":stale", occurrence.exactSymbol));
		expectFailure("wrong carrier symbol", "wrong target symbol",
			() -> new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements,
				decision.runtimeUseOccurrences).typeIdentifier(occurrence.id, occurrence.planRevision, occurrence.exactSymbol + "_wrong"));
		final metalOnly = copyOccurrence(occurrence, ["metal"]);
		expectFailure("wrong carrier profile", "not eligible for profile portable",
			() -> new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements,
				[metalOnly]).typeIdentifier(metalOnly.id, metalOnly.planRevision, metalOnly.exactSymbol));
	}

	/**
		Proves that only a carrier present in final structured output becomes active.

		The unused decision represents a temporary type candidate. It must not add an
		`HxMap` requirement or a missing-use error when the request finishes.
	**/
	static function proveFinalActivation(used:OcamlStandardMapCarrierDecision, unused:OcamlStandardMapCarrierDecision):Void {
		final unusedContext = new CompilationContext();
		unusedContext.beginRuntimeRequirementProgram(PROGRAM_REVISION, "portable");
		unusedContext.stageStandardMapCarrierRuntimeUse(unused);
		unusedContext.finalRuntimeUses.finishProgram();
		expectFailure("unused staged carrier", 'lookup is missing "${unused.runtimeRequirementIds[0]}"',
			() -> unusedContext.runtimeRequirementsByIds(unused.runtimeRequirementIds));

		final staleContext = new CompilationContext();
		staleContext.beginRuntimeRequirementProgram(PROGRAM_REVISION + ":next", "portable");
		expectFailure("stale staged carrier", "uses program revision", () -> staleContext.stageStandardMapCarrierRuntimeUse(used));

		final usedContext = new CompilationContext();
		usedContext.beginRuntimeRequirementProgram(PROGRAM_REVISION, "portable");
		usedContext.stageStandardMapCarrierRuntimeUse(used);
		final reference = checkedReference(used);
		usedContext.finalRuntimeUses.observeModuleItems([
			OcamlModuleItem.IType([
				{
					name: "used_map",
					params: [],
					kind: OcamlTypeDeclKind.Alias(OcamlTypeExpr.TRuntimeApp(reference, [OcamlTypeExpr.TIdent("int")]))
				}
			], false)
		], "standard-map-carrier-fixture",
			usedContext.activateStandardMapCarrierRuntimeUse);
		usedContext.finalRuntimeUses.finishProgram();
		if (usedContext.runtimeRequirementsByIds(used.runtimeRequirementIds).length != 1)
			throw "A final standard Map carrier must activate one HxMap requirement.";

		final corruptedContext = new CompilationContext();
		corruptedContext.beginRuntimeRequirementProgram(PROGRAM_REVISION, "portable");
		corruptedContext.stageStandardMapCarrierRuntimeUse(used);
		final originalOccurrence = used.runtimeUseOccurrences[0];
		final wrongOwnerOccurrence = copyOccurrence(originalOccurrence, originalOccurrence.profileEligibility, originalOccurrence.ownerId + ":wrong");
		final wrongOwnerAuthority = new OcamlRuntimeUseAuthority(used.revision, "portable",
			OcamlRuntimeRequirementLedger.requirementsForStandardMapCarrier(used), [wrongOwnerOccurrence]);
		final corrupted = wrongOwnerAuthority.typeIdentifier(wrongOwnerOccurrence.id, wrongOwnerOccurrence.planRevision, wrongOwnerOccurrence.exactSymbol);
		wrongOwnerAuthority.reconcileType(OcamlTypeExpr.TRuntimeIdent(corrupted));
		expectFailure("corrupted staged carrier", "no longer matches its staged facts", () -> corruptedContext.finalRuntimeUses.observeModuleItems([
			OcamlModuleItem.IType([
				{
					name: "corrupted_map",
					params: [],
					kind: OcamlTypeDeclKind.Alias(OcamlTypeExpr.TRuntimeIdent(corrupted))
				}
			], false)
		], "corrupted-standard-map-carrier-fixture",
			corruptedContext.activateStandardMapCarrierRuntimeUse));
	}

	static function checkedReference(decision:OcamlStandardMapCarrierDecision):OcamlRuntimeReference {
		final requirements = OcamlRuntimeRequirementLedger.requirementsForStandardMapCarrier(decision);
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
