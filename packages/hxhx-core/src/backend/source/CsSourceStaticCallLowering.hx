package backend.source;

private typedef CsSourceStaticTarget = {
	final owner:String;
	final packagePath:String;
	final className:String;
	final method:String;
};

/** The target declaration selected for a static call, with arguments in source order. */
typedef CsSourceStaticCall = {
	final packagePath:String;
	final className:String;
	final method:String;
	final noRoot:Bool;
	final arguments:Array<HxExpr>;
};

/**
	Map exact source-method identities to the classes emitted by C#.

	Haxe secondary types include their module in their identity, but C# emits
	them directly in the package. This request-owned catalog prevents restoring
	that Haxe path as a C# receiver. External methods retain their existing
	intrinsic rendering; this pass does not provide missing method bodies.
**/
@:access(backend.source.SourceTargetCommon)
class CsSourceStaticCallLowering {
	final targets = new haxe.ds.StringMap<CsSourceStaticTarget>();
	final noRoot:Bool;

	public function new(program:backend.GenIrProgram, noRoot:Bool) {
		this.noRoot = noRoot;
		for (module in program.getTypedModules()) {
			if (SourceTargetCommon.isStdSourceFile(module.getParsed().getFilePath()))
				continue;
			for (cls in module.getTypedClasses()) {
				final source = cls.getSourceDeclaration();
				if (HxClassDecl.getIsExtern(source) || SourceTargetCommon.isCompileTimeOnlySupportClass(source))
					continue;
				for (fn in cls.getFunctions()) {
					final declaration = fn.getDeclaration();
					if (declaration == null || !declaration.getIsStatic() || declaration.getIsEnumConstructor())
						continue;
					targets.set(declaration.getIdentity().getCanonicalKey(), {
						owner: declaration.getOwner().getCanonicalName(),
						packagePath: module.getEnv().getPackagePath(),
						className: HxClassDecl.getName(source),
						method: HxFunctionDecl.getName(fn.getSourceDeclaration())
					});
				}
			}
		}
	}

	/** Preserve external calls; require matching owner and method for an internal declaration. */
	public function body(statements:Array<HxStmt>):Array<HxStmt> {
		return SourceFunctionBodyRewriter.body(statements, function(expression) {
			final call = TypedExactStaticCallSource.decode(expression);
			if (call == null)
				return expression;
			final target = targets.get(call.declaration);
			if (target == null)
				return expression;
			if (target.owner != call.owner || target.method != call.method)
				throw "C# static call disagrees with its exact source declaration";
			return ECall(EUnsupported("$hxhx:cs-source-static-call"), [
				EString(target.packagePath),
				EString(target.className),
				EString(target.method),
				EBool(noRoot),
				EArrayDecl(call.arguments)
			]);
		});
	}

	public static function decode(expression:HxExpr):Null<CsSourceStaticCall> {
		return switch (expression) {
			case ECall(EUnsupported("$hxhx:cs-source-static-call"), [
				EString(packagePath),
				EString(className),
				EString(method),
				EBool(noRoot),
				EArrayDecl(arguments)
			]):
				{
					packagePath: packagePath,
					className: className,
					method: method,
					noRoot: noRoot,
					arguments: arguments
				};
			case _: null;
		};
	}
}
