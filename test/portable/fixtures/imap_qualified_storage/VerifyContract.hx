import reflaxe.ocaml.lowered.OcamlIMapInterfaceModel.OcamlIMapInterfaceContract;
import reflaxe.ocaml.lowered.OcamlIMapInterfaceModel.OcamlIMapStorageAliasDecision;
import reflaxe.ocaml.lowered.OcamlIMapInterfaceModel.OcamlIMapStorageAliasNullPolicy;

/** Exact standard type forms must not admit unrelated owners, generic arguments, or storage. */
class VerifyContract {
	static function decision(input:{source:String, ?nullable:Bool, ?carrier:String}):OcamlIMapStorageAliasDecision {
		final policy = input.nullable == true ? OcamlIMapStorageAliasNullPolicy.CheckNullAndUnbox : OcamlIMapStorageAliasNullPolicy.NonNullableSource;
		final result:OcamlIMapStorageAliasDecision = {
			id: "alias-test",
			source: {file: "Main.hx", min: 1, max: 2},
			sourceSemanticTypeId: input.source,
			sourceCarrierTypeId: input.carrier == null ? (input.nullable == true ? "Obj.t" : "HxMap.string_map") : input.carrier,
			preservedCarrierTypeId: "HxMap.string_map",
			targetSemanticTypeId: "haxe.IMap<String, Item>",
			keySemanticTypeId: "String",
			valueSemanticTypeId: "Item",
			standardKeyKind: StringKey,
			nullPolicy: policy,
			uses: [
				{
					source: {file: "Main.hx", min: 3, max: 4},
					nativeOperation: "values_string",
					carrierTypeId: "HxMap.string_map"
				}
			],
			runtimeRequirementIds: OcamlIMapInterfaceContract.storageAliasRuntimeRequirementIds("alias-test", policy),
			runtimeUseOccurrences: [],
			proofId: OcamlIMapInterfaceContract.STORAGE_ALIAS_PROOF_ID,
			proofClaim: OcamlIMapInterfaceContract.STORAGE_ALIAS_PROOF_CLAIM,
			functionId: "function-test",
			programRevision: "program-test",
			bodyRevision: "body-test",
			pipelineRevision: "pipeline-test"
		};
		for (use in OcamlIMapInterfaceContract.storageAliasRuntimeUseOccurrencesFor(result))
			result.runtimeUseOccurrences.push(use);
		return result;
	}

	static function reject(input:{source:String, ?nullable:Bool, ?carrier:String}):Void {
		var rejected = false;
		try
			OcamlIMapInterfaceContract.requireStorageAlias(decision(input))
		catch (error:haxe.Exception) {
			if (error.message.indexOf("invalid-storage-alias") < 0)
				throw error;
			rejected = true;
		}
		if (!rejected)
			throw "Accepted conflicting source or carrier: " + input.source;
	}

	static function main():Void {
		for (name in ["Map", "haxe.ds.Map"]) {
			final source = name + "<String, Item>";
			OcamlIMapInterfaceContract.requireStorageAlias(decision({source: source}));
			OcamlIMapInterfaceContract.requireStorageAlias(decision({source: "Null<" + source + ">", nullable: true}));
			reject({source: name + "<Int, Item>"});
			reject({source: name + "<String, OtherItem>"});
			reject({source: "Null<" + source + ">"});
			reject({source: source, nullable: true});
			reject({source: source, carrier: "HxMap.int_map"});
		}
		for (source in [
			"other.Map<String, Item>",
			"other.haxe.ds.Map<String, Item>",
			"haxe.ds.Map<String, Item, Extra>"
		])
			reject({source: source});
		Sys.println("QUALIFIED_MAP_CONTRACT:PASS");
	}
}
