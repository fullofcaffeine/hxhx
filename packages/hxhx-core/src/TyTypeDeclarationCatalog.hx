import haxe.ds.StringMap;
import TyTypeDeclaration.TyTypeResolutionContext;

/**
	Look up source declarations before deciding whether they denote classes.

	Local declarations precede imports, enclosing packages, and StdTypes. The
	catalog never searches unrelated modules for a globally unique short name.
	Static-member consumers must separately require a nominal provider.
 */
class TyTypeDeclarationCatalog {
	final byName = new StringMap<TyTypeDeclaration>();
	final byModule = new StringMap<Array<TyTypeDeclaration>>();

	public function new() {}

	public function get(canonicalName:String):Null<TyTypeDeclaration>
		return byName.get(canonicalName);

	public function add(declaration:TyTypeDeclaration):Void {
		final key = declaration.getCanonicalName();
		// Re-registering an already loaded header must not replace retained identities.
		if (byName.exists(key))
			return;
		byName.set(key, declaration);
		final module = declaration.getModulePath();
		if (!byModule.exists(module))
			byModule.set(module, []);
		byModule.get(module).push(declaration);
	}

	function visible(declaration:Null<TyTypeDeclaration>, module:String):Bool
		return declaration != null && (declaration.getVisibility() == Public || declaration.getModulePath() == module);

	function moduleMember(module:String, name:String, currentModule:String):Null<TyTypeDeclaration> {
		if (!byModule.exists(module))
			return null;
		for (declaration in byModule.get(module))
			if (declaration.getShortName() == name && visible(declaration, currentModule))
				return declaration;
		return null;
	}

	public function resolve(path:String, context:TyTypeResolutionContext):Null<TyTypeDeclaration> {
		final raw = StringTools.trim(path);
		if (raw.length == 0)
			return null;
		if (raw.indexOf(".") >= 0) {
			final exact = get(raw);
			if (visible(exact, context.modulePath))
				return exact;
		}
		final local = moduleMember(context.modulePath, raw, context.modulePath);
		if (local != null)
			return local;
		for (offset in 0...context.directives.length) {
			final directive = context.directives[context.directives.length - 1 - offset];
			final importedPath = HxModuleDirective.getPath(directive);
			switch (HxModuleDirective.getKind(directive)) {
				case ImportNormal | ImportAlias(_):
					if (HxModuleDirective.getImportedLocalName(directive) == raw) {
						final selected = get(importedPath);
						if (visible(selected, context.modulePath))
							return selected;
					}
					if (HxModuleDirective.getKind(directive).match(ImportNormal)) {
						final secondary = moduleMember(importedPath, raw, context.modulePath);
						if (secondary != null)
							return secondary;
					}
				case ImportAll:
					// A type wildcard exposes static members, not sibling types.
					if (get(importedPath) == null) {
						final selected = get(importedPath + "." + raw);
						if (visible(selected, context.modulePath))
							return selected;
					}
				case Using:
			}
		}
		var enclosingPackage = context.packagePath;
		while (enclosingPackage.length > 0) {
			final selected = get(enclosingPackage + "." + raw);
			if (visible(selected, context.modulePath))
				return selected;
			final dot = enclosingPackage.lastIndexOf(".");
			enclosingPackage = dot < 0 ? "" : enclosingPackage.substr(0, dot);
		}
		final root = get(raw);
		if (visible(root, context.modulePath))
			return root;
		return moduleMember("StdTypes", raw, context.modulePath);
	}
}
