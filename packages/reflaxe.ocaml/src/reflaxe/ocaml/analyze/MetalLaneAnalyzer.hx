package reflaxe.ocaml.analyze;

#if macro
import haxe.macro.Context;
import haxe.macro.Type;
#end

/**
	Collects Stage0 portable-lane metal-island declarations.

	Policy:
	- Canonical metadata is `@:haxeMetal`.
	- Legacy aliases are rejected (hard cutover).
**/
class MetalLaneAnalyzer {
	#if macro
	public static function collectModuleSet(moduleTypes:Array<ModuleType>):Map<String, Bool> {
		final out:Map<String, Bool> = [];
		for (moduleType in moduleTypes) {
			switch (moduleType) {
				case TClassDecl(classRef):
					final classType = classRef.get();
					if (hasHaxeMetalMetadata(classType.meta))
						out.set(moduleNameForClass(classType), true);
					collectFieldMetadata(classType.module, classType.fields.get(), out);
					collectFieldMetadata(classType.module, classType.statics.get(), out);
				case TEnumDecl(enumRef):
					final enumType = enumRef.get();
					if (hasHaxeMetalMetadata(enumType.meta))
						out.set(moduleNameForEnum(enumType), true);
				case TTypeDecl(typeRef):
					final typeDecl = typeRef.get();
					if (hasHaxeMetalMetadata(typeDecl.meta))
						out.set(moduleNameForTypedef(typeDecl), true);
				case TAbstract(abstractRef):
					final abstractType = abstractRef.get();
					if (hasHaxeMetalMetadata(abstractType.meta))
						out.set(moduleNameForAbstract(abstractType), true);
					if (abstractType.impl != null) {
						final impl = abstractType.impl.get();
						if (impl != null) {
							collectFieldMetadata(abstractType.module, impl.fields.get(), out);
							collectFieldMetadata(abstractType.module, impl.statics.get(), out);
						}
					}
			}
		}
		return out;
	}

	static function collectFieldMetadata(defaultModule:Null<String>, fields:Array<ClassField>, out:Map<String, Bool>):Void {
		if (fields == null)
			return;
		for (field in fields) {
			if (field == null || field.meta == null)
				continue;
			if (!hasHaxeMetalMetadata(field.meta))
				continue;
			final moduleName = normalizeModuleLabel(defaultModule);
			out.set(moduleName, true);
		}
	}

	static function hasHaxeMetalMetadata(meta:MetaAccess):Bool {
		if (meta == null)
			return false;
		for (entry in meta.get()) {
			final name = entry.name;
			if (name == ":haxeMetal" || name == "haxeMetal")
				return true;
			if (name == ":ocamlMetal" || name == "ocamlMetal" || name == ":reflaxeMetal" || name == "reflaxeMetal") {
				Context.error("Unsupported metal-lane metadata `" + name + "`. Use `@:haxeMetal`.", entry.pos);
			}
		}
		return false;
	}

	static function normalizeModuleLabel(moduleName:Null<String>):String {
		if (moduleName != null && moduleName.length > 0)
			return moduleName;
		return "<unknown>";
	}

	static function moduleNameForClass(classType:ClassType):String {
		return normalizeModuleLabel(classType.module);
	}

	static function moduleNameForAbstract(abstractType:AbstractType):String {
		return normalizeModuleLabel(abstractType.module);
	}

	static function moduleNameForEnum(enumType:EnumType):String {
		return normalizeModuleLabel(enumType.module);
	}

	static function moduleNameForTypedef(typeDecl:DefType):String {
		return normalizeModuleLabel(typeDecl.module);
	}
	#end
}
