package reflaxe.ocaml.reports;

import reflaxe.ocaml.lowered.OcamlCallableViewRepresentation;
import reflaxe.ocaml.lowered.OcamlCallableViewRepresentation.OcamlCallableViewDescriptor;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion.OcamlGenericValueConversion;
import reflaxe.ocaml.reports.OcamlGenericCallReport;
import reflaxe.ocaml.reports.OcamlGenericCallReport.ReportNode;

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
