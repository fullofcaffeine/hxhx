package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime || eval)
import haxe.crypto.Sha256;
#if macro
import haxe.ds.ObjectMap;
import haxe.macro.Type;
import haxe.macro.Type.ClassField;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypeTools;
import haxe.macro.TypedExprTools;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallKind;
#end
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.lowered.OcamlStructuralIteratorCallModel.OcamlStructuralIteratorCallContract;
import reflaxe.ocaml.lowered.OcamlStructuralIteratorCallModel.OcamlStructuralIteratorCallTarget;

/** The caller-visible meaning selected for one structural `next` or `hasNext`. */
enum abstract OcamlStructuralFieldOperation(String) from String to String {
	/** Read an ordinary stored field from the portable anonymous-object carrier. */
	final ReadStoredField = "read-stored-field";

	/** Replace an ordinary stored field and return the assigned Haxe value. */
	final WriteStoredField = "write-stored-field";

	/** Capture a genuine structural Iterator method as a `Void -> T` value. */
	final CaptureIteratorMethod = "capture-iterator-method";
}

/** How a stored `HxAnon` value becomes the field's typed Haxe result. */
enum abstract OcamlStructuralFieldLoadConversion(String) from String to String {
	final ObjObj = "obj-obj";
	final UnboxBool = "unbox-bool";
}

/** How an assigned Haxe value enters the universal `HxAnon` field slot. */
enum abstract OcamlStructuralFieldStoreConversion(String) from String to String {
	final ObjRepr = "obj-repr";
	final BoxBool = "box-bool";
}

/**
	One immutable decision for a structural field whose name overlaps Iterator.

	The decision makes the important distinction before OCaml syntax: `q.next`
	can be an ordinary linked-node value, while `iterator.next` can be a captured
	Iterator method. The renderer receives the selected runtime operation and is
	not allowed to infer either meaning from the spelling of the field.
**/
typedef OcamlStructuralFieldDecision = {
	final id:String;
	final occurrenceOrdinal:Int;
	final source:OcamlLoweredSourceSpan;
	final operation:OcamlStructuralFieldOperation;
	final fieldName:String;
	final receiverSemanticTypeId:String;
	final receiverCarrierTypeId:String;
	final fieldSemanticTypeId:String;
	final resultSemanticTypeId:String;
	final loadConversion:Null<OcamlStructuralFieldLoadConversion>;
	final storeConversion:Null<OcamlStructuralFieldStoreConversion>;
	final runtimeModule:String;
	final runtimeOperation:String;
	final runtimeRequirementIds:Array<String>;
	final evaluationSchedule:Array<String>;
	final iteratorTarget:Null<OcamlStructuralIteratorCallTarget>;
	final proofId:String;
	final proofClaim:String;
	final functionId:String;
	final programRevision:String;
	final bodyRevision:String;
	final pipelineRevision:String;
}

/** Pure identity and validation rules shared by planning, syntax, and reports. */
class OcamlStructuralFieldContract {
	public static inline final MODEL = "typed-structural-field-overlap-v1";
	public static inline final HAXE_ANON_CAPABILITY = "haxe-structural-field";
	public static inline final HAXE_ITERATOR_CAPABILITY = "haxe-iterator";
	public static inline final STORED_PROOF_ID = "structural-stored-field-v1";
	public static inline final ITERATOR_PROOF_ID = "structural-iterator-method-value-v1";

	public static inline final STORED_PROOF_CLAIM = "The final typed FAnon occurrence names an ordinary stored next or hasNext field, not a complete structural Iterator method. The portable carrier is one HxAnon object. Reads evaluate the receiver once and recover the stored field value. Writes evaluate the receiver before the assigned value, replace that exact field, and return the assigned Haxe value.";
	public static inline final ITERATOR_PROOF_CLAIM = "The final typed field occurrence captures hasNext or next from a complete structural Iterator value. The target evaluates the receiver once and returns a zero-argument closure over the exact HxIterator operation. Immediate invocation remains owned by the separate structural Iterator call plan.";

