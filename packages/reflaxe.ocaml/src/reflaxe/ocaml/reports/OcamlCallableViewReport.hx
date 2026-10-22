package reflaxe.ocaml.reports;

import reflaxe.ocaml.lowered.OcamlCallableViewRepresentation;
import reflaxe.ocaml.lowered.OcamlCallableViewRepresentation.OcamlCallableViewDescriptor;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion.OcamlGenericValueConversion;
import reflaxe.ocaml.reports.OcamlGenericCallReport;
import reflaxe.ocaml.reports.OcamlGenericCallReport.ReportNode;
import reflaxe.ocaml.lowered.OcamlCallableViewContract;
import reflaxe.ocaml.lowered.OcamlCallableViewContract.OcamlCallableViewLocalDecision;
import reflaxe.ocaml.lowered.OcamlCallableViewContract.OcamlCallableViewInput;
import reflaxe.ocaml.lowered.OcamlLocalConversionModel.OcamlLocalRepresentationReference;
import reflaxe.ocaml.lowered.OcamlLocalConversionModel.OcamlLocalConversionRole;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;

/** A recursive callback signature with its exact native representation revision. */
typedef CallableViewLayoutReport = {
	final shape:ReportNode;
	final semanticTypeId:String;
	final carrierTypeId:String;
	final revision:String;
};

/** Export the closed shape tree rather than host enum instances. */
function layoutToReport(layout:OcamlCallableViewDescriptor):CallableViewLayoutReport {
	validate(layout);
	return {
		shape: callableShapeToReport(layout.shape),
		semanticTypeId: layout.semanticTypeId,
		carrierTypeId: layout.carrierTypeId,
		revision: layout.revision
	};
}

/** Rebuild the layout from its shape and reject independently changed representation fields. */
function layoutFromReport(value:Dynamic):OcamlCallableViewDescriptor {
	requireFields(value, ["shape", "semanticTypeId", "carrierTypeId", "revision"]);
	final layout = describe(callableShapeFromReport(Reflect.field(value, "shape")));
	if (Reflect.field(value, "semanticTypeId") != layout.semanticTypeId
		|| Reflect.field(value, "carrierTypeId") != layout.carrierTypeId
		|| Reflect.field(value, "revision") != layout.revision)
		throw "Callback layout report has a stale or changed descriptor.";
	return layout;
}

/** Explicit producer tags; absent fields remain null instead of carrying an invented local. */
private enum abstract InputKind(String) to String {
	final Existing = "existing-view";
	final Literal = "fresh-literal";
	final Declaration = "static-declaration";
	final Published = "published-declaration";
	final Call = "call-result";
}

/** JSON-safe producer evidence shared by writes, arguments and comparisons. */
typedef CallableViewInputReport = {
	final kind:InputKind;
	final reference:Null<OcamlLocalRepresentationReference>;
	final calleeId:Null<String>;
	final declaration:Null<{programRevision:String, pipelineRevision:String}>;
	final callSource:Null<OcamlLoweredSourceSpan>;
};

/** A callback write retains its source, body, storage references, and validated adapter. */
typedef CallableViewLocalReport = {
	final id:String;
	final revision:String;
	final role:OcamlLocalConversionRole;
	final source:OcamlLoweredSourceSpan;
	final binding:OcamlFunctionPlanBinding;
	final input:CallableViewInputReport;
	final output:OcamlLocalRepresentationReference;
	final adapter:CallableViewAdapterReport;
};

/** Snapshot an actual sealed decision before exposing plain report fields. */
function localToReport(decision:OcamlCallableViewLocalDecision):CallableViewLocalReport {
	final selected = copy(decision);
	return {
		id: selected.id,
		revision: selected.revision,
		role: selected.role,
		source: selected.source,
		binding: selected.binding,
		input: inputToReport(selected.input),
		output: selected.output,
		adapter: adapterToReport(selected.inputLayout, selected.outputLayout, selected.conversion)
	};
}

