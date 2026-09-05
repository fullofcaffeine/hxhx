package reflaxe.ocaml.target;

#if (macro || reflaxe_runtime)
import haxe.macro.Type;
import haxe.macro.TypeTools;
import reflaxe.ocaml.target.OcamlTargetFieldInitializerFact.OcamlTargetFieldInitializerRole;
import reflaxe.ocaml.target.OcamlTargetFieldInitializerFact.OcamlTargetFieldInitializerSignature;
#end

/** Copies admitted stock-Haxe field initializers before preprocessing. **/
class HaxeOcamlTargetFieldInitializerAdapter {
	#if (macro || reflaxe_runtime)
	public static function captureModuleTypes(moduleTypes:Array<ModuleType>, catalog:OcamlTargetFieldInitializerCatalog):Int {
		if (catalog == null)
			throw "stock Haxe target field capture requires a request catalog";
		catalog.beginRequest();
		var captured = 0;
		for (moduleType in moduleTypes)
			switch (moduleType) {
				case TClassDecl(reference):
					final classType = reference.get();
					for (field in classType.statics.get()) {
						final initializer = field.expr();
						if (initializer == null)
							continue;
						final fact = fromSourceBeforePreprocessing(classType, field, initializer);
						if (fact != null) {
							catalog.register(hostFieldId(classType, field), fact);
							captured++;
						}
					}
				case _:
			}
		return captured;
	}

	public static function fromSourceBeforePreprocessing(classType:ClassType, field:ClassField, initializer:TypedExpr):Null<OcamlTargetFieldInitializerFact> {
		if (classType == null || field == null || initializer == null)
			throw "stock Haxe target field adapter requires complete typed facts";
		final typeDisplay = TypeTools.toString(field.type);
		if (typeDisplay != "Int" && typeDisplay != "Bool" && typeDisplay != "String")
			return null;
		final signature:OcamlTargetFieldInitializerSignature = {
			moduleId: classType.module,
			sourceTypeName: classType.name,
			sourceFieldName: field.name,
			role: OcamlTargetFieldInitializerRole.StaticField,
			semanticTypeDisplay: typeDisplay
		};
		final targetExpression = HaxeOcamlTargetExpressionAdapter.fromSourceBeforePreprocessing(OcamlTargetFieldInitializerFact.identityFor(signature),
			initializer);
		return targetExpression == null
			|| targetExpression.semanticTypeDisplay != typeDisplay ? null : new OcamlTargetFieldInitializerFact(signature, targetExpression);
	}

	public static function hostFieldId(classType:ClassType, field:ClassField):String
		return classType.module + "|" + classType.name + "::" + field.name;
	#end
}