	/** Returns whether this bounded model owns a potentially ambiguous field. */
	public static function ownsFieldName(name:String):Bool {
		return name == "next" || name == "hasNext";
	}

	/** Returns the one runtime requirement selected by a structural field decision. */
	public static function runtimeRequirementId(decisionId:String, operation:OcamlStructuralFieldOperation):String {
		return decisionId + ":runtime:" + (operation == CaptureIteratorMethod ? HAXE_ITERATOR_CAPABILITY : HAXE_ANON_CAPABILITY);
	}

	/** Builds the content identity after every behavior-bearing field is known. */
	public static function decisionId(decision:OcamlStructuralFieldDecision):String {
		return "structural-field:" + Sha256.encode(fingerprint(copy(decision, ""))).substr(0, 24);
	}

	/** Rejects missing, contradictory, or stale plain decision data. */
	public static function require(decision:OcamlStructuralFieldDecision):Void {
		if (decision == null)
			throw "reflaxe.ocaml [ocaml-structural-field:missing]: structural field decision is missing";
		if (!ownsFieldName(decision.fieldName)
			|| decision.occurrenceOrdinal < 0
			|| decision.source.file.length == 0
			|| decision.source.min < 0
			|| decision.source.max < decision.source.min
			|| decision.receiverSemanticTypeId.length == 0
			|| decision.receiverCarrierTypeId.length == 0
			|| decision.fieldSemanticTypeId.length == 0
			|| decision.resultSemanticTypeId.length == 0
			|| decision.functionId.length == 0
			|| decision.programRevision.length == 0
			|| decision.bodyRevision.length == 0
			|| decision.pipelineRevision.length == 0) {
			throw 'reflaxe.ocaml [ocaml-structural-field:invalid]: structural field decision "${decision.id}" has incomplete source, type, or revision facts';
		}

		switch (decision.operation) {
			case ReadStoredField:
				requireStored(decision, "get", ["materialize-receiver", "read-field"], true);
			case WriteStoredField:
				requireStored(decision, "set", ["materialize-receiver", "materialize-value", "write-field"], false);
			case CaptureIteratorMethod:
				final target = decision.iteratorTarget;
				if (target == null)
					throw 'reflaxe.ocaml [ocaml-structural-field:invalid-iterator]: Iterator method decision "${decision.id}" has no target';
				OcamlStructuralIteratorCallContract.require(target);
				if (decision.receiverSemanticTypeId != target.receiverSemanticTypeId
					|| decision.receiverCarrierTypeId != OcamlStructuralIteratorCallContract.RECEIVER_CARRIER
					|| decision.fieldName != OcamlStructuralIteratorCallContract.sourceFieldName(target.operation)
					|| decision.resultSemanticTypeId != decision.fieldSemanticTypeId
					|| decision.runtimeModule != target.runtimeModule
					|| decision.runtimeOperation != target.runtimeFunction
					|| target.proofId != OcamlStructuralIteratorCallContract.METHOD_VALUE_PROOF_ID
					|| target.proofClaim != OcamlStructuralIteratorCallContract.METHOD_VALUE_PROOF_CLAIM
					|| decision.loadConversion != null
					|| decision.storeConversion != null
					|| decision.evaluationSchedule.join(",") != "materialize-receiver,capture-method"
					|| decision.proofId != ITERATOR_PROOF_ID
					|| decision.proofClaim != ITERATOR_PROOF_CLAIM) {
					throw 'reflaxe.ocaml [ocaml-structural-field:invalid-iterator]: Iterator method decision "${decision.id}" disagrees with its target';
				}
		}
		final expectedRequirement = runtimeRequirementId(decision.id, decision.operation);
		if (decision.runtimeRequirementIds.length != 1 || decision.runtimeRequirementIds[0] != expectedRequirement)
			throw 'reflaxe.ocaml [ocaml-structural-field:invalid-runtime]: structural field decision "${decision.id}" does not own its exact runtime requirement';
		if (decision.id != decisionId(decision))
			throw 'reflaxe.ocaml [ocaml-structural-field:stale]: structural field decision "${decision.id}" does not match its canonical facts';
	}

