package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.crypto.Sha256;
import haxe.ds.StringMap;
import haxe.macro.Type;
import haxe.macro.TypeTools;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDecision;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDomain;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationAliasingPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationBoxingPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationIdentityPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationMutationPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationNullPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationSelection;

/**
	Owns the OCaml carrier selected for each admitted Haxe type and use domain.

	The registry is request-local. A decision answers a semantic question once—
	for example, how an exact non-null Haxe `Int` is stored in a mutable local—so
	function plans, place plans, reports, and syntax construction cannot silently
	choose different carriers. This first slice admits only exact `Int`.
**/
class OcamlRepresentationRegistry {
	public static inline final MODEL_REVISION = "ocaml-representation-v1";

	var currentProgramRevision:Null<String> = null;
	final decisionsByKey:StringMap<OcamlRepresentationDecision> = new StringMap();
	final decisionsById:StringMap<OcamlRepresentationDecision> = new StringMap();

	public function new() {}

	/** Starts one compilation request and discards every previous decision. */
	public function beginProgram(programRevision:String):Void {
		if (programRevision.length == 0)
			throw "reflaxe.ocaml [ocaml-representation:missing-program-revision]: the target-selected program revision is empty";
		currentProgramRevision = programRevision;
		decisionsByKey.clear();
		decisionsById.clear();
	}

	/** Returns whether a Haxe type is the exact, non-null built-in `Int`. */
	public static function isExactInt(type:Type):Bool {
		var current = type;
		var following = true;
		var depth = 0;
		while (following && depth < 32) {
			depth += 1;
			current = switch (current) {
				case TLazy(resolve): resolve();
				case TMono(reference):
					final resolved = reference.get();
					if (resolved == null) {
						following = false;
						current;
					} else {
						resolved;
					}
				case TType(typeRef, parameters):
					final typedefType = typeRef.get();
					TypeTools.applyTypeParameters(typedefType.type, typedefType.params, parameters);
				case _:
					following = false;
					current;
			}
		}
		if (following)
			return false;
		return switch (current) {
			case TAbstract(abstractRef, _): final abstractType = abstractRef.get(); abstractType.pack.length == 0 && abstractType.name == "Int";
			case _:
				false;
		}
	}

	/** Registers or reuses the canonical direct carrier for exact Haxe `Int`. */
	public function selectExactInt(domain:OcamlRepresentationDomain):OcamlRepresentationDecision {
		final mutationPolicy = switch (domain) {
			case InternalValue: OcamlRepresentationMutationPolicy.ImmutableValue;
			case MutableLocalStorage, CapturedLocalStorage: OcamlRepresentationMutationPolicy.SharedLocalCell;
			case InstanceField: OcamlRepresentationMutationPolicy.InstanceFieldOwner;
			case StaticField: OcamlRepresentationMutationPolicy.StaticFieldOwner;
			case ArrayElement: OcamlRepresentationMutationPolicy.ArrayOwner;
		}
		return register({
			semanticTypeId: "Int",
			domain: domain,
			carrierTypeId: "int",
			nullPolicy: OcamlRepresentationNullPolicy.NonNull,
			identityPolicy: OcamlRepresentationIdentityPolicy.PrimitiveValue,
			aliasingPolicy: OcamlRepresentationAliasingPolicy.NoValueAlias,
			mutationPolicy: mutationPolicy,
			boxingPolicy: OcamlRepresentationBoxingPolicy.DirectUnboxed,
			reason: exactIntReason(domain),
			proof: {
				id: "direct-exact-int-storage-64-v1",
				claim: "On the currently tested 64-bit OCaml hosts, every signed 32-bit Haxe Int value fits exactly in OCaml int. This proves storage and pass-through only: overflow-sensitive and bit-pattern-sensitive operations still require HxInt, and this proof does not admit a 32-bit OCaml target."
			},
			profileEligibility: ["metal", "portable"]
		});
	}

	/**
		Registers one complete choice or rejects a conflicting choice for its key.

		Keeping this operation general lets later semantic types join the same
		registry without adding another side table. This slice's compiler path calls
		it only through `selectExactInt`.
	**/
	public function register(selection:OcamlRepresentationSelection):OcamlRepresentationDecision {
		final programRevision = requireProgramRevision();
		validateSelection(selection);
		final canonical = canonicalSelection(selection);
		final key = decisionKey(canonical.semanticTypeId, canonical.domain);
		final id = "representation:" + canonical.semanticTypeId + ":" + (canonical.domain : String);
		final revision = "sha256:" + Sha256.encode(selectionFingerprint(canonical));
		final candidate:OcamlRepresentationDecision = {
			id: id,
			key: key,
			programRevision: programRevision,
			revision: revision,
			semanticTypeId: canonical.semanticTypeId,
			domain: canonical.domain,
			carrierTypeId: canonical.carrierTypeId,
			nullPolicy: canonical.nullPolicy,
			identityPolicy: canonical.identityPolicy,
			aliasingPolicy: canonical.aliasingPolicy,
			mutationPolicy: canonical.mutationPolicy,
			boxingPolicy: canonical.boxingPolicy,
			reason: canonical.reason,
			proof: canonical.proof,
			profileEligibility: canonical.profileEligibility
		};
		final existing = decisionsByKey.get(key);
		if (existing != null) {
			if (existing.revision != candidate.revision) {
				throw 'reflaxe.ocaml [ocaml-representation:conflicting-decision]: "$key" was already assigned ${existing.carrierTypeId} (${existing.revision}), so it cannot also use ${candidate.carrierTypeId} (${candidate.revision})';
			}
			return copyDecision(existing);
		}
		if (decisionsById.exists(id))
			throw 'reflaxe.ocaml [ocaml-representation:duplicate-identity]: representation identity "$id" belongs to more than one key';
		decisionsByKey.set(key, candidate);
		decisionsById.set(id, candidate);
		return copyDecision(candidate);
	}

