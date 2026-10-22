package backend.source;

/**
	Select the runtime enum tag from the exact typed declaration in this program.
	Python and Lua retain the parser's raw declaration tag; C# emits its sanitized
	class name. Reject colliding tags rather than matching a different enum with
	the same constructor spelling. PHP has its own checked naming catalog.
 */
@:access(backend.source.SourceTargetCommon)
function requireName(program:backend.GenIrProgram, identity:TyNominalTypeId, target:SourceNativeTarget):String {
	if (target == Php || target == Java)
		throw "this source enum representation requires its target-specific declaration adapter";
	var selected:Null<String> = null;
	final owners = new haxe.ds.StringMap<String>();
	for (module in program.getTypedModules())
		for (owner in module.getTypedClasses()) {
			final info = owner.getSemanticInfo();
			if (info == null || !info.getIsEnum())
				continue;
			final raw = HxClassDecl.getName(owner.getSourceDeclaration());
			final name = target == Cs ? SourceTargetCommon.sanitizeCsIdentifier(raw) : raw;
			final canonical = info.getIdentity().getCanonicalName();
			final previous = owners.get(name);
			if (previous != null && previous != canonical)
				throw "source enum runtime tag is shared by distinct declarations: " + name;
			owners.set(name, canonical);
			if (info.getIdentity().equals(identity))
				selected = name;
		}
	if (selected == null)
		throw "source enum pattern has no exact emitted declaration: " + identity.getCanonicalName();
	return selected;
}