	static function requireStored(decision:OcamlStructuralFieldDecision, operation:String, schedule:Array<String>, read:Bool):Void {
		final boolField = decision.fieldSemanticTypeId == "Bool";
		if (decision.receiverCarrierTypeId != "Obj.t"
			|| decision.resultSemanticTypeId != decision.fieldSemanticTypeId
			|| decision.runtimeModule != "HxAnon"
			|| decision.runtimeOperation != operation
			|| decision.evaluationSchedule.join(",") != schedule.join(",")
			|| decision.iteratorTarget != null
			|| decision.proofId != STORED_PROOF_ID
			|| decision.proofClaim != STORED_PROOF_CLAIM
			|| (read && decision.storeConversion != null)
			|| (!read && decision.loadConversion != null)
			|| (read && decision.loadConversion != (boolField ? UnboxBool : ObjObj))
			|| (!read && decision.storeConversion != (boolField ? BoxBool : ObjRepr))) {
			throw 'reflaxe.ocaml [ocaml-structural-field:invalid-stored]: stored field decision "${decision.id}" disagrees with its HxAnon operation';
		}
	}

	/** Returns a detached copy suitable for reports and sealed-plan storage. */
	public static function copy(decision:OcamlStructuralFieldDecision, ?id:String):OcamlStructuralFieldDecision {
		return {
			id: id ?? decision.id,
			occurrenceOrdinal: decision.occurrenceOrdinal,
			source: {file: decision.source.file, min: decision.source.min, max: decision.source.max},
			operation: decision.operation,
			fieldName: decision.fieldName,
			receiverSemanticTypeId: decision.receiverSemanticTypeId,
			receiverCarrierTypeId: decision.receiverCarrierTypeId,
			fieldSemanticTypeId: decision.fieldSemanticTypeId,
			resultSemanticTypeId: decision.resultSemanticTypeId,
			loadConversion: decision.loadConversion,
			storeConversion: decision.storeConversion,
			runtimeModule: decision.runtimeModule,
			runtimeOperation: decision.runtimeOperation,
			runtimeRequirementIds: decision.runtimeRequirementIds.copy(),
			evaluationSchedule: decision.evaluationSchedule.copy(),
			iteratorTarget: decision.iteratorTarget == null ? null : OcamlStructuralIteratorCallContract.copy(decision.iteratorTarget),
			proofId: decision.proofId,
			proofClaim: decision.proofClaim,
			functionId: decision.functionId,
			programRevision: decision.programRevision,
			bodyRevision: decision.bodyRevision,
			pipelineRevision: decision.pipelineRevision
		};
	}

	/** Canonical text used by decision IDs and complete-plan revisions. */
	public static function fingerprint(decision:OcamlStructuralFieldDecision):String {
		return [
			Std.string(decision.occurrenceOrdinal),
			decision.source.file,
			Std.string(decision.source.min),
			Std.string(decision.source.max),
			(decision.operation : String),
			decision.fieldName,
			decision.receiverSemanticTypeId,
			decision.receiverCarrierTypeId,
			decision.fieldSemanticTypeId,
			decision.resultSemanticTypeId,
			decision.loadConversion == null ? "" : (decision.loadConversion : String),
			decision.storeConversion == null ? "" : (decision.storeConversion : String),
			decision.runtimeModule + "." + decision.runtimeOperation,
			decision.evaluationSchedule.join(","),
			decision.iteratorTarget == null ? "" : OcamlStructuralIteratorCallContract.fingerprint(decision.iteratorTarget),
			decision.proofId,
			decision.proofClaim,
			decision.functionId,
			decision.programRevision,
			decision.bodyRevision,
			decision.pipelineRevision
		].join("|");
	}
}

