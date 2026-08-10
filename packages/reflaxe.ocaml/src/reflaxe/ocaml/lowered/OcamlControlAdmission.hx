package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime || eval)
import haxe.crypto.Sha256;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;

/** The control-transfer family whose typed planning result is being explained. */
enum abstract OcamlControlAdmissionFamily(String) to String {
	var Return = "return";
	var Loop = "loop";
	var Throw = "throw";
}

/**
	Whether a function needed and received one complete typed control plan.

	`not-needed` means the final function body had no transfer in that family that
	required the private control channel. `blocked` means at least one occurrence
	existed, but the typed planner could not represent the complete family. Return,
	loop, and throw migrations may still route such a family through their older
	implementation. A non-empty catch is stricter: function sealing rejects it, so
	it cannot fall through to target syntax without one complete catch chain.
**/
enum abstract OcamlControlAdmissionStatus(String) to String {
	var NotNeeded = "not-needed";
	var Admitted = "admitted";
	var Blocked = "blocked";
}

/** One report-safe reason that prevented a complete typed control decision. */
typedef OcamlControlAdmissionBlocker = {
	final code:String;
	final occurrenceId:String;
	final source:OcamlLoweredSourceSpan;
	final semanticTypeId:Null<String>;
	final message:String;
}

/** The complete disposition of one return, loop-transfer, or throw family. */
typedef OcamlControlFamilyAdmission = {
	final family:OcamlControlAdmissionFamily;
	final status:OcamlControlAdmissionStatus;
	final occurrenceCount:Int;
	final decisionCount:Int;
	final blockers:Array<OcamlControlAdmissionBlocker>;
}

/** The admitted or blocked disposition of one exact source `try` expression. */
typedef OcamlControlCatchAdmission = {
	final occurrenceId:String;
	final source:OcamlLoweredSourceSpan;
	final status:OcamlControlAdmissionStatus;
	final chainId:Null<String>;
	final blockers:Array<OcamlControlAdmissionBlocker>;
}

/**
	Immutable explanation of control planning for one final Haxe function body.

	This snapshot contains only strings, numbers, and copied source spans. It can
	be saved in the lowering report without retaining Haxe compiler objects or the
	request-local lookup maps used later by OCaml syntax generation.
**/
typedef OcamlControlAdmissionSnapshot = {
	final id:String;
	final functionId:String;
	final programRevision:String;
	final bodyRevision:String;
	final pipelineRevision:String;
	final families:Array<OcamlControlFamilyAdmission>;
	final catches:Array<OcamlControlCatchAdmission>;
	final revision:String;
}

/** Builds, copies, and validates report-safe control-admission snapshots. */
class OcamlControlAdmissionContract {
	public static inline final MODEL = "typed-ocaml-control-admission-v1";

	/** Creates one deterministic blocker at the exact rejected typed occurrence. */
	public static function blocker(code:String, occurrenceId:String, source:OcamlLoweredSourceSpan, ?semanticTypeId:String):OcamlControlAdmissionBlocker {
		return {
			code: code,
			occurrenceId: occurrenceId,
			source: copySource(source),
			semanticTypeId: semanticTypeId,
			message: blockerMessage(code, semanticTypeId)
		};
	}

	/** Derives the family state after the planner has visited the complete body. */
	public static function family(family:OcamlControlAdmissionFamily, occurrenceCount:Int, decisionCount:Int, admitted:Bool,
			blockers:Array<OcamlControlAdmissionBlocker>):OcamlControlFamilyAdmission {
		final status = occurrenceCount == 0 ? OcamlControlAdmissionStatus.NotNeeded : (admitted ? OcamlControlAdmissionStatus.Admitted : OcamlControlAdmissionStatus.Blocked);
		return {
			family: family,
			status: status,
			occurrenceCount: occurrenceCount,
			decisionCount: decisionCount,
			blockers: blockers.map(copyBlocker)
		};
	}

