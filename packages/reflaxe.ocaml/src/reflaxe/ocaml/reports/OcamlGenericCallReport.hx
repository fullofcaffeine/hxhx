package reflaxe.ocaml.reports;

import reflaxe.ocaml.lowered.OcamlGenericInstanceCallContract.require as genericCallRequire;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion.OcamlGenericValueShape;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion.OcamlGenericValueConversion;
import reflaxe.ocaml.lowered.OcamlGenericInstanceCallContract.OcamlGenericInstanceCallTarget;

/** Closed tags for the plain-data representation of generic storage and conversions. */
private enum abstract NodeKind(String) to String {
	final Erased = "erased";
	final Integer = "int";
	final Boolean = "bool";
	final Text = "string";
	final NullableText = "nullable-string";
	final NullableInteger = "nullable-int";
	final NullableBoolean = "nullable-bool";
	final ArrayValue = "array";
	final FunctionValue = "function";
	final EffectOnly = "void";
	final Identity = "identity";
	final BoxValue = "box-value";
	final UnboxValue = "unbox-value";
	final BoxBoolean = "box-bool";
	final UnboxBoolean = "unbox-bool";
	final BoxNullableBoolean = "box-nullable-bool";
	final UnboxNullableBoolean = "unbox-nullable-bool";
	final AdaptFunction = "adapt-function";
}

/** Parameters are present only for erased nodes; function children end with the result. */
private typedef ReportNode = {
	final kind:NodeKind;
	final parameter:Null<String>;
	final children:Array<ReportNode>;
}

/** JSON-safe projection; no compiler object or Haxe enum reaches the report writer. */
typedef GenericCallReportTarget = {
	final moduleId:String;
	final typeName:String;
	final fieldName:String;
	final receiverTypeId:String;
	final receiverRepresentationId:String;
	final ownedParameterIds:Array<String>;
	final declaration:ReportNode;
	final instantiation:ReportNode;
	final argumentShapes:Array<ReportNode>;
	final arguments:Array<ReportNode>;
	final resultShape:ReportNode;
	final result:ReportNode;
}

/** Copies a validated target into explicit scalar and recursive record fields. */
function targetToReport(target:OcamlGenericInstanceCallTarget):GenericCallReportTarget {
	genericCallRequire(target);
	return {
		moduleId: target.moduleId,
		typeName: target.typeName,
		fieldName: target.fieldName,
		receiverTypeId: target.receiverTypeId,
		receiverRepresentationId: target.receiverRepresentationId,
		ownedParameterIds: target.ownedParameterIds.copy(),
		declaration: shapeToReport(target.declaration),
		instantiation: shapeToReport(target.instantiation),
		argumentShapes: target.argumentShapes.map(shapeToReport),
		arguments: target.arguments.map(conversionToReport),
		resultShape: shapeToReport(target.resultShape),
		result: conversionToReport(target.result)
	};
}

/**
	Validates untrusted JSON at the report boundary, then checks the typed conversion contract.
	Dynamic is confined to the parsed JSON tree. Each field is narrowed before domain use;
	unknown fields, unsupported tags, malformed trees, and conflicting conversions are errors.
**/
function targetFromReport(value:Dynamic):OcamlGenericInstanceCallTarget {
	requireFields(value, [
		   "moduleId",      "typeName",      "fieldName", "receiverTypeId", "receiverRepresentationId", "ownedParameterIds",
		"declaration", "instantiation", "argumentShapes",      "arguments",              "resultShape",            "result"
	]);
	final target:OcamlGenericInstanceCallTarget = {
		moduleId: text(Reflect.field(value, "moduleId")),
		typeName: text(Reflect.field(value, "typeName")),
		fieldName: text(Reflect.field(value, "fieldName")),
		receiverTypeId: text(Reflect.field(value, "receiverTypeId")),
		receiverRepresentationId: text(Reflect.field(value, "receiverRepresentationId")),
		ownedParameterIds: sequence(Reflect.field(value, "ownedParameterIds")).map(text),
		declaration: readShape(Reflect.field(value, "declaration"), 0),
		instantiation: readShape(Reflect.field(value, "instantiation"), 0),
		argumentShapes: sequence(Reflect.field(value, "argumentShapes")).map(entry -> readShape(entry, 0)),
		arguments: sequence(Reflect.field(value, "arguments")).map(entry -> readConversion(entry, 0)),
		resultShape: readShape(Reflect.field(value, "resultShape"), 0),
		result: readConversion(Reflect.field(value, "result"), 0)
	};
	genericCallRequire(target);
	return target;
}

private function node(kind:NodeKind, ?children:Array<ReportNode>, ?parameter:String):ReportNode {
	return {kind: kind, parameter: parameter, children: children == null ? [] : children};
}

private function shapeToReport(shape:OcamlGenericValueShape):ReportNode {
	return switch (shape) {
		case Erased(parameter): node(NodeKind.Erased, [], parameter);
		case Integer: node(NodeKind.Integer);
		case Boolean: node(NodeKind.Boolean);
		case Text(nullable): node(nullable ? NodeKind.NullableText : NodeKind.Text);
		case NullableInteger: node(NodeKind.NullableInteger);
		case NullableBoolean: node(NodeKind.NullableBoolean);
		case ArrayValue(element): node(NodeKind.ArrayValue, [shapeToReport(element)]);
		case FunctionValue(arguments, result): node(NodeKind.FunctionValue, arguments.map(shapeToReport).concat([shapeToReport(result)]));
		case EffectOnly: node(NodeKind.EffectOnly);
	};
}

