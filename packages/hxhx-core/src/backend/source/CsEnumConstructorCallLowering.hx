package backend.source;

private typedef CsExactEnumConstructorTarget = {
	final owner:String;
	final modulePath:String;
	final declaration:String;
	final packagePath:String;
	final className:String;
	final constructor:String;
};

typedef CsEnumConstructorCall = {
	final packagePath:String;
	final className:String;
	final constructor:String;
	final noRoot:Bool;
	final arguments:Array<HxExpr>;
};

/**
	Translate already-selected Haxe enum constructors into explicit C# calls.

	The typer records the exact declaration identity in the source-shaped
	projection. One request-owned catalog maps that identity to the C# class
	which will be emitted. This lowering validates both sides and replaces the
	generic marker with a target marker, so recursive rendering never repeats
	Haxe lookup from a constructor name or process-global map.
**/
class CsEnumConstructorCallLowering {
	final constructors:haxe.ds.StringMap<CsExactEnumConstructorTarget>;
	final noRoot:Bool;

	public function new(program:backend.GenIrProgram, noRoot:Bool) {
		if (program == null)
			throw "C# enum-constructor lowering requires a typed program";
		this.noRoot = noRoot;
		this.constructors = new haxe.ds.StringMap<CsExactEnumConstructorTarget>();
		for (typedModule in program.getTypedModules()) {
			final moduleDecl = typedModule.getBackendDeclaration();
			final packagePath = HxModuleDecl.getPackagePath(moduleDecl);
			for (typedClass in typedModule.getTypedClasses()) {
				final semanticInfo = typedClass.getSemanticInfo();
				if (semanticInfo == null || !semanticInfo.getIsEnum())
					continue;
				final sourceClass = typedClass.getSourceDeclaration();
				for (typedFunction in typedClass.getFunctions()) {
					final declaration = typedFunction.getDeclaration();
					if (declaration == null || !declaration.getIsEnumConstructor())
						continue;
					if (!declaration.getOwner().equals(semanticInfo.getIdentity()))
						throw "typed enum constructor owner disagrees with its containing enum";
					if (declaration.getModulePath() != semanticInfo.getModulePath())
						throw "typed enum constructor module disagrees with its containing enum";
					final key = declaration.getIdentity().getCanonicalKey();
					final target:CsExactEnumConstructorTarget = {
						owner: declaration.getOwner().getCanonicalName(),
						modulePath: declaration.getModulePath(),
						declaration: key,
						packagePath: packagePath,
						className: HxClassDecl.getName(sourceClass),
						constructor: HxFunctionDecl.getName(typedFunction.getSourceDeclaration())
					};
					final existing = constructors.get(key);
					if (existing != null
						&& (existing.owner != target.owner
							|| existing.modulePath != target.modulePath
							|| existing.className != target.className
							|| existing.constructor != target.constructor))
						throw "C# enum-constructor catalog contains conflicting exact declaration " + key;
					constructors.set(key, target);
				}
			}
		}
	}

	public static inline function marker():String
		return "$hxhx:cs-exact-enum-constructor";

	public static inline function isMarker(value:String):Bool
		return value == marker();

	public static function decode(expression:HxExpr):Null<CsEnumConstructorCall> {
		return switch (expression) {
			case ECall(EUnsupported(value), [
				EString(packagePath),
				EString(className),
				EString(constructor),
				EBool(noRoot),
				EArrayDecl(arguments)
			]) if (isMarker(value)):
				if (className.length == 0 || constructor.length == 0)
					throw "C# enum-constructor marker has an incomplete target identity";
				{
					packagePath: packagePath,
					className: className,
					constructor: constructor,
					noRoot: noRoot,
					arguments: arguments.copy()
				};
			case _:
				null;
		};
	}

	public function body(projection:TypedBackendFunctionProjection):Array<HxStmt> {
		if (projection == null)
			throw "C# enum-constructor lowering requires a typed function projection";
		final dynamicCalls = CsDynamicLocalCallLowering.body(projection);
		return SourceFunctionBodyRewriter.body(dynamicCalls, function(expression) {
			final exact = TypedExactEnumConstructorSource.decode(expression);
			if (exact == null)
				return expression;
			final target = constructors.get(exact.declaration);
			if (target == null)
				throw "C# enum-constructor lowering cannot resolve exact declaration " + exact.declaration;
			if (target.owner != exact.owner || target.modulePath != exact.modulePath || target.constructor != exact.constructor)
				throw "C# enum-constructor marker disagrees with exact declaration " + exact.declaration;
			return ECall(EUnsupported(marker()), [
				EString(target.packagePath),
				EString(target.className),
				EString(target.constructor),
				EBool(noRoot),
				EArrayDecl(exact.arguments.copy())
			]);
		});
	}
}
