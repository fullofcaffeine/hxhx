package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.crypto.Sha256;
import haxe.macro.Type;
import reflaxe.ocaml.lowered.OcamlCallPlan;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallPlanner;
import reflaxe.ocaml.lowered.OcamlCallableProgramSelection.OcamlCallableMethodSelection;
import reflaxe.ocaml.lowered.OcamlCallableViewRepresentation;
import reflaxe.ocaml.lowered.OcamlCallableViewRepresentation.OcamlCallableViewDescriptor;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion.OcamlGenericValueShape;

/** The whole-program selection changes a method's callback arguments and results together. */
final SIGNATURE_PROOF = "direct-static-callable-view-signature-v1";

/** A view crosses this boundary unchanged; creating or adapting it needs a separate occurrence plan. */
final VALUE_PROOF = "identity-callable-view-carrier-v1";

final INVOCATION_PROOF = "typed-callable-view-invocation-v1";

/** Scalar-only method interfaces already use the ordinary catalog entry. */
function changesInterface(shape:OcamlGenericValueShape):Bool {
	function callback(value:OcamlGenericValueShape):Bool {
		return switch (value) {
			case FunctionValue(_, _): true;
			case _: false;
		};
	}
	return switch (shape) {
		case FunctionValue(arguments, result): Lambda.exists(arguments, callback) || callback(result);
		case _: false;
	};
}

/**
	Builds the ordinary declaration catalog entry for a selected callback method.

	The selection must come from the complete typed consumer scan. Rechecking the
	method and recursive signature here prevents an entry from authorizing another
	declaration. Final bodies and call occurrences still have to prove producers,
	conversions and every use before this declaration can reach native output.
**/
function declaration(owner:ClassType, field:ClassField, selection:OcamlCallableMethodSelection, registry:OcamlRepresentationRegistry, programRevision:String,
		pipelineRevision:String):OcamlCallableDeclarationPlan {
	final normalOwner = switch (owner.kind) {
		case KNormal: true;
		case _: false;
	};
	final normalMethod = switch (field.kind) {
		case FMethod(MethNormal): true;
		case _: false;
	};
	final shape = callableShape(field.type);
	final id = OcamlCallPlanner.calleeId(owner, field);
	// Macro API field wrappers are not stable object identities across reads.
	// Resolve the declared member by name and compare its typed signature.
	final member = Lambda.find(owner.statics.get(), candidate -> candidate.name == field.name);
	final memberShape = member == null ? null : callableShape(member.type);
	if (!normalOwner
		|| !normalMethod
		|| owner.isExtern
		|| owner.isInterface
		|| owner.params.length != 0
		|| owner.meta.has(":native")
		|| field.isExtern
		|| field.params.length != 0
		|| field.overloads.get().length != 0
		|| field.meta.has(":native")
		|| memberShape == null
		|| shape == null
		|| shapeId(memberShape) != shapeId(shape)
		|| selection.calleeId != id
		|| selection.fieldName != field.name
		|| shape == null
		|| shapeId(shape) != shapeId(selection.signature))
		throw "reflaxe.ocaml [callback-declaration:source-mismatch]: selected callback declaration no longer matches its typed source";
	final signature = switch (shape) {
		case FunctionValue(arguments, result): {arguments: arguments, result: result};
		case _: throw "reflaxe.ocaml [callback-declaration:missing-signature]: selected method is not callable";
	};
	final result = signature.result == EffectOnly ? null : value(-1, signature.result, registry);
	final selected:OcamlCallableDeclarationPlan = {
		id: "callable-declaration:" + Sha256.encode(id).substr(0, 24),
		calleeId: id,
		sourceModuleId: owner.module,
		sourceTypeName: owner.name,
		sourceFieldName: field.name,
		kind: DirectStaticHaxeMethod,
		receiver: null,
		arguments: [
			for (index in 0...signature.arguments.length)
				value(index, signature.arguments[index], registry)
		],
		resultKind: result == null ? EffectOnlyVoid : Value,
		result: result,
		profileEligibility: ["metal", "portable"],
		reason: "The complete typed consumer scan selected this ordinary static method. Callback parameters and results carry their invocation and original identity together.",
		proofId: SIGNATURE_PROOF,
		proofClaim: "The exact declaration and final body must agree on every recursive callback carrier. Each caller must supply a separately proved view and preserve the returned identity.",
		programRevision: programRevision,
		pipelineRevision: pipelineRevision
	};
	OcamlCallPlan.requireCallableDeclarationPlan(selected);
	return selected;
}

