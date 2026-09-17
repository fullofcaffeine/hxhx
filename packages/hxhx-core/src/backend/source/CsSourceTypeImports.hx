package backend.source;

/** One imported source class and the declaration names used by C# emission. */
typedef CsSourceTypeImport = {
	final localName:String;
	final packagePath:String;
	final className:String;
};

/**
	Select source-class aliases from resolved Haxe imports.

	A provider's Haxe identity can include its declaring module, while C# emits
	secondary classes directly in the package namespace. Match the exact typed
	identity before reading the declaration's package and class name. Later type
	imports win a local name, including when that provider is an external type.
	External runtime imports remain owned by the existing C# header renderer.
**/
function collect(program:backend.GenIrProgram, directives:Array<TyModuleDirective>):Array<CsSourceTypeImport> {
	final seen = new haxe.ds.StringMap<Bool>();
	final imports = new Array<CsSourceTypeImport>();
	for (offset in 0...directives.length) {
		final directive = directives[directives.length - 1 - offset];
		if (!directive.getKind().match(TypeImport))
			continue;
		for (provider in directive.getProviders()) {
			final localName = directive.getImportedTypeLocalName(provider);
			if (localName == null || seen.exists(localName))
				continue;
			seen.set(localName, true);
			final selected = sourceClass(program, provider, localName);
			if (selected != null)
				imports.push(selected);
		}
	}
	imports.reverse();
	return imports;
}

/** Resolve emitted declaration names without guessing package boundaries from a type path. */
@:access(backend.source.SourceTargetCommon)
private function sourceClass(program:backend.GenIrProgram, provider:TyNominalTypeId, localName:String):Null<CsSourceTypeImport> {
	for (module in program.getTypedModules()) {
		if (SourceTargetCommon.isStdSourceFile(module.getParsed().getFilePath()))
			continue;
		for (typedClass in module.getTypedClasses()) {
			final info = typedClass.getSemanticInfo();
			final source = typedClass.getSourceDeclaration();
			if (info != null
				&& !HxClassDecl.getIsExtern(source)
				&& !SourceTargetCommon.isCompileTimeOnlySupportClass(source)
				&& info.getIdentity().equals(provider))
				return {
					localName: localName,
					packagePath: module.getEnv().getPackagePath(),
					className: HxClassDecl.getName(typedClass.getSourceDeclaration())
				};
		}
	}
	return null;
}