#if macro
private typedef OcamlStructuralFieldOccurrence = {
	final expression:TypedExpr;
	final decisionId:String;
}

/** Request-local lookup from final typed occurrences to immutable field decisions. */
class OcamlStructuralFieldPlan {
	final decisionsById:Map<String, OcamlStructuralFieldDecision> = [];
	final decisionIdByExpression:ObjectMap<TypedExpr, String> = new ObjectMap();
	final ordered:Array<OcamlStructuralFieldDecision>;

	public final revision:String;

	public function new(decisions:Array<OcamlStructuralFieldDecision>, ?occurrences:Array<OcamlStructuralFieldOccurrence>) {
		ordered = decisions.map(decision -> OcamlStructuralFieldContract.copy(decision));
		ordered.sort((left, right) -> Reflect.compare(left.id, right.id));
		for (decision in ordered) {
			OcamlStructuralFieldContract.require(decision);
			if (decisionsById.exists(decision.id))
				throw 'reflaxe.ocaml [ocaml-structural-field:duplicate]: decision "${decision.id}" appears more than once';
			decisionsById.set(decision.id, OcamlStructuralFieldContract.copy(decision));
		}
		final seen:Map<String, Bool> = [];
		for (occurrence in occurrences ?? []) {
			if (decisionIdByExpression.exists(occurrence.expression)
				|| seen.exists(occurrence.decisionId)
				|| !decisionsById.exists(occurrence.decisionId))
				throw 'reflaxe.ocaml [ocaml-structural-field:occurrence]: structural field occurrence has a duplicate or missing decision "${occurrence.decisionId}"';
			decisionIdByExpression.set(occurrence.expression, occurrence.decisionId);
			seen.set(occurrence.decisionId, true);
		}
		if (occurrences != null)
			for (decision in ordered)
				if (!seen.exists(decision.id))
					throw 'reflaxe.ocaml [ocaml-structural-field:occurrence]: decision "${decision.id}" has no exact typed occurrence';
		revision = "sha256:" + Sha256.encode(ordered.map(OcamlStructuralFieldContract.fingerprint).join("\n"));
	}

	/** Returns and rechecks the decision for one exact final typed expression. */
	public function decisionFor(expression:TypedExpr):Null<OcamlStructuralFieldDecision> {
		final id = decisionIdByExpression.get(expression);
		if (id == null)
			return null;
		final decision = decisionsById.get(id);
		if (decision == null)
			throw 'reflaxe.ocaml [ocaml-structural-field:stale]: decision "$id" is missing from its sealed plan';
		final mismatch = OcamlStructuralFieldPlanner.mismatchReason(decision, expression);
		if (mismatch != null)
			throw 'reflaxe.ocaml [ocaml-structural-field:stale]: decision "$id" no longer matches its final typed occurrence at ${decision.source.file}:${decision.source.min}-${decision.source.max}: $mismatch';
		return OcamlStructuralFieldContract.copy(decision);
	}

	/** Revalidates every decision against the function revision that owns it. */
	public function requirePlanBinding(binding:OcamlFunctionPlanBinding):Void {
		for (decision in ordered)
			if (decision.functionId != binding.functionId
				|| decision.programRevision != binding.programRevision
				|| decision.bodyRevision != binding.bodyRevision
				|| decision.pipelineRevision != binding.pipelineRevision) {
				throw 'reflaxe.ocaml [ocaml-structural-field:stale]: decision "${decision.id}" does not belong to ${binding.functionId}/${binding.bodyRevision}/${binding.pipelineRevision}';
			}
	}

	/** Returns report-safe copies in stable identity order. */
	public function decisions():Array<OcamlStructuralFieldDecision> {
		return ordered.map(decision -> OcamlStructuralFieldContract.copy(decision));
	}
}

/** Selects overlapping structural fields from one exact final typed body. */
class OcamlStructuralFieldPlanner {
	final binding:OcamlFunctionPlanBinding;
	final calls:OcamlCallPlan;
	final anonymousStructures:OcamlAnonymousStructurePlan;
	final representations:OcamlRepresentationRegistry;
	var ordinal = 0;

