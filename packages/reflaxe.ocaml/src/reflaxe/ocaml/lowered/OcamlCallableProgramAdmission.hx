package reflaxe.ocaml.lowered;

import reflaxe.ocaml.lowered.OcamlGenericCallConversion.OcamlGenericValueShape;

/** Host adapters describe every method and unsupported observer before callback interfaces can change. */
typedef OcamlCallableProgramCandidate = {
	final id:String;
	final fieldName:String;
	final signature:Null<OcamlGenericValueShape>;
	final dependencies:Array<String>;
	final rejected:Bool;
	final usesViews:Bool;
};

/** Selection identifies a closed component; declaration and occurrence plans still authorize its native representation. */
typedef OcamlCallableMethodSelection = {
	final calleeId:String;
	final fieldName:String;
	final signature:OcamlGenericValueShape;
};

/** Callback arguments and results change the method interface; scalar-only interfaces keep their ordinary layout. */
function needsBoundary(shape:Null<OcamlGenericValueShape>):Bool {
	function callback(value:OcamlGenericValueShape):Bool {
		return switch value {
			case FunctionValue(_, _): true;
			case _: false;
		};
	}
	return switch shape {
		case FunctionValue(arguments, result): callback(result) || Lambda.exists(arguments, callback);
		case _: false;
	};
}

/**
	Reject a whole connected callback component when any consumer cannot use it.

	Host adapters own typed-use classification and supply all consumers, including
	unsupported observers such as field initializers. Edges work in both directions:
	a later unsupported caller invalidates an earlier selected factory and its callers.
	A runtime class value can expose any higher-order method, so those methods and
	their connected consumers are excluded until reflection has an explicit plan.

	This function does not mutate the adapter's facts or authorize emitted syntax.
	Each host must still bind selected declarations and occurrences to its exact
	current typed program before the representation registry can publish layouts.
**/
function select(input:Array<OcamlCallableProgramCandidate>, hasUnresolvedClassValue:Bool = false):Array<OcamlCallableMethodSelection> {
	final candidates:Map<String, OcamlCallableProgramCandidate> = [];
	final edges:Map<String, Array<String>> = [];
	final rejected:Map<String, Bool> = [];
	for (candidate in input) {
		if (candidates.exists(candidate.id))
			throw "reflaxe.ocaml [callback-program:duplicate-method]: typed declaration occurs twice";
		candidates.set(candidate.id, candidate);
		edges.set(candidate.id, []);
		if (candidate.rejected
			|| (candidate.usesViews && candidate.signature == null)
			|| (hasUnresolvedClassValue && needsBoundary(candidate.signature)))
			rejected.set(candidate.id, true);
	}
	for (candidate in input)
		for (dependency in candidate.dependencies) {
			if (!candidates.exists(dependency)) {
				rejected.set(candidate.id, true);
				continue;
			}
			final forward = edges.get(candidate.id);
			final reverse = edges.get(dependency);
			if (forward == null || reverse == null)
				throw "reflaxe.ocaml [callback-program:missing-method]: a connected method has no graph entry";
			if (!forward.contains(dependency))
				forward.push(dependency);
			if (!reverse.contains(candidate.id))
				reverse.push(candidate.id);
		}
	final pending = [for (id in rejected.keys()) id];
	while (pending.length > 0) {
		final id = pending.pop();
		if (id == null)
			break;
		final dependencies = edges.get(id);
		if (dependencies == null)
			throw "reflaxe.ocaml [callback-program:missing-method]: rejection lost its typed declaration";
		for (dependency in dependencies)
			if (!rejected.exists(dependency)) {
				rejected.set(dependency, true);
				pending.push(dependency);
			}
	}
	final selected:Array<OcamlCallableMethodSelection> = [];
	for (candidate in input) {
		if (!candidate.usesViews || rejected.exists(candidate.id))
			continue;
		final signature:OcamlGenericValueShape = candidate.signature ?? throw "reflaxe.ocaml [callback-program:missing-signature]: selected method has no checked signature";
		selected.push({calleeId: candidate.id, fieldName: candidate.fieldName, signature: signature});
	}
	selected.sort((left, right) -> left.calleeId < right.calleeId ? -1 : left.calleeId > right.calleeId ? 1 : 0);
	return selected;
}
