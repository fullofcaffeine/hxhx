package reflaxe.ocaml.tooling;

import reflaxe.ocaml.tooling.InspectionReport;
import reflaxe.ocaml.reports.OcamlCallableCallReport;
import reflaxe.ocaml.reports.OcamlCallableViewReport;
import reflaxe.ocaml.reports.OcamlGenericCallReport.sequence;
import reflaxe.ocaml.reports.OcamlReportJson.encode;
import reflaxe.ocaml.lowered.OcamlCallableViewRepresentation;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion;
import reflaxe.ocaml.lowered.OcamlCallableReturnContract;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;

/** Read all callback carrier fields explicitly; absent fields require regeneration of the report. */
function readValue(value:Dynamic):{layout:Null<CallableViewLayoutReport>, argument:Null<CallableArgumentReport>} {
	final layout = field(value, "callableView");
	final argument = field(value, "callbackArgument");
	return {
		layout: layout == null ? null : layoutToReport(layoutFromReport(layout)),
		argument: argument == null ? null : argumentToReport(argumentFromReport(argument))
	};
}

/** A computed call records its recursive invocation layout separately from its result layout. */
function readInvocation(value:Dynamic):Null<CallableCalleeReport> {
	final layout = field(value, "callbackInvocation");
	return layout == null ? null : calleeToReport(calleeFromReport(layout));
}

/** Decode each actual return instead of treating a result descriptor as evidence of a producing body. */
function readReturns(value:Dynamic):Null<Array<CallableReturnReport>> {
	final returns = field(value, "callbackReturns");
	return returns == null ? null : sequence(returns).map(value -> returnToReport(returnFromReport(value)));
}

/** The count distinguishes a planned non-returning body from deleted return records. */
function readReturnCount(value:Dynamic):Null<Int> {
	final count = field(value, "callbackReturnCount");
	if (count == null)
		return null;
	if (!Std.isOfType(count, Int) || count < 0)
		throw "Callback return count must be a nonnegative integer.";
	return cast count;
}

private function field(value:Dynamic, name:String):Dynamic {
	if (!Reflect.hasField(value, name))
		throw 'Callback call report is missing field "$name".';
	return Reflect.field(value, name);
}

/** Layout equality includes rebuilding both descriptors; matching stale revision strings are insufficient. */
function sameLayout(left:Null<CallableViewLayoutReport>, right:Null<CallableViewLayoutReport>):Bool {
	return left == null
		|| right == null ? left == null && right == null : layoutFromReport(left).revision == layoutFromReport(right).revision;
}

/** Validate the prepared carrier; source ownership is checked later against its enclosing call. */
function validateValue(value:InspectionCallValue):Bool {
	if (value.callableView == null) {
		if (value.callbackArgument != null || value.proofId == "identity-callable-view-carrier-v1")
			throw "Callback argument or carrier proof has no recursive layout.";
		return false;
	}
	final layout = layoutFromReport(value.callableView);
	final id = "representation:" + layout.semanticTypeId + ":internal-value";
	if (value.index < -1
		|| value.parameterOptional
		|| value.nullableEnumCarrier != null
		|| value.conversion != "identity"
		|| value.proofId != "identity-callable-view-carrier-v1"
		|| value.inputSemanticTypeId != layout.semanticTypeId
		|| value.outputSemanticTypeId != layout.semanticTypeId
		|| value.inputCarrierTypeId != layout.carrierTypeId
		|| value.outputCarrierTypeId != layout.carrierTypeId
		|| value.inputRepresentationId != id
		|| value.outputRepresentationId != id)
		throw "Callback call carrier disagrees with its recursive layout.";
	if (value.callbackArgument != null) {
		final prepared = argumentFromReport(value.callbackArgument);
		if (value.index < 0 || prepared.operation.outputLayout.revision != layout.revision)
			throw "Callback preparation disagrees with its declared argument carrier.";
	}
	return true;
}