	/** Seals one complete, plain-data snapshot against its exact function binding. */
	public static function create(binding:OcamlFunctionPlanBinding, families:Array<OcamlControlFamilyAdmission>,
			catches:Array<OcamlControlCatchAdmission>):OcamlControlAdmissionSnapshot {
		final normalizedFamilies = families.map(copyFamily);
		normalizedFamilies.sort((left, right) -> Reflect.compare((left.family : String), (right.family : String)));
		final normalizedCatches = catches.map(copyCatch);
		normalizedCatches.sort((left, right) -> Reflect.compare(left.occurrenceId, right.occurrenceId));
		final id = "control-admission:" + Sha256.encode(binding.functionId).substr(0, 24);
		final revision = revisionForValues(id, binding.functionId, binding.programRevision, binding.bodyRevision, binding.pipelineRevision,
			normalizedFamilies, normalizedCatches);
		final snapshot:OcamlControlAdmissionSnapshot = {
			id: id,
			functionId: binding.functionId,
			programRevision: binding.programRevision,
			bodyRevision: binding.bodyRevision,
			pipelineRevision: binding.pipelineRevision,
			families: normalizedFamilies,
			catches: normalizedCatches,
			revision: revision
		};
		requireSnapshot(snapshot);
		return copySnapshot(snapshot);
	}

	/** Creates a complete `not-needed` snapshot for a declaration with no body. */
	public static function empty(binding:OcamlFunctionPlanBinding):OcamlControlAdmissionSnapshot {
		return create(binding, [
			family(OcamlControlAdmissionFamily.Return, 0, 0, false, []),
			family(OcamlControlAdmissionFamily.Loop, 0, 0, false, []),
			family(OcamlControlAdmissionFamily.Throw, 0, 0, false, [])
		], []);
	}

	/** Rejects incomplete, contradictory, duplicated, or stale report data. */
	public static function requireSnapshot(snapshot:OcamlControlAdmissionSnapshot):Void {
		if (snapshot.id != "control-admission:" + Sha256.encode(snapshot.functionId).substr(0, 24)
			|| snapshot.functionId.length == 0
			|| snapshot.programRevision.length == 0
			|| snapshot.bodyRevision.length == 0
			|| snapshot.pipelineRevision.length == 0) {
			throw 'reflaxe.ocaml [ocaml-control-admission:invalid-binding]: snapshot "${snapshot.id}" has incomplete or stale function identity';
		}
		final expectedFamilies = [
			OcamlControlAdmissionFamily.Loop,
			OcamlControlAdmissionFamily.Return,
			OcamlControlAdmissionFamily.Throw
		];
		if (snapshot.families.length != expectedFamilies.length)
			throw 'reflaxe.ocaml [ocaml-control-admission:incomplete-families]: snapshot "${snapshot.id}" must report return, loop, and throw';
		for (index in 0...expectedFamilies.length) {
			final family = snapshot.families[index];
			if (family.family != expectedFamilies[index])
				throw 'reflaxe.ocaml [ocaml-control-admission:invalid-family-order]: snapshot "${snapshot.id}" has a missing, duplicate, or unsorted control family';
			requireFamily(snapshot.id, family);
		}
		final catchIds:Map<String, Bool> = [];
		var previousCatchId = "";
		for (entry in snapshot.catches) {
			if (entry.occurrenceId.length == 0
				|| catchIds.exists(entry.occurrenceId)
				|| (previousCatchId.length > 0 && Reflect.compare(previousCatchId, entry.occurrenceId) >= 0)) {
				throw 'reflaxe.ocaml [ocaml-control-admission:duplicate-catch]: snapshot "${snapshot.id}" has a duplicate or unsorted catch occurrence';
			}
			requireSource(entry.source, entry.occurrenceId);
			switch (entry.status) {
				case Admitted:
					if (entry.chainId == null || entry.chainId.length == 0 || entry.blockers.length != 0)
						throw 'reflaxe.ocaml [ocaml-control-admission:invalid-catch]: admitted catch "${entry.occurrenceId}" must name one chain and no blocker';
				case Blocked:
					if (entry.chainId != null || entry.blockers.length == 0)
						throw 'reflaxe.ocaml [ocaml-control-admission:invalid-catch]: blocked catch "${entry.occurrenceId}" must name blockers and no chain';
				case NotNeeded:
					throw 'reflaxe.ocaml [ocaml-control-admission:invalid-catch]: a recorded catch occurrence cannot be not-needed';
			}
			requireBlockers(entry.blockers, entry.status == OcamlControlAdmissionStatus.Blocked, entry.occurrenceId);
			catchIds.set(entry.occurrenceId, true);
			previousCatchId = entry.occurrenceId;
		}
		if (snapshot.revision != revisionFor(snapshot))
			throw 'reflaxe.ocaml [ocaml-control-admission:stale-revision]: snapshot "${snapshot.id}" revision does not match its reported facts';
	}

