package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.macro.Type.ClassType;
import haxe.macro.Type.MethodKind;
import haxe.macro.TypeTools;
import reflaxe.ocaml.CompilationContext;
import reflaxe.ocaml.lowered.OcamlMonomorphicClassRepresentation.OcamlMonomorphicClassField;

/**
	Selects the first exact nominal class layouts from the complete typed program.

	A class is admitted only when the whole program proves that ordinary record
	typing is sufficient: there is no base class, subclass, interface, generic
	parameter, extern/native boundary, or dynamic method. Every stored field must
	already have a program representation decision of its own.
**/
class OcamlMonomorphicClassPlanner {
	/** Registers every eligible user-class layout in deterministic module order. */
	public static function plan(moduleOrder:Array<String>, classesByModule:Map<String, Array<ClassType>>, context:CompilationContext,
			representations:OcamlRepresentationRegistry, isUserClass:ClassType->Bool):Void {
		for (moduleId in moduleOrder) {
			final classes = classesByModule.get(moduleId);
			if (classes == null)
				continue;
			for (classType in classes) {
				if (!isCandidate(classType, context, isUserClass))
					continue;
				final fields:Array<OcamlMonomorphicClassField> = [];
				var supported = true;
				var declarationOrder = 0;
				for (field in classType.fields.get()) {
					switch (field.kind) {
						case FVar(_, _):
							final fieldRepresentation = representations.selectAdmittedInstanceField(field.type);
							if (fieldRepresentation == null) {
								supported = false;
								break;
							}
							fields.push({
								sourceFieldName: field.name,
								targetFieldName: context.ocamlRecordLabel(field.name),
								semanticTypeId: TypeTools.toString(field.type),
								carrierTypeId: fieldRepresentation.carrierTypeId,
								representationId: fieldRepresentation.id,
								declarationOrder: declarationOrder
							});
							declarationOrder += 1;
						case FMethod(_):
					}
				}
				if (!supported)
					continue;
				representations.registerMonomorphicClass({
					semanticTypeId: fullName(classType),
					sourceModuleId: classType.module,
					sourceTypeName: classType.name,
					targetModuleName: context.ocamlModuleNameForModuleId(classType.module),
					targetTypeName: context.scopedInstanceTypeName(classType.module, classType.name),
					fields: fields
				});
			}
		}
	}

	static function isCandidate(classType:ClassType, context:CompilationContext, isUserClass:ClassType->Bool):Bool {
		if (!isUserClass(classType)
			|| classType.isExtern
			|| classType.isInterface
			|| classType.meta.has(":native")
			|| classType.params.length > 0
			|| classType.superClass != null
			|| (classType.interfaces != null && classType.interfaces.length > 0)
			|| context.dispatchTypes.exists(fullName(classType))) {
			return false;
		}
		for (field in classType.fields.get()) {
			if (field.meta.has(":native"))
				return false;
			switch (field.kind) {
				case FMethod(MethodKind.MethDynamic):
					return false;
				case _:
			}
		}
		return true;
	}

	static function fullName(classType:ClassType):String {
		return (classType.pack ?? []).concat([classType.name]).join(".");
	}
}
#end