/** Admit only the closed recursive signature under its dedicated declaration or invocation proof. */
function validateSignature(kind:String, receiver:Null<InspectionCallValue>, arguments:Array<InspectionCallValue>, resultKind:String,
		result:Null<InspectionCallValue>, proof:String, isBoundary:Bool):Bool {
	final declared = proof == "direct-static-callable-view-signature-v1";
	final invoked = proof == "typed-callable-view-invocation-v1";
	if (!declared && !invoked) {
		if (Lambda.exists(arguments, value -> value.callableView != null) || (result != null && result.callableView != null))
			throw "Callback signature has no matching recursive declaration proof.";
		return false;
	}
	if (receiver != null
		|| (declared && kind != "direct-static-haxe-method")
		|| (invoked && (isBoundary || kind != "typed-function-value")))
		throw "Callback signature proof belongs to another call kind.";
	if ((resultKind == "value") != (result != null) || (resultKind != "value" && resultKind != "effect-only-void"))
		throw "Callback signature lost its declared result kind.";
	for (index in 0...arguments.length) {
		final argument = arguments[index];
		if (argument.index != index
			|| argument.parameterOptional
			|| (isBoundary && (argument.conversion != "identity" || argument.callbackArgument != null)))
			throw "Callback signature lost its declared parameter slot.";
	}
	if (result != null
		&& (result.index != -1 || result.parameterOptional || result.conversion != "identity" || result.callbackArgument != null))
		throw "Callback signature has an invalid result carrier.";
	final layout = signature(arguments, result);
	if (declared && !Lambda.exists(arguments, value -> value.callableView != null) && (result == null || result.callableView == null))
		throw "Scalar declaration has an unrelated callback signature proof.";
	return true;
}

/** Reconstruct the exported signature from independently checked parameter and result carrier records. */
function signature(arguments:Array<InspectionCallValue>, result:Null<InspectionCallValue>):OcamlCallableViewDescriptor {
	return describe(FunctionValue(arguments.map(shape), result == null ? EffectOnly : shape(result)));
}

/** Scalar nullability can share a carrier; recursive callback slots must still match exactly. */
function matchesSignature(layout:OcamlCallableViewDescriptor, arguments:Array<InspectionCallValue>, result:Null<InspectionCallValue>):Bool {
	validate(layout);
	function matches(expected:OcamlGenericValueShape, value:InspectionCallValue):Bool {
		return switch (expected) {
			case Text(_): value.callableView == null && value.outputSemanticTypeId == "String";
			case _: shapeId(expected) == shapeId(shape(value));
		};
	}
	return switch (layout.shape) {
		case FunctionValue(parameters, returned): parameters.length == arguments.length && (result == null ? returned == EffectOnly : matches(returned,
				result)) && Lambda.foreach([for (index in 0...arguments.length) index], index -> matches(parameters[index], arguments[index]));
		case _: false;
	};
}

private function shape(value:InspectionCallValue):OcamlGenericValueShape {
	if (value.callableView != null) {
		validateValue(value);
		return layoutFromReport(value.callableView).shape;
	}
	return switch (value.outputSemanticTypeId) {
		case "Int": Integer;
		case "Bool": Boolean;
		case "String": Text(false);
		case "Null<Int>": NullableInteger;
		case "Null<Bool>": NullableBoolean;
		case "Dynamic": DynamicValue;
		case _: throw "Callback signature has an unsupported scalar carrier.";
	};
}

/** Return and argument operations must retain the complete final caller identity. */
function binding(value:OcamlFunctionPlanBinding):OcamlFunctionPlanBinding {
	return {
		functionId: value.functionId,
		programRevision: value.programRevision,
		bodyRevision: value.bodyRevision,
		pipelineRevision: value.pipelineRevision
	};
}

/** A declaration reference must describe the actual body exported by this program. */
function requireDeclaration(reference:OcamlCallableInvocationReference, boundaries:Map<String, InspectionCallableBoundary>):InspectionCallableBoundary {
	final declared = boundaries.get(reference.calleeId);
	if (declared == null
		|| declared.programRevision != reference.programRevision
		|| declared.pipelineRevision != reference.pipelineRevision
		|| !matchesSignature(reference.layout, declared.arguments, declared.result))
		throw "Callback producer does not match its exported declaration.";
	return declared;
}

