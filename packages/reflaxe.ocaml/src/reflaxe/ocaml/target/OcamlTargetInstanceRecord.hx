package reflaxe.ocaml.target;

import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.ast.OcamlRecordField;
import reflaxe.ocaml.ast.OcamlTypeDecl;
import reflaxe.ocaml.ast.OcamlTypeExpr;
import reflaxe.ocaml.ast.OcamlTypeRecordField;

/** Target record members after the class owner selects inheritance, dispatch and field carriers. **/
typedef OcamlTargetInstanceRecordInput = {
	final typeName:String;
	final fields:Array<OcamlTypeRecordField>;
}

/** Values for that exact layout; the marker must come from the checked class-marker operation. **/
typedef OcamlTargetInstanceRecordValues = {
	final declaration:OcamlTypeDecl;
	final classMarker:OcamlExpr;
	final fields:Array<OcamlRecordField>;
}

/**
	Declare the common Haxe instance representation with its runtime marker first.

	Every class uses the same first slot so runtime reflection and checked upcasts
	can recover its most-derived class. Remaining slots retain the class owner's
	order and represented types, including inherited fields and dispatch methods.
	This operation does not choose field defaults or execute authored initializers.
**/
function declareInstanceRecord(input:OcamlTargetInstanceRecordInput):OcamlTypeDecl {
	if (input == null || input.typeName == null || StringTools.trim(input.typeName).length == 0 || input.fields == null)
		throw "OCaml instance record requires its type name and complete member inventory";
	final fields:Array<OcamlTypeRecordField> = [{name: "__hx_type", isMutable: false, typ: OcamlTypeExpr.TIdent("Obj.t")}];
	final names:Map<String, Bool> = ["__hx_type" => true];
	for (field in input.fields) {
		if (field == null || field.name == null || field.name.length == 0 || field.typ == null || names.exists(field.name))
			throw "OCaml instance record requires distinct named members after its runtime marker";
		names.set(field.name, true);
		fields.push({name: field.name, isMutable: field.isMutable, typ: field.typ});
	}
	return {name: input.typeName, params: [], kind: Record(fields)};
}

/**
	Build values in the declared slot order and annotate the exact nominal type.

	Constructor and empty-instance allocation use this same operation with their
	separate checked markers and storage defaults. Authored initialization remains
	in the constructor body. Reject a lost or reordered slot before producing syntax;
	otherwise a subclass upcast could read a different field from the same record.
**/
function initializeInstanceRecord(input:OcamlTargetInstanceRecordValues):OcamlExpr {
	if (input == null || input.declaration == null || input.classMarker == null || input.fields == null)
		throw "OCaml instance initialization requires a declaration, marker and values";
	final declaration = input.declaration;
	final fields = switch (declaration.kind) {
		case Record(fields): fields;
		case _: throw "OCaml instance initialization requires a record declaration";
	};
	if (declaration.name == null
		|| declaration.name.length == 0
		|| declaration.params.length != 0
		|| fields.length != input.fields.length + 1)
		throw "OCaml instance initialization does not match its declared member inventory";
	final header = fields[0];
	final headerType = switch (header.typ) {
		case TIdent("Obj.t"): true;
		case _: false;
	};
	if (header.name != "__hx_type" || header.isMutable || !headerType)
		throw "OCaml instance initialization requires the runtime marker in its first slot";
	final values:Array<OcamlRecordField> = [{name: "__hx_type", value: input.classMarker}];
	for (index in 0...input.fields.length) {
		final field = input.fields[index];
		if (field == null || field.value == null || field.name != fields[index + 1].name)
			throw "OCaml instance initialization does not match its declared member order";
		values.push({name: field.name, value: field.value});
	}
	return OcamlExpr.EAnnot(OcamlExpr.ERecord(values), OcamlTypeExpr.TIdent(declaration.name));
}