	public function new(binding:OcamlFunctionPlanBinding, calls:OcamlCallPlan, anonymousStructures:OcamlAnonymousStructurePlan,
			representations:OcamlRepresentationRegistry) {
		this.binding = binding;
		this.calls = calls;
		this.anonymousStructures = anonymousStructures;
		this.representations = representations;
	}

	/** Plans stored fields and Iterator method values without duplicating direct calls. */
	public function plan(root:TypedExpr):OcamlStructuralFieldPlan {
		final decisions:Array<OcamlStructuralFieldDecision> = [];
		final occurrences:Array<OcamlStructuralFieldOccurrence> = [];

		function record(expression:TypedExpr, decision:Null<OcamlStructuralFieldDecision>):Void {
			if (decision == null)
				return;
			if (anonymousStructures.operationFor(expression, representations) != null)
				return;
			decisions.push(decision);
			occurrences.push({expression: expression, decisionId: decision.id});
		}

		function visit(expression:TypedExpr):Void {
			final currentOrdinal = ordinal++;
			switch (expression.expr) {
				case TCall({expr: TField(receiver, _)}, arguments):
					final call = calls.decisionFor(expression);
					if (call != null && call.kind == OcamlCallKind.StructuralIteratorMethod) {
						visit(receiver);
						for (argument in arguments)
							visit(argument);
					} else {
						TypedExprTools.iter(expression, visit);
					}
				case TBinop(OpAssign, {expr: TField(receiver, FAnon(fieldRef))}, value):
					record(expression, selectWrite(expression, receiver, fieldRef.get(), currentOrdinal));
					visit(receiver);
					visit(value);
				case TField(receiver, FAnon(fieldRef)):
					record(expression, selectRead(expression, receiver, fieldRef.get(), currentOrdinal, true));
					visit(receiver);
				case TField(receiver, FClosure(null, fieldRef)):
					record(expression, selectRead(expression, receiver, fieldRef.get(), currentOrdinal, false));
					visit(receiver);
				case _:
					TypedExprTools.iter(expression, visit);
			}
		}

		visit(root);
		return new OcamlStructuralFieldPlan(decisions, occurrences);
	}

	/** Returns whether syntax must demand a decision for this expression. */
	public static function isCandidate(expression:TypedExpr):Bool {
		return switch (expression.expr) {
			case TField(_, FAnon(fieldRef)):
				OcamlStructuralFieldContract.ownsFieldName(fieldRef.get().name);
			case TField(receiver, FClosure(null, fieldRef)):
				OcamlStructuralIteratorCallContract.selectMethodValue(receiver, fieldRef.get()) != null;
			case TBinop(OpAssign, {expr: TField(_, FAnon(fieldRef))}, _):
				OcamlStructuralFieldContract.ownsFieldName(fieldRef.get().name);
			case _:
				false;
		}
	}

	/** Rechecks plain decision facts against their request-local typed occurrence. */
	public static function matches(decision:OcamlStructuralFieldDecision, expression:TypedExpr):Bool {
		return mismatchReason(decision, expression) == null;
	}

	/**
		Explains why a previously typed field decision can no longer be consumed.

		A non-null result means some behavior-bearing typed fact changed between
		planning and code generation. Naming the exact fact keeps this fail-closed
		check useful: a maintainer sees whether the source occurrence, receiver,
		field type, result type, or Iterator classification drifted instead of
		being tempted to remove the check merely to let generation continue.
	**/
	public static function mismatchReason(decision:OcamlStructuralFieldDecision, expression:TypedExpr):Null<String> {
		final source = OcamlLoweredOrigin.sourceSpan(expression.pos);
		if (source.file != decision.source.file || source.min != decision.source.min || source.max != decision.source.max)
			return 'source expected=${decision.source.file}:${decision.source.min}-${decision.source.max} actual=${source.file}:${source.min}-${source.max}';
		return switch (expression.expr) {
			case TField(receiver, FAnon(fieldRef)):
				readMismatch(decision, receiver, fieldRef.get(), expression.t, true);
			case TField(receiver, FClosure(null, fieldRef)):
				readMismatch(decision, receiver, fieldRef.get(), expression.t, false);
			case TBinop(OpAssign, {expr: TField(receiver, FAnon(fieldRef))}, _):
				writeMismatch(decision, receiver, fieldRef.get(), expression.t);
			case _:
				"expression shape is no longer an owned structural field read, method capture, or write";
		}
	}