/** Preserve the actual source producer without inventing local storage for a call or method. */
function inputToReport(input:OcamlCallableViewInput):CallableViewInputReport {
	return switch (copyInput(input)) {
		case ExistingView(reference): {
				kind: Existing,
				reference: reference,
				calleeId: null,
				declaration: null,
				callSource: null
			};
		case RawOrigin(FreshLiteral): {
				kind: Literal,
				reference: null,
				calleeId: null,
				declaration: null,
				callSource: null
			};
		case RawOrigin(StaticDeclaration(calleeId)): {
				kind: Declaration,
				reference: null,
				calleeId: calleeId,
				declaration: null,
				callSource: null
			};
		case DeclaredOrigin(declaration): {
				kind: Published,
				reference: null,
				calleeId: declaration.calleeId,
				declaration: {programRevision: declaration.programRevision, pipelineRevision: declaration.pipelineRevision},
				callSource: null
			};
		case CallResult(source): {
				kind: Call,
				reference: null,
				calleeId: null,
				declaration: null,
				callSource: source
			};
	};
}

/** Decode a complete occurrence, then reuse the compiler's source-bound decision validation. */
function localFromReport(value:Dynamic):OcamlCallableViewLocalDecision {
	requireFields(value, ["id", "revision", "role", "source", "binding", "input", "output", "adapter"]);
	final adapter = adapterFromReport(Reflect.field(value, "adapter"));
	final result:OcamlCallableViewLocalDecision = {
		id: text(Reflect.field(value, "id")),
		revision: text(Reflect.field(value, "revision")),
		role: text(Reflect.field(value, "role")),
		source: readSource(Reflect.field(value, "source")),
		binding: readBinding(Reflect.field(value, "binding")),
		input: inputFromReport(Reflect.field(value, "input"), adapter.input),
		output: readReference(Reflect.field(value, "output")),
		inputLayout: adapter.input,
		outputLayout: adapter.output,
		conversion: adapter.conversion
	};
	requireDecision(result);
	return result;
}

/** Decode only the selected producer tag and the fields permitted for that tag. */
function inputFromReport(input:Dynamic, layout:OcamlCallableViewDescriptor):OcamlCallableViewInput {
	validate(layout);
	requireFields(input, ["kind", "reference", "calleeId", "declaration", "callSource"]);
	final kind = text(Reflect.field(input, "kind"));
	final reference:Dynamic = Reflect.field(input, "reference");
	final callee:Dynamic = Reflect.field(input, "calleeId");
	final declaration:Dynamic = Reflect.field(input, "declaration");
	final callSource:Dynamic = Reflect.field(input, "callSource");
	return switch (kind) {
		case "existing-view" if (callee == null && declaration == null && callSource == null): ExistingView(readReference(reference));
		case "fresh-literal" if (reference == null && callee == null && declaration == null && callSource == null): RawOrigin(FreshLiteral);
		case "static-declaration" if (reference == null && declaration == null && callSource == null): RawOrigin(StaticDeclaration(text(callee)));
		case "published-declaration" if (reference == null && callSource == null):
			requireFields(declaration, ["programRevision", "pipelineRevision"]);
			DeclaredOrigin({
				calleeId: text(callee),
				layout: describe(layout.shape),
				programRevision: text(Reflect.field(declaration, "programRevision")),
				pipelineRevision: text(Reflect.field(declaration, "pipelineRevision"))
			});
		case "call-result" if (reference == null && callee == null && declaration == null):
			CallResult(readSource(callSource));
		case _: throw "Callback report has a conflicting or unsupported producer.";
	};
}

/** Source locations are diagnostic positions; final-body joins establish ownership. */
function readSource(value:Dynamic):OcamlLoweredSourceSpan {
	requireFields(value, ["file", "min", "max"]);
	final source:OcamlLoweredSourceSpan = {
		file: text(Reflect.field(value, "file")),
		min: integer(Reflect.field(value, "min")),
		max: integer(Reflect.field(value, "max"))
	};
	if (source.file.length == 0 || source.min < 0 || source.max < source.min)
		throw "Callback report has an invalid source position.";
	return source;
}