/** Construct a detached carrier record; this does not classify a source expression as a view. */
function value(index:Int, shape:OcamlGenericValueShape, registry:OcamlRepresentationRegistry):OcamlCallValuePlan {
	final representation = switch (shape) {
		case Integer: registry.selectExactInt(InternalValue);
		case Boolean: registry.selectExactBool(InternalValue);
		case Text(_): registry.selectExactString(InternalValue);
		case DynamicValue: registry.selectExactDynamic(InternalValue);
		case NullableInteger: registry.selectExactNullInt(InternalValue);
		case NullableBoolean: registry.selectExactNullBool(InternalValue);
		case FunctionValue(_, _): registry.selectCallableView(shape, InternalValue);
		case _: throw "reflaxe.ocaml [callback-declaration:unsupported-carrier]: selected boundary has no represented value";
	};
	final layout = switch (shape) {
		case FunctionValue(_, _): describe(shape);
		case _: null;
	};
	return {
		index: index,
		parameterOptional: false,
		inputSemanticTypeId: representation.semanticTypeId,
		inputCarrierTypeId: representation.carrierTypeId,
		inputRepresentationId: representation.id,
		outputSemanticTypeId: representation.semanticTypeId,
		outputCarrierTypeId: representation.carrierTypeId,
		outputRepresentationId: representation.id,
		conversion: Identity,
		proofId: layout == null ? "identity-call-carrier-v1" : VALUE_PROOF,
		proofClaim: layout == null ? "The selected scalar already uses its declared native carrier." : "The selected callback view preserves its invocation and original identity without conversion.",
		callableView: layout
	};
}

/** Validate the recursive layout as well as both carrier identities before accepting a view crossing. */
function requireValue(value:OcamlCallValuePlan):Void {
	final layout = value.callableView;
	if (layout == null)
		throw "reflaxe.ocaml [callback-declaration:missing-layout]: callback carrier has no recursive layout";
	validate(layout);
	final id = "representation:" + layout.semanticTypeId + ":internal-value";
	if (value.index < -1
		|| value.parameterOptional
		|| value.conversion != Identity
		|| value.proofId != VALUE_PROOF
		|| value.nullableEnumCarrier != null
		|| value.inputSemanticTypeId != layout.semanticTypeId
		|| value.outputSemanticTypeId != layout.semanticTypeId
		|| value.inputCarrierTypeId != layout.carrierTypeId
		|| value.outputCarrierTypeId != layout.carrierTypeId
		|| value.inputRepresentationId != id
		|| value.outputRepresentationId != id)
		throw "reflaxe.ocaml [callback-declaration:invalid-carrier]: callback crossing does not preserve its declared view";
}

/** Comparing descriptors also validates them; an unchanged revision string cannot conceal changed nested arguments. */
function same(left:Null<OcamlCallableViewDescriptor>, right:Null<OcamlCallableViewDescriptor>):Bool {
	if (left == null || right == null)
		return left == null && right == null;
	validate(left);
	validate(right);
	return left.revision == right.revision;
}

/** A return's recursive invocation signature must describe the actual exported argument slots. */
function requireSignature(layout:OcamlCallableViewDescriptor, arguments:Array<OcamlCallValuePlan>, result:Null<OcamlCallValuePlan>):Void {
	validate(layout);
	function matches(shape:OcamlGenericValueShape, value:OcamlCallValuePlan):Bool {
		return switch (shape) {
			case FunctionValue(_, _): value.callableView != null && same(describe(shape), value.callableView);
			case _: final semantic = switch (shape) {
					case Integer: "Int";
					case Boolean: "Bool";
					case Text(_): "String";
					case NullableInteger: "Null<Int>";
					case NullableBoolean: "Null<Bool>";
					case DynamicValue: "Dynamic";
					case _: "";
				}; semantic.length > 0 && value.callableView == null && value.outputSemanticTypeId == semantic;
		};
	}
	final signature = switch (layout.shape) {
		case FunctionValue(parameters, returned): {parameters: parameters, returned: returned};
		case _: throw "reflaxe.ocaml [callback-declaration:invalid-invocation]: layout is not callable";
	};
	if (arguments.length != signature.parameters.length
		|| (result == null ? signature.returned != EffectOnly : !matches(signature.returned, result)))
		throw "reflaxe.ocaml [callback-declaration:invalid-invocation]: invocation result or arity differs from its declaration";
	for (index in 0...arguments.length)
		if (arguments[index].parameterOptional || !matches(signature.parameters[index], arguments[index]))
			throw "reflaxe.ocaml [callback-declaration:invalid-invocation]: invocation parameter differs from its declaration";
}
#end
