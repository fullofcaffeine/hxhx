package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime || eval)
import reflaxe.ocaml.lowered.OcamlCallableViewContract;
import reflaxe.ocaml.lowered.OcamlCallableViewContract.OcamlCallableViewInput;
import reflaxe.ocaml.lowered.OcamlCallableValueOperation;
import reflaxe.ocaml.lowered.OcamlCallableViewRepresentation;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion;

/** The source proof and preparation step for one callback argument slot. */
typedef OcamlCallableArgumentPlan = {
	final input:OcamlCallableViewInput;
	final operation:OcamlCallableValueOperation;
};

/** Validate preparation independently from the call's already-prepared argument carrier. */
function requireArgument(plan:OcamlCallableArgumentPlan):Void {
	final operation = plan.operation;
	requireOperation(operation);
	if (operation.role != ArgumentValue)
		throw "reflaxe.ocaml [callback-argument:wrong-role]: callback argument borrowed another occurrence role";
	switch (plan.input) {
		case ExistingView(reference):
			requireReference(reference, operation.inputLayout);
			if (operation.origin != null || operation.invocation != null)
				throw "reflaxe.ocaml [callback-argument:changed-origin]: existing callback cannot create another identity";
		case CallResult(source):
			if (source.file != operation.source.file
				|| source.min != operation.source.min
				|| source.max != operation.source.max
				|| operation.origin != null
				|| operation.invocation != null)
				throw "reflaxe.ocaml [callback-argument:changed-call]: callback argument lost its result occurrence";
		case RawOrigin(kind):
			if (Std.string(kind) != Std.string(operation.origin) || operation.invocation != null)
				throw "reflaxe.ocaml [callback-argument:changed-origin]: callback argument lost its raw producer";
		case DeclaredOrigin(declaration):
			validate(declaration.layout);
			final invocation = operation.invocation;
			if (invocation == null
				|| declaration.calleeId != invocation.calleeId
				|| declaration.programRevision != invocation.programRevision
				|| declaration.pipelineRevision != invocation.pipelineRevision
				|| declaration.layout.revision != invocation.layout.revision)
				throw "reflaxe.ocaml [callback-argument:changed-declaration]: callback argument lost its published producer";
	}
}

/** Detach host-mutable arrays before a call plan retains or exposes preparation facts. */
function copy(plan:OcamlCallableArgumentPlan):OcamlCallableArgumentPlan {
	requireArgument(plan);
	final source = plan.operation;
	final input = copyInput(plan.input);
	return {
		input: input,
		operation: {
			id: source.id,
			role: source.role,
			source: {file: source.source.file, min: source.source.min, max: source.source.max},
			binding: {
				functionId: source.binding.functionId,
				programRevision: source.binding.programRevision,
				bodyRevision: source.binding.bodyRevision,
				pipelineRevision: source.binding.pipelineRevision
			},
			origin: source.origin,
			inputLayout: describe(source.inputLayout.shape),
			outputLayout: describe(source.outputLayout.shape),
			conversion: crossing(source.inputLayout.shape, source.outputLayout.shape) ?? throw "callback argument lost conversion",
			invocation: switch (input) {
				case DeclaredOrigin(declaration): declaration;
				case _: null;
			}
		}
	};
}

/** Include the source proof and final-body identity in the enclosing call fingerprint. */
function fingerprint(plan:OcamlCallableArgumentPlan):String {
	requireArgument(plan);
	final operation = plan.operation;
	return [
		                    operation.id,               inputKey(plan.input),    operation.binding.functionId, operation.binding.programRevision,
		  operation.binding.bodyRevision, operation.binding.pipelineRevision,           operation.source.file,  Std.string(operation.source.min),
		Std.string(operation.source.max),     operation.inputLayout.revision, operation.outputLayout.revision,  Std.string(operation.conversion)
	].join("\n");
}
#end
