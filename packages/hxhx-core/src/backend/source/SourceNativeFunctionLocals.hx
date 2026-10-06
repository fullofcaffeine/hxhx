package backend.source;

/** Immutable inputs for one Java or C# function's local declaration rendering. */
typedef SourceNativeFunctionLocalInput = {
	final target:SourceNativeTarget;
	final program:backend.GenIrProgram;
	final projection:TypedBackendFunctionProjection;
	final noRoot:Bool;
};

/**
	Render declarations that native `var` cannot infer, using exact typed locals.

	An absent initializer stays absent so Java and C# still check definite
	assignment. A written null remains an initializer. Nominal names come from
	the exact provider declaration; a Haxe module segment is not a target package.
	This object belongs to one function and is carried through its child blocks.
**/
@:access(backend.source.SourceTargetCommon)
class SourceNativeFunctionLocals {
	public final target:SourceNativeTarget;

	final program:backend.GenIrProgram;
	final projection:TypedBackendFunctionProjection;
	final noRoot:Bool;

	public function new(input:SourceNativeFunctionLocalInput) {
		if (input.target != Java && input.target != Cs)
			throw "native local declarations require Java or C#";
		var found = false;
		for (module in input.program.getTypedModules())
			for (owner in module.getBackendProjection().getClasses())
				for (body in owner.getFunctions())
					if (body == input.projection)
						found = true;
		if (!found)
			throw "native local declarations require the exact program function projection";
		target = input.target;
		program = input.program;
		projection = input.projection;
		noRoot = input.noRoot;
	}

	/** Preserve the distinction between no initializer and an explicit null expression. */
	public function declaration(name:String, hasNullInitializer:Bool):String {
		final local = projection.getLocalCatalog().findByProjectedName(name);
		if (local == null)
			throw "native local declaration is absent from its typed catalog: " + name;
		final type = local.getBinding().getType();
		final nativeName = target == Java ? SourceTargetCommon.sanitizeJavaIdentifier(name) : SourceTargetCommon.sanitizeCsIdentifier(name);
		return typeName(type) + " " + nativeName + (hasNullInitializer ? " = null;" : ";");
	}

	function typeName(type:TyType):String {
		final nullable = type.isNullable();
		final inner = type.unwrapNull();
		return switch (inner.getSemanticKey()) {
			case "primitive:Int": target == Java ? (nullable ? "Integer" : "int") : (nullable ? "int?" : "int");
			case "primitive:Float": target == Java ? (nullable ? "Double" : "double") : (nullable ? "double?" : "double");
			case "primitive:Bool": target == Java ? (nullable ? "Boolean" : "boolean") : (nullable ? "bool?" : "bool");
			case "primitive:String": target == Java ? "String" : "string";
			case "dynamic": target == Java ? "Object" : "dynamic";
			case _:
				final identity = inner.getNominalIdentity();
				if (identity == null)
					throw "native local declaration has no supported target type: " + type.getSemanticKey();
				nominalName(identity);
		};
	}

	/** Select the emitted class by semantic identity, including secondary types and import aliases. */
	function nominalName(identity:TyNominalTypeId):String {
		for (module in program.getTypedModules())
			for (owner in module.getTypedClasses()) {
				final info = owner.getSemanticInfo();
				if (info != null && info.getIdentity().equals(identity)) {
					if (!Std.isOfType(info, TyClassInfo) || info.getIsEnum())
						throw "native local declaration requires the target representation of " + identity.getCanonicalName();
					final packagePath = module.getEnv().getPackagePath();
					final className = HxClassDecl.getName(owner.getSourceDeclaration());
					return target == Java ? SourceTargetCommon.javaQualifiedClassName(packagePath,
						className) : SourceTargetCommon.csGlobalClassRef(packagePath, className, noRoot);
				}
			}
		throw "native local declaration cannot find its exact provider: " + identity.getCanonicalName();
	}
}