	/** Resolves one decision only inside the program revision that selected it. */
	public function require(representationId:String, expectedProgramRevision:String):OcamlRepresentationDecision {
		final actualProgramRevision = requireProgramRevision();
		if (expectedProgramRevision != actualProgramRevision) {
			throw 'reflaxe.ocaml [ocaml-representation:stale-program-revision]: representation "$representationId" was requested for $expectedProgramRevision, but the registry belongs to $actualProgramRevision';
		}
		final decision = decisionsById.get(representationId);
		if (decision == null)
			throw 'reflaxe.ocaml [ocaml-representation:missing-decision]: no representation decision exists for "$representationId"';
		return copyDecision(decision);
	}

	/** Returns every decision in deterministic identity order. */
	public function decisions():Array<OcamlRepresentationDecision> {
		final ids = [for (id in decisionsById.keys()) id];
		ids.sort(Reflect.compare);
		return [for (id in ids) copyDecision(cast decisionsById.get(id))];
	}

	/** Returns a deterministic digest of the program's current decisions. */
	public function revision():String {
		return "sha256:" + Sha256.encode(decisions().map(decision -> decision.id + "|" + decision.revision).join("\n"));
	}

	static function decisionKey(semanticTypeId:String, domain:OcamlRepresentationDomain):String {
		return semanticTypeId + "|" + (domain : String);
	}

	static function exactIntReason(domain:OcamlRepresentationDomain):String {
		return switch (domain) {
			case InternalValue: "An exact, non-null Haxe Int uses OCaml int directly; a later value is represented by a newer immutable binding.";
			case MutableLocalStorage: "An exact, non-null Haxe Int uses OCaml int directly inside the mutable local cell selected by the function plan.";
			case CapturedLocalStorage: "An exact, non-null Haxe Int uses OCaml int directly inside the one local cell shared with nested functions.";
			case InstanceField: "An exact, non-null Haxe Int uses OCaml int directly; the enclosing instance field owns mutation.";
			case StaticField: "An exact, non-null Haxe Int uses OCaml int directly inside the static field's OCaml ref cell.";
			case ArrayElement: "An exact, non-null Haxe Int uses OCaml int directly; the enclosing Haxe array owns element mutation.";
		}
	}

	function requireProgramRevision():String {
		if (currentProgramRevision == null)
			throw "reflaxe.ocaml [ocaml-representation:program-not-started]: beginProgram must run before selecting or resolving representations";
		return currentProgramRevision;
	}

	static function validateSelection(selection:OcamlRepresentationSelection):Void {
		if (selection.semanticTypeId.length == 0 || selection.carrierTypeId.length == 0 || selection.reason.length == 0)
			throw "reflaxe.ocaml [ocaml-representation:invalid-decision]: semantic type, carrier, and reason must be non-empty";
		if (selection.proof.id.length == 0 || selection.proof.claim.length == 0)
			throw "reflaxe.ocaml [ocaml-representation:invalid-decision]: every decision needs a named proof and claim";
		if (selection.profileEligibility.length == 0)
			throw "reflaxe.ocaml [ocaml-representation:invalid-decision]: every decision needs at least one eligible profile";
	}

	static function canonicalSelection(selection:OcamlRepresentationSelection):OcamlRepresentationSelection {
		final profiles = selection.profileEligibility.copy();
		profiles.sort(Reflect.compare);
		final uniqueProfiles:Array<String> = [];
		for (profile in profiles) {
			if (uniqueProfiles.length == 0 || uniqueProfiles[uniqueProfiles.length - 1] != profile)
				uniqueProfiles.push(profile);
		}
		return {
			semanticTypeId: selection.semanticTypeId,
			domain: selection.domain,
			carrierTypeId: selection.carrierTypeId,
			nullPolicy: selection.nullPolicy,
			identityPolicy: selection.identityPolicy,
			aliasingPolicy: selection.aliasingPolicy,
			mutationPolicy: selection.mutationPolicy,
			boxingPolicy: selection.boxingPolicy,
			reason: selection.reason,
			proof: {
				id: selection.proof.id,
				claim: selection.proof.claim
			},
			profileEligibility: uniqueProfiles
		};
	}

	static function selectionFingerprint(selection:OcamlRepresentationSelection):String {
		return [
			MODEL_REVISION,
			selection.semanticTypeId,
			(selection.domain : String),
			selection.carrierTypeId,
			(selection.nullPolicy : String),
			(selection.identityPolicy : String),
			(selection.aliasingPolicy : String),
			(selection.mutationPolicy : String),
			(selection.boxingPolicy : String),
			selection.reason,
			selection.proof.id,
			selection.proof.claim,
			selection.profileEligibility.join(",")
		].join("\n");
	}

	static function copyDecision(decision:OcamlRepresentationDecision):OcamlRepresentationDecision {
		return {
			id: decision.id,
			key: decision.key,
			programRevision: decision.programRevision,
			revision: decision.revision,
			semanticTypeId: decision.semanticTypeId,
			domain: decision.domain,
			carrierTypeId: decision.carrierTypeId,
			nullPolicy: decision.nullPolicy,
			identityPolicy: decision.identityPolicy,
			aliasingPolicy: decision.aliasingPolicy,
			mutationPolicy: decision.mutationPolicy,
			boxingPolicy: decision.boxingPolicy,
			reason: decision.reason,
			proof: {
				id: decision.proof.id,
				claim: decision.proof.claim
			},
			profileEligibility: decision.profileEligibility.copy()
		};
	}
}
#end