private function conversionToReport(conversion:OcamlGenericValueConversion):ReportNode {
	return switch (conversion) {
		case Identity: node(NodeKind.Identity);
		case BoxValue: node(NodeKind.BoxValue);
		case UnboxValue: node(NodeKind.UnboxValue);
		case BoxBoolean: node(NodeKind.BoxBoolean);
		case UnboxBoolean: node(NodeKind.UnboxBoolean);
		case BoxNullableBoolean: node(NodeKind.BoxNullableBoolean);
		case UnboxNullableBoolean: node(NodeKind.UnboxNullableBoolean);
		case AdaptFunction(arguments, result): node(NodeKind.AdaptFunction, arguments.map(conversionToReport).concat([conversionToReport(result)]));
	};
}

private function readShape(value:Dynamic, depth:Int):OcamlGenericValueShape {
	final decoded = readNode(value, depth);
	final children = decoded.children;
	return switch (decoded.kind) {
		case "erased" if (children.length == 0 && decoded.parameter != null): Erased(decoded.parameter);
		case "int" if (children.length == 0): Integer;
		case "bool" if (children.length == 0): Boolean;
		case "string" if (children.length == 0): Text(false);
		case "nullable-string" if (children.length == 0): Text(true);
		case "nullable-int" if (children.length == 0): NullableInteger;
		case "nullable-bool" if (children.length == 0): NullableBoolean;
		case "void" if (children.length == 0): EffectOnly;
		case "array" if (children.length == 1): ArrayValue(readShape(children[0], depth + 1));
		case "function" if (children.length > 0):
			FunctionValue(children.slice(0, -1).map(child -> readShape(child, depth + 1)), readShape(children[children.length - 1], depth + 1));
		case _: throw "Generic call report has an unsupported or malformed storage shape.";
	};
}

private function readConversion(value:Dynamic, depth:Int):OcamlGenericValueConversion {
	final decoded = readNode(value, depth);
	final children = decoded.children;
	return switch (decoded.kind) {
		case "identity" if (children.length == 0): Identity;
		case "box-value" if (children.length == 0): BoxValue;
		case "unbox-value" if (children.length == 0): UnboxValue;
		case "box-bool" if (children.length == 0): BoxBoolean;
		case "unbox-bool" if (children.length == 0): UnboxBoolean;
		case "box-nullable-bool" if (children.length == 0): BoxNullableBoolean;
		case "unbox-nullable-bool" if (children.length == 0): UnboxNullableBoolean;
		case "adapt-function" if (children.length > 0):
			AdaptFunction(children.slice(0, -1).map(child -> readConversion(child, depth + 1)), readConversion(children[children.length - 1], depth + 1));
		case _: throw "Generic call report has an unsupported or malformed conversion.";
	};
}

/** Keeps JSON tags and children at this boundary until recursive validation finishes. */
private function readNode(value:Dynamic, depth:Int):{kind:String, parameter:Null<String>, children:Array<Dynamic>} {
	if (depth > 64)
		throw "Generic call report exceeds the supported type nesting depth.";
	requireFields(value, ["kind", "parameter", "children"]);
	final kind = text(Reflect.field(value, "kind"));
	final rawParameter:Dynamic = Reflect.field(value, "parameter");
	final parameter = rawParameter == null ? null : text(rawParameter);
	if ((kind == "erased") != (parameter != null))
		throw "Generic call report has an unexpected type parameter.";
	return {kind: kind, parameter: parameter, children: sequence(Reflect.field(value, "children"))};
}

private function text(value:Dynamic):String {
	if (!Std.isOfType(value, String))
		throw "Generic call report requires a String field.";
	final selected:String = value;
	if (selected.length == 0)
		throw "Generic call report requires a nonempty String field.";
	return selected;
}

private function sequence(value:Dynamic):Array<Dynamic> {
	if (!Std.isOfType(value, Array))
		throw "Generic call report requires an Array field.";
	return value;
}

private function requireFields(value:Dynamic, expected:Array<String>):Void {
	if (Type.typeof(value) != TObject)
		throw "Generic call report requires a plain object.";
	final actual = Reflect.fields(value);
	if (actual.length != expected.length || Lambda.exists(actual, name -> expected.indexOf(name) < 0))
		throw "Generic call report has missing or unexpected fields.";
}

#if macro
/** Copies the existing call envelope while projecting only the enum-bearing generic target. */
function callToReport(call:reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallDecision) {
	return {
		id: call.id,
		source: call.source,
		calleeId: call.calleeId,
		sourceModuleId: call.sourceModuleId,
		sourceTypeName: call.sourceTypeName,
		sourceFieldName: call.sourceFieldName,
		kind: call.kind,
		receiver: call.receiver,
		arguments: call.arguments,
		resultKind: call.resultKind,
		result: call.result,
		resultMaterialization: call.resultMaterialization,
		evaluationSchedule: call.evaluationSchedule,
		profileEligibility: call.profileEligibility,
		reason: call.reason,
		proofId: call.proofId,
		proofClaim: call.proofClaim,
		functionId: call.functionId,
		programRevision: call.programRevision,
		bodyRevision: call.bodyRevision,
		pipelineRevision: call.pipelineRevision,
		dynamicFunctionTarget: call.dynamicFunctionTarget,
		standardArrayTarget: call.standardArrayTarget,
		standardIMapTarget: call.standardIMapTarget,
		structuralIteratorTarget: call.structuralIteratorTarget,
		genericInstanceTarget: call.genericInstanceTarget == null ? null : targetToReport(call.genericInstanceTarget)
	};
}
#end
