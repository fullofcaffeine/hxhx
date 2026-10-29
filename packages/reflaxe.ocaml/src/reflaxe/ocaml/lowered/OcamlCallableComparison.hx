package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime || eval)
import haxe.crypto.Sha256;
import reflaxe.ocaml.lowered.OcamlCallableViewContract;
import reflaxe.ocaml.lowered.OcamlCallableViewContract.OcamlCallableViewInput;
import reflaxe.ocaml.lowered.OcamlCallableViewRepresentation;
import reflaxe.ocaml.lowered.OcamlCallableViewRepresentation.OcamlCallableViewDescriptor;
import reflaxe.ocaml.lowered.OcamlCallableValueOperation;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;

/** An equality operand keeps its actual producer; it does not acquire synthetic local storage. */
typedef OcamlCallableComparisonOperand = {
	final source:OcamlLoweredSourceSpan;
	final input:OcamlCallableViewInput;
	final layout:OcamlCallableViewDescriptor;
};

/** One final-body comparison evaluates two producers in order and compares their original identities. */
typedef OcamlCallableComparisonDecision = {
	final id:String;
	final revision:String;
	final binding:OcamlFunctionPlanBinding;
	final source:OcamlLoweredSourceSpan;
	final notEqual:Bool;
	final left:OcamlCallableComparisonOperand;
	final right:OcamlCallableComparisonOperand;
};

/** Select the occurrence before emission; later readers cannot change its inputs or operation. */
function seal(binding:OcamlFunctionPlanBinding, source:OcamlLoweredSourceSpan, notEqual:Bool, left:OcamlCallableComparisonOperand,
		right:OcamlCallableComparisonOperand):OcamlCallableComparisonDecision {
	final id = occurrenceId(binding, source, notEqual);
	final decision:OcamlCallableComparisonDecision = {
		id: id,
		revision: fingerprint(id, left, right),
		binding: {
			functionId: binding.functionId,
			programRevision: binding.programRevision,
			bodyRevision: binding.bodyRevision,
			pipelineRevision: binding.pipelineRevision
		},
		source: copySource(source),
		notEqual: notEqual,
		left: copyOperand(left),
		right: copyOperand(right)
	};
	requireDecision(decision);
	return decision;
}

/** Reject stale source facts before syntax or report export consumes them. */
function requireDecision(decision:OcamlCallableComparisonDecision):Void {
	if (decision.source.file.length == 0 || decision.source.min < 0 || decision.source.max < decision.source.min)
		throw "reflaxe.ocaml [callback-comparison:invalid-source]: equality lost its source occurrence";
	if (decision.id != occurrenceId(decision.binding, decision.source, decision.notEqual)
		|| decision.revision != fingerprint(decision.id, decision.left, decision.right))
		throw "reflaxe.ocaml [callback-comparison:stale-decision]: callback comparison changed its source or operation";
	for (operand in [decision.left, decision.right]) {
		validate(operand.layout);
		// Alias substitution can retain the initializer's earlier source position.
		// The final-body binding and exact operand join prove ownership; textual
		// containment in the comparison would reject that valid transformation.
		switch (operand.input) {
			case ExistingView(reference):
				requireReference(reference, operand.layout);
			case CallResult(source):
				if (sourceKey(source) != sourceKey(operand.source))
					throw "reflaxe.ocaml [callback-comparison:foreign-call]: operand lost its exact call result";
			case DeclaredOrigin(declaration):
				validate(declaration.layout);
				if (declaration.layout.revision != operand.layout.revision)
					throw "reflaxe.ocaml [callback-comparison:foreign-declaration]: operand lost its published layout";
			case RawOrigin(_):
		}
	}
	requireOperation(uncheckedOperation(decision, true));
	requireOperation(uncheckedOperation(decision, false));
}

/** Copy after validation so a changed shape cannot obtain a newly valid fingerprint. */
function copy(decision:OcamlCallableComparisonDecision):OcamlCallableComparisonDecision {
	requireDecision(decision);
	return seal(decision.binding, decision.source, decision.notEqual, decision.left, decision.right);
}

/** Reuse requires the same function, final body, program and target pipeline. */
function requireBinding(decision:OcamlCallableComparisonDecision, binding:OcamlFunctionPlanBinding):Void {
	requireDecision(decision);
	if (decision.binding.functionId != binding.functionId
		|| decision.binding.programRevision != binding.programRevision
		|| decision.binding.bodyRevision != binding.bodyRevision
		|| decision.binding.pipelineRevision != binding.pipelineRevision)
		throw "reflaxe.ocaml [callback-comparison:foreign-binding]: equality belongs to another final function body";
}

/** Each side reuses callback value emission while preserving its own source evaluation and identity. */
function operation(decision:OcamlCallableComparisonDecision, left:Bool):OcamlCallableValueOperation {
	requireDecision(decision);
	return uncheckedOperation(copy(decision), left);
}

function occurrenceId(binding:OcamlFunctionPlanBinding, source:OcamlLoweredSourceSpan, notEqual:Bool):String {
	return "callback-comparison:" + Sha256.encode([
		binding.functionId,
		binding.programRevision,
		binding.bodyRevision,
		binding.pipelineRevision,
		sourceKey(source),
		Std.string(notEqual)
	].join("|")).substr(0, 24);
}

private function uncheckedOperation(decision:OcamlCallableComparisonDecision, left:Bool):OcamlCallableValueOperation {
	final operand = left ? decision.left : decision.right;
	return {
		id: decision.id + (left ? ":left" : ":right"),
		role: left ? ComparisonLeft : ComparisonRight,
		source: operand.source,
		binding: decision.binding,
		origin: switch (operand.input) {
			case RawOrigin(kind): kind;
			case DeclaredOrigin(declaration): StaticDeclaration(declaration.calleeId);
			case _: null;
		},
		inputLayout: operand.layout,
		outputLayout: operand.layout,
		conversion: Identity,
		invocation: switch (operand.input) {
			case DeclaredOrigin(declaration): declaration;
			case _: null;
		}
	};
}

private function copyOperand(value:OcamlCallableComparisonOperand):OcamlCallableComparisonOperand {
	validate(value.layout);
	return {source: copySource(value.source), input: copyInput(value.input), layout: describe(value.layout.shape)};
}

private function copySource(value:OcamlLoweredSourceSpan):OcamlLoweredSourceSpan {
	return {file: value.file, min: value.min, max: value.max};
}

private function sourceKey(value:OcamlLoweredSourceSpan):String {
	return value.file + ":" + value.min + ":" + value.max;
}

private function fingerprint(id:String, left:OcamlCallableComparisonOperand, right:OcamlCallableComparisonOperand):String {
	return "sha256:" + Sha256.encode([
		id,
		sourceKey(left.source),
		inputKey(left.input),
		left.layout.revision,
		sourceKey(right.source),
		inputKey(right.input),
		right.layout.revision
	].join("\n"));
}
#end