/** Narrow a report reference; the owning decision/inventory validates its registered identity. */
function readReference(value:Dynamic):OcamlLocalRepresentationReference {
	requireFields(value, [
		"localId",
		"representationId",
		"representationRevision",
		"semanticTypeId",
		"domain"
	]);
	return {
		localId: text(Reflect.field(value, "localId")),
		representationId: text(Reflect.field(value, "representationId")),
		representationRevision: text(Reflect.field(value, "representationRevision")),
		semanticTypeId: text(Reflect.field(value, "semanticTypeId")),
		domain: text(Reflect.field(value, "domain"))
	};
}

/** The full compiler context is explicit even when two functions have the same local shape. */
function readBinding(value:Dynamic):OcamlFunctionPlanBinding {
	requireFields(value, ["functionId", "programRevision", "bodyRevision", "pipelineRevision"]);
	return {
		functionId: text(Reflect.field(value, "functionId")),
		programRevision: text(Reflect.field(value, "programRevision")),
		bodyRevision: text(Reflect.field(value, "bodyRevision")),
		pipelineRevision: text(Reflect.field(value, "pipelineRevision"))
	};
}

private function integer(value:Dynamic):Int {
	if (!Std.isOfType(value, Int))
		throw "Callback report requires an Int source position.";
	return value;
}

/** Plain JSON fields for one directional callback adapter, independent of its source occurrence. */
typedef CallableViewAdapterReport = {
	final input:ReportNode;
	final output:ReportNode;
	final inputRevision:String;
	final outputRevision:String;
	final conversion:ReportNode;
};

/** Validated layouts and conversion; the owning occurrence still supplies storage and body authority. */
typedef CallableViewAdapter = {
	final input:OcamlCallableViewDescriptor;
	final output:OcamlCallableViewDescriptor;
	final conversion:OcamlGenericValueConversion;
};

/** Publish only a conversion derived from the exact input and output layouts. */
function adapterToReport(input:OcamlCallableViewDescriptor, output:OcamlCallableViewDescriptor,
		conversion:OcamlGenericValueConversion):CallableViewAdapterReport {
	requireAdapter(input, output, conversion);
	return {
		input: callableShapeToReport(input.shape),
		output: callableShapeToReport(output.shape),
		inputRevision: input.revision,
		outputRevision: output.revision,
		conversion: conversionToReport(conversion)
	};
}

/**
	Narrow untrusted JSON before interpreting a callback conversion.

	Dynamic is confined to this decoder. Exact fields, recursive node syntax,
	layout revisions, and conversion direction are checked before typed values
	leave it. This validates the adapter, not a producer, local, or runtime grant.
**/
function adapterFromReport(value:Dynamic):CallableViewAdapter {
	final expected = ["input", "output", "inputRevision", "outputRevision", "conversion"];
	if (Type.typeof(value) != TObject)
		throw "Callback adapter report requires a plain object.";
	final fields = Reflect.fields(value);
	if (fields.length != expected.length || Lambda.exists(fields, name -> !expected.contains(name)))
		throw "Callback adapter report has missing or unexpected fields.";
	final input = describe(callableShapeFromReport(Reflect.field(value, "input")));
	final output = describe(callableShapeFromReport(Reflect.field(value, "output")));
	if (Reflect.field(value, "inputRevision") != input.revision || Reflect.field(value, "outputRevision") != output.revision)
		throw "Callback adapter report has a stale layout revision.";
	final conversion = conversionFromReport(Reflect.field(value, "conversion"));
	requireAdapter(input, output, conversion);
	return {input: input, output: output, conversion: conversion};
}

private function requireAdapter(input:OcamlCallableViewDescriptor, output:OcamlCallableViewDescriptor, conversion:OcamlGenericValueConversion):Void {
	validate(input);
	validate(output);
	final expected = crossing(input.shape, output.shape);
	if (expected == null || Std.string(expected) != Std.string(conversion))
		throw "Callback adapter report disagrees with its directional layout conversion.";
}
