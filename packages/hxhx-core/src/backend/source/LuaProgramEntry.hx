package backend.source;

/** Exact entry projections let Lua consume runtime-type catalogs without the legacy declaration-only adapter. */
typedef LuaProgramEntry = {
	final module:TypedBackendModuleProjection;
	final cls:TypedBackendClassProjection;
	final main:TypedBackendFunctionProjection;
};

/** Preserve the source backend's main selection order while keeping the owning immutable objects. */
function find(program:backend.GenIrProgram, requested:Null<String>):Null<LuaProgramEntry> {
	final wanted = requested == null ? "" : requested;
	var fallback:Null<LuaProgramEntry> = null;
	for (typed in program.getTypedModules()) {
		final module = typed.getBackendProjection();
		final pkg = HxModuleDecl.getPackagePath(module.getDeclaration());
		for (cls in module.getClasses()) {
			final name = HxClassDecl.getName(cls.getDeclaration());
			final fullName = pkg.length == 0 ? name : pkg + "." + name;
			for (main in cls.getFunctions()) {
				final declaration = main.getDeclaration();
				if (!HxFunctionDecl.getIsStatic(declaration) || HxFunctionDecl.getName(declaration) != "main")
					continue;
				final found:LuaProgramEntry = {module: module, cls: cls, main: main};
				if (fallback == null)
					fallback = found;
				if (wanted.length == 0 || wanted == name || wanted == fullName)
					return found;
			}
		}
	}
	return fallback;
}
