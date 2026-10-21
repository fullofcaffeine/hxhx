package reflaxe.ocaml.ast;

#if (macro || reflaxe_runtime)
import haxe.macro.Type;
import haxe.macro.TypeTools;
import reflaxe.ocaml.CompilationContext;
import reflaxe.ocaml.ast.OcamlDeclarationSignature.projectDeclarationSignature;
import reflaxe.ocaml.lowered.OcamlMethodViewConversionPlan.OcamlMethodViewConversion;
import reflaxe.ocaml.lowered.OcamlMethodDispatchProgram;
import reflaxe.ocaml.lowered.OcamlMethodDispatchSignature;
import reflaxe.ocaml.lowered.OcamlMethodDispatchSignature.selectMethodSignature;
import reflaxe.ocaml.lowered.OcamlRepresentationRegistry;

/**
	Preserves object identity after matching every required method contract.

	The source class or interface must prove the view's methods, including their
	native argument and result carriers. Program reconciliation then requires those
	entries on every retained concrete implementation. Boxing keeps the original
	record; it does not manufacture an anonymous table or copy bound methods.
**/
function buildMethodViewConversion(plan:OcamlMethodViewConversion, value:TypedExpr, context:CompilationContext, representations:OcamlRepresentationRegistry,
		program:OcamlMethodDispatchProgram, nominalType:Type->OcamlTypeExpr, build:TypedExpr->OcamlExpr):OcamlExpr {
	function signature(field:ClassField, role:String):OcamlMethodDispatchSignature {
		final method = switch (TypeTools.follow(field.type)) {
			case TFun(arguments, result): {arguments: arguments, result: result};
			case _: throw 'reflaxe.ocaml [ocaml-method-view:not-callable]: $role ${field.name} is not a method';
		};
		final native = projectDeclarationSignature(method.arguments.map(argument -> argument.t), method.result, representations, nominalType, context);
		if (native == null)
			throw 'reflaxe.ocaml [ocaml-method-view:unsupported-native-signature]: $role ${field.name}: ${TypeTools.toString(field.type)}';
		final selected = selectMethodSignature(field, native, context.ocamlModuleNameForModuleId(context.currentModuleId));
		if (selected == null)
			throw 'reflaxe.ocaml [ocaml-method-view:unsupported-source-signature]: $role ${field.name}: ${TypeTools.toString(field.type)}';
		return selected;
	}
	for (field in plan.fields) {
		final declaration = findMethod(plan.source, field.name, []);
		if (declaration == null)
			throw 'reflaxe.ocaml [ocaml-method-view:missing-source-method]: ${plan.source.module}.${plan.source.name} has no retained ${field.name} declaration';
		final wanted = signature(field, "structural view");
		final actual = signature(declaration, "source declaration");
		if (wanted.key != actual.key)
			throw 'reflaxe.ocaml [ocaml-method-view:signature-mismatch]: ${plan.source.module}.${plan.source.name}.${field.name} differs from its structural view';
		program.recordUse(plan.source, wanted);
	}
	return OcamlExpr.EApp(OcamlExpr.EIdent("Obj.repr"), [build(value)]);
}

/** Class overrides win; interface inheritance is also a declaration edge. */
private function findMethod(owner:ClassType, name:String, visited:Map<String, Bool>):Null<ClassField> {
	final identity = owner.module + ":" + owner.pack.concat([owner.name]).join(".");
	if (visited.exists(identity))
		return null;
	visited.set(identity, true);
	for (field in owner.fields.get())
		if (field.name == name)
			return field;
	if (owner.superClass != null) {
		final inherited = findMethod(owner.superClass.t.get(), name, visited);
		if (inherited != null)
			return inherited;
	}
	for (edge in owner.interfaces) {
		final inherited = findMethod(edge.t.get(), name, visited);
		if (inherited != null)
			return inherited;
	}
	return null;
}
#end