/** Check the containing call and declaration before any consumer may use their callback evidence. */
function validateInventory(calls:Array<InspectionCall>, boundaries:Array<InspectionCallableBoundary>):Void {
	final declarations:Map<String, InspectionCallableBoundary> = [];
	final byCall:Map<String, InspectionCall> = [];
	for (boundary in boundaries)
		declarations.set(boundary.calleeId, boundary);
	for (call in calls)
		byCall.set(call.id, call);
	for (call in calls) {
		if (call.proofId == "direct-static-callable-view-signature-v1") {
			final target = declarations.get(call.calleeId);
			if (target == null || target.programRevision != call.programRevision || target.pipelineRevision != call.pipelineRevision)
				throw "Callback call refers to a declaration from another program or pipeline.";
		}
		if (call.callbackInvocation != null) {
			if (reflaxe.ocaml.lowered.OcamlCallableInvocationContract.calleeId(calleeFromReport(call.callbackInvocation), binding(call)) != call.calleeId
				|| call.kind != "typed-function-value"
				|| call.proofId != "typed-callable-view-invocation-v1"
				|| !matchesSignature(calleeFromReport(call.callbackInvocation).layout, call.arguments, call.result))
				throw "Callback invocation does not match its computed call signature.";
		} else if (call.proofId == "typed-callable-view-invocation-v1")
			throw "Callback invocation lost its recursive signature.";
		for (argument in call.arguments) {
			if (argument.callbackArgument == null) {
				if (argument.callableView != null)
					throw "Callback call argument has no source preparation evidence.";
				continue;
			}
			final operation = argumentFromReport(argument.callbackArgument).operation;
			if (operation.id != call.id + ":callback-argument:" + argument.index || encode(operation.binding) != encode(binding(call)))
				throw "Callback argument belongs to another call slot or final body.";
		}
	}
	for (boundary in boundaries) {
		if (Lambda.exists(boundary.arguments, value -> value.callbackArgument != null)
			|| (boundary.result != null && boundary.result.callbackArgument != null))
			throw "Callable declaration owns a caller's callback preparation.";
		final returns = boundary.callbackReturns;
		if (boundary.result == null || boundary.result.callableView == null) {
			if (returns != null || boundary.callbackReturnCount != null)
				throw "Callback returns have no declared callback result.";
			continue;
		}
		if (returns == null)
			throw "Declared callback result has no producing return inventory.";
		if (boundary.callbackReturnCount == null || boundary.callbackReturnCount != returns.length)
			throw "Declared callback result has incomplete return occurrences.";
		final ids:Map<String, Bool> = [];
		for (entry in returns) {
			final returned = returnFromReport(entry);
			requireBinding(returned, binding(boundary));
			if (ids.exists(returned.id)
				|| returned.boundary.calleeId != boundary.calleeId
				|| requireDeclaration(returned.boundary, declarations).id != boundary.id)
				throw "Callback return has a duplicate occurrence or a foreign declaration.";
			ids.set(returned.id, true);
			switch (returned.input) {
				case CallResult(id, reference):
					final call = byCall.get(id);
					requireDeclaration(reference, declarations);
					if (call == null
						|| encode(binding(call)) != encode(returned.binding)
						|| call.calleeId != reference.calleeId
						|| call.result == null
						|| call.result.callableView == null
						|| layoutFromReport(call.result.callableView).revision != operation(returned).inputLayout.revision
						|| call.sourceFile != returned.source.file
						|| call.sourceMin != returned.source.min
						|| call.sourceMax != returned.source.max)
						throw "Returned callback does not match the actual call result in its final body.";
				case Producer(StaticDeclaration(id), layout):
					requireDeclaration({
						calleeId: id,
						layout: layout,
						programRevision: boundary.programRevision,
						pipelineRevision: boundary.pipelineRevision
					}, declarations);
				case Producer(FreshLiteral, _), Parameter(_), LocalView(_, _):
			}
		}
	}
}