	/** Returns the exact family record or fails on a structurally incomplete snapshot. */
	public static function requireFamilyByKind(snapshot:OcamlControlAdmissionSnapshot, kind:OcamlControlAdmissionFamily):OcamlControlFamilyAdmission {
		for (family in snapshot.families)
			if (family.family == kind)
				return copyFamily(family);
		throw 'reflaxe.ocaml [ocaml-control-admission:missing-family]: snapshot "${snapshot.id}" has no $kind family';
	}

	/** Returns a detached copy suitable for report publication. */
	public static function copySnapshot(snapshot:OcamlControlAdmissionSnapshot):OcamlControlAdmissionSnapshot {
		return {
			id: snapshot.id,
			functionId: snapshot.functionId,
			programRevision: snapshot.programRevision,
			bodyRevision: snapshot.bodyRevision,
			pipelineRevision: snapshot.pipelineRevision,
			families: snapshot.families.map(copyFamily),
			catches: snapshot.catches.map(copyCatch),
			revision: snapshot.revision
		};
	}

	static function requireFamily(snapshotId:String, family:OcamlControlFamilyAdmission):Void {
		if (family.occurrenceCount < 0 || family.decisionCount < 0 || family.decisionCount > family.occurrenceCount)
			throw 'reflaxe.ocaml [ocaml-control-admission:invalid-count]: snapshot "$snapshotId" has impossible ${family.family} counts';
		switch (family.status) {
			case NotNeeded:
				if (family.occurrenceCount != 0 || family.decisionCount != 0 || family.blockers.length != 0)
					throw 'reflaxe.ocaml [ocaml-control-admission:invalid-family]: not-needed ${family.family} must have no occurrence, decision, or blocker';
			case Admitted:
				if (family.occurrenceCount == 0 || family.decisionCount != family.occurrenceCount || family.blockers.length != 0)
					throw 'reflaxe.ocaml [ocaml-control-admission:invalid-family]: admitted ${family.family} must explain every occurrence with one decision';
			case Blocked:
				if (family.occurrenceCount == 0 || family.decisionCount != 0 || family.blockers.length == 0)
					throw 'reflaxe.ocaml [ocaml-control-admission:invalid-family]: blocked ${family.family} must have occurrences, no published decisions, and at least one blocker';
		}
		requireBlockers(family.blockers, family.status == OcamlControlAdmissionStatus.Blocked, (family.family : String));
	}

	static function requireBlockers(blockers:Array<OcamlControlAdmissionBlocker>, required:Bool, owner:String):Void {
		if (required != (blockers.length > 0))
			throw 'reflaxe.ocaml [ocaml-control-admission:invalid-blockers]: "$owner" blocker inventory contradicts its status';
		final ids:Map<String, Bool> = [];
		var previousKey = "";
		for (blocker in blockers) {
			final key = blockerKey(blocker);
			if (blocker.code.length == 0
				|| blocker.occurrenceId.length == 0
				|| ids.exists(key)
				|| (previousKey.length > 0 && Reflect.compare(previousKey, key) >= 0)
				|| blocker.message != blockerMessage(blocker.code, blocker.semanticTypeId)) {
				throw 'reflaxe.ocaml [ocaml-control-admission:invalid-blocker]: "$owner" contains an unknown, duplicate, unsorted, or edited blocker';
			}
			requireSource(blocker.source, blocker.occurrenceId);
			ids.set(key, true);
			previousKey = key;
		}
	}

	static function requireSource(source:OcamlLoweredSourceSpan, owner:String):Void {
		if (source.file.length == 0 || source.min < 0 || source.max < source.min)
			throw 'reflaxe.ocaml [ocaml-control-admission:invalid-source]: "$owner" has an invalid source span';
	}