	function selectRead(expression:TypedExpr, receiver:TypedExpr, field:ClassField, occurrenceOrdinal:Int,
			storedFieldAllowed:Bool):Null<OcamlStructuralFieldDecision> {
		if (!OcamlStructuralFieldContract.ownsFieldName(field.name))
			return null;
		final iteratorTarget = OcamlStructuralIteratorCallContract.selectMethodValue(receiver, field);
		if (iteratorTarget == null && !storedFieldAllowed)
			return null;
		final fieldSemanticTypeId = TypeTools.toString(field.type);
		final operation = iteratorTarget == null ? ReadStoredField : CaptureIteratorMethod;
		final decision = baseDecision(expression, receiver, field, occurrenceOrdinal, operation, fieldSemanticTypeId);
		if (iteratorTarget == null) {
			decision.receiverCarrierTypeId = "Obj.t";
			decision.loadConversion = fieldSemanticTypeId == "Bool" ? UnboxBool : ObjObj;
			decision.runtimeModule = "HxAnon";
			decision.runtimeOperation = "get";
			decision.evaluationSchedule = ["materialize-receiver", "read-field"];
			decision.proofId = OcamlStructuralFieldContract.STORED_PROOF_ID;
			decision.proofClaim = OcamlStructuralFieldContract.STORED_PROOF_CLAIM;
		} else {
			decision.receiverCarrierTypeId = iteratorTarget.receiverCarrierTypeId;
			decision.runtimeModule = iteratorTarget.runtimeModule;
			decision.runtimeOperation = iteratorTarget.runtimeFunction;
			decision.evaluationSchedule = ["materialize-receiver", "capture-method"];
			decision.iteratorTarget = iteratorTarget;
			decision.proofId = OcamlStructuralFieldContract.ITERATOR_PROOF_ID;
			decision.proofClaim = OcamlStructuralFieldContract.ITERATOR_PROOF_CLAIM;
		}
		return finalize(decision);
	}

	function selectWrite(expression:TypedExpr, receiver:TypedExpr, field:ClassField, occurrenceOrdinal:Int):Null<OcamlStructuralFieldDecision> {
		if (!OcamlStructuralFieldContract.ownsFieldName(field.name))
			return null;
		final fieldSemanticTypeId = TypeTools.toString(field.type);
		final decision = baseDecision(expression, receiver, field, occurrenceOrdinal, WriteStoredField, fieldSemanticTypeId);
		decision.receiverCarrierTypeId = "Obj.t";
		decision.storeConversion = fieldSemanticTypeId == "Bool" ? BoxBool : ObjRepr;
		decision.runtimeModule = "HxAnon";
		decision.runtimeOperation = "set";
		decision.evaluationSchedule = ["materialize-receiver", "materialize-value", "write-field"];
		decision.proofId = OcamlStructuralFieldContract.STORED_PROOF_ID;
		decision.proofClaim = OcamlStructuralFieldContract.STORED_PROOF_CLAIM;
		return finalize(decision);
	}