	static function blockerMessage(code:String, semanticTypeId:Null<String>):String {
		final semantic = semanticTypeId == null ? "the observed value" : semanticTypeId;
		return switch (code) {
			case "return-boundary-unrepresented": 'The function result boundary has no checked carrier for $semantic, so nested returns remain on the older result path.';
			case "return-payload-missing": "A nested payloadless return does not belong to an admitted effect-only Void boundary.";
			case "return-value-unrepresented": 'The nested return value $semantic has no checked control-channel representation.';
			case "return-conversion-unrepresented": 'The nested return value $semantic cannot cross the checked function-result boundary.';
			case "loop-target-missing": "The typed break or continue has no lexical loop target in the current function plan.";
			case "throw-value-unrepresented": 'The thrown value $semantic has no checked exception-channel representation.';
			case "throw-conversion-unrepresented": 'The thrown value $semantic has no checked conversion into the exception channel.';
			case "throw-proof-unrepresented": 'The thrown value $semantic has no proof for the selected exception-channel representation.';
			case "catch-chain-empty": "The typed try expression has no source catch clause to seal.";
			case "catch-clause-unrepresented": 'The catch type $semantic has no checked payload-matching representation.';
			case _:
				throw 'reflaxe.ocaml [ocaml-control-admission:unknown-blocker]: unsupported blocker code "$code"';
		};
	}

	static function revisionFor(snapshot:OcamlControlAdmissionSnapshot):String {
		return revisionForValues(snapshot.id, snapshot.functionId, snapshot.programRevision, snapshot.bodyRevision, snapshot.pipelineRevision,
			snapshot.families, snapshot.catches);
	}

	static function revisionForValues(id:String, functionId:String, programRevision:String, bodyRevision:String, pipelineRevision:String,
			families:Array<OcamlControlFamilyAdmission>, catches:Array<OcamlControlCatchAdmission>):String {
		return "sha256:"
			+ Sha256.encode([MODEL, id, functionId, programRevision, bodyRevision, pipelineRevision].concat(families.map(familyFingerprint))
				.concat(catches.map(catchFingerprint))
				.join("\n"));
	}

	static function familyFingerprint(family:OcamlControlFamilyAdmission):String {
		return [
			(family.family : String),
			(family.status : String),
			Std.string(family.occurrenceCount),
			Std.string(family.decisionCount)
		].concat(family.blockers.map(blockerFingerprint)).join("|");
	}

	static function catchFingerprint(entry:OcamlControlCatchAdmission):String {
		return [
			entry.occurrenceId,
			sourceKey(entry.source),
			(entry.status : String),
			entry.chainId ?? ""
		].concat(entry.blockers.map(blockerFingerprint)).join("|");
	}

	static function blockerFingerprint(blocker:OcamlControlAdmissionBlocker):String {
		return [
			blocker.code,
			blocker.occurrenceId,
			sourceKey(blocker.source),
			blocker.semanticTypeId ?? "",
			blocker.message
		].join("|");
	}

	static function blockerKey(blocker:OcamlControlAdmissionBlocker):String {
		return blocker.occurrenceId + "|" + blocker.code + "|" + (blocker.semanticTypeId ?? "");
	}

	static function copyFamily(family:OcamlControlFamilyAdmission):OcamlControlFamilyAdmission {
		final blockers = family.blockers.map(copyBlocker);
		blockers.sort((left, right) -> Reflect.compare(blockerKey(left), blockerKey(right)));
		return {
			family: family.family,
			status: family.status,
			occurrenceCount: family.occurrenceCount,
			decisionCount: family.decisionCount,
			blockers: blockers
		};
	}

	static function copyCatch(entry:OcamlControlCatchAdmission):OcamlControlCatchAdmission {
		final blockers = entry.blockers.map(copyBlocker);
		blockers.sort((left, right) -> Reflect.compare(blockerKey(left), blockerKey(right)));
		return {
			occurrenceId: entry.occurrenceId,
			source: copySource(entry.source),
			status: entry.status,
			chainId: entry.chainId,
			blockers: blockers
		};
	}

	static function copyBlocker(blocker:OcamlControlAdmissionBlocker):OcamlControlAdmissionBlocker {
		return {
			code: blocker.code,
			occurrenceId: blocker.occurrenceId,
			source: copySource(blocker.source),
			semanticTypeId: blocker.semanticTypeId,
			message: blocker.message
		};
	}

	static function copySource(source:OcamlLoweredSourceSpan):OcamlLoweredSourceSpan {
		return {file: source.file, min: source.min, max: source.max};
	}

	static function sourceKey(source:OcamlLoweredSourceSpan):String {
		return source.file + ":" + source.min + ":" + source.max;
	}
}
#end