	function baseDecision(expression:TypedExpr, receiver:TypedExpr, field:ClassField, occurrenceOrdinal:Int, operation:OcamlStructuralFieldOperation,
			resultSemanticTypeId:String):Dynamic {
		return {
			id: "",
			occurrenceOrdinal: occurrenceOrdinal,
			source: OcamlLoweredOrigin.sourceSpan(expression.pos),
			operation: operation,
			fieldName: field.name,
			receiverSemanticTypeId: TypeTools.toString(receiver.t),
			receiverCarrierTypeId: "",
			fieldSemanticTypeId: TypeTools.toString(field.type),
			resultSemanticTypeId: resultSemanticTypeId,
			loadConversion: null,
			storeConversion: null,
			runtimeModule: "",
			runtimeOperation: "",
			runtimeRequirementIds: [],
			evaluationSchedule: [],
			iteratorTarget: null,
			proofId: "",
			proofClaim: "",
			functionId: binding.functionId,
			programRevision: binding.programRevision,
			bodyRevision: binding.bodyRevision,
			pipelineRevision: binding.pipelineRevision
		};
	}

	function finalize(raw:Dynamic):OcamlStructuralFieldDecision {
		final provisional:OcamlStructuralFieldDecision = cast raw;
		final id = OcamlStructuralFieldContract.decisionId(provisional);
		Reflect.setField(raw, "id", id);
		Reflect.setField(raw, "runtimeRequirementIds", [OcamlStructuralFieldContract.runtimeRequirementId(id, provisional.operation)]);
		final decision:OcamlStructuralFieldDecision = cast raw;
		OcamlStructuralFieldContract.require(decision);
		return decision;
	}

	static function readMismatch(decision:OcamlStructuralFieldDecision, receiver:TypedExpr, field:ClassField, resultType:Type,
			storedFieldAllowed:Bool):Null<String> {
		if (decision.operation == WriteStoredField)
			return "operation changed from a write to a read";
		if (decision.fieldName != field.name)
			return 'field name expected=${decision.fieldName} actual=${field.name}';
		final receiverType = TypeTools.toString(receiver.t);
		if (decision.receiverSemanticTypeId != receiverType)
			return 'receiver type expected=${decision.receiverSemanticTypeId} actual=$receiverType';
		final fieldType = TypeTools.toString(field.type);
		if (decision.fieldSemanticTypeId != fieldType)
			return 'field type expected=${decision.fieldSemanticTypeId} actual=$fieldType';
		final actualResultType = TypeTools.toString(resultType);
		if (decision.resultSemanticTypeId != actualResultType)
			return 'result type expected=${decision.resultSemanticTypeId} actual=$actualResultType';
		final iteratorTarget = OcamlStructuralIteratorCallContract.selectMethodValue(receiver, field);
		if (decision.operation == CaptureIteratorMethod) {
			if (iteratorTarget == null || decision.iteratorTarget == null)
				return "Iterator method ownership is no longer present";
			if (OcamlStructuralIteratorCallContract.fingerprint(iteratorTarget) != OcamlStructuralIteratorCallContract.fingerprint(decision.iteratorTarget))
				return "Iterator method target facts changed";
			return null;
		}
		if (!storedFieldAllowed)
			return "the final field shape no longer permits a stored anonymous field";
		return iteratorTarget == null ? null : "the stored field is now classified as an Iterator method";
	}

	static function writeMismatch(decision:OcamlStructuralFieldDecision, receiver:TypedExpr, field:ClassField, resultType:Type):Null<String> {
		if (decision.operation != WriteStoredField)
			return "operation changed from a read or method capture to a write";
		if (decision.fieldName != field.name)
			return 'field name expected=${decision.fieldName} actual=${field.name}';
		final receiverType = TypeTools.toString(receiver.t);
		if (decision.receiverSemanticTypeId != receiverType)
			return 'receiver type expected=${decision.receiverSemanticTypeId} actual=$receiverType';
		final fieldType = TypeTools.toString(field.type);
		if (decision.fieldSemanticTypeId != fieldType)
			return 'field type expected=${decision.fieldSemanticTypeId} actual=$fieldType';
		final actualResultType = TypeTools.toString(resultType);
		return decision.resultSemanticTypeId == actualResultType ? null : 'result type expected=${decision.resultSemanticTypeId} actual=$actualResultType';
	}
}
#end

#end
