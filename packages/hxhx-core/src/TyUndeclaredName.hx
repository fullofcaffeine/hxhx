/**
	Report names that upstream Haxe rejects because nothing declares them.

	Why
	- The bring-up typer gave an unresolved title-case name such as `Run` the
	  type String (a legacy enum-tag path), and typed `Nope.foo()` on an
	  unknown receiver as an unknown value. A program that upstream rejects
	  therefore passed `--no-output` and failed later, or never
	  (haxe_ocaml-db83a, haxe_ocaml-ikrmd).

	What
	- `namesType` is true when the name resolves to a declared type or type
	  alias in the current module context.
	- `recordValueName` records a title-case value name that resolves to
	  nothing; `TyUndeclaredValueNames` reports it after the module is typed,
	  unless an expected type selected it or a loaded enum or abstract declares
	  it. Upstream resolves such a name from the expected type
	  (`node.nodeType != Element`), which this typer does not always carry.
	- `requireStaticReceiver` rejects `Nope.foo` and `Nope.foo()` with upstream's
	  "Type not found : Nope" when the bare title-case receiver is no value, no
	  type, no import-introduced name, and no module (a module of module-level
	  functions, `CounterOps.total`, has no type of its own name). Untyped code
	  is exempt, as upstream defers it to run time.

	Only title-case bare names are checked. An unresolved lowercase name stays
	on the existing inference path for now. Both checks need a declaration
	loader: a root-only index (used by focused tests) omits the standard
	library, so a missing name there proves nothing.
**/
class TyUndeclaredName {
	public static function namesType(name:String, ctx:TyperContext):Bool {
		return ctx.resolveType(name) != null || ctx.resolveTypeDeclaration(name) != null;
	}

	/**
		Record a title-case value name that this occurrence could not resolve.
		The typer types some expressions without their expected type (for
		example a call's callee, or the body projection of each node), so the
		same name can still be selected from context by another pass. The module
		decides in `TyUndeclaredValueNames.requireDeclared` after typing.
	**/
	public static function recordValueName(name:String, scope:TyFunctionEnv, ctx:TyperContext, pos:HxPos):Void {
		if (!ctx.hasDeclarationLoader() || scope.isUntypedContext() || ctx.importsLocalName(name) || namesType(name, ctx) || runsBuildMacro(ctx)
			|| sourceImportsName(ctx, name))
			return;
		ctx.getIndex().undeclaredValueNames(ctx.getFilePath()).record(name, pos);
	}

	public static function requireStaticReceiver(receiver:HxExpr, scope:TyFunctionEnv, ctx:TyperContext, pos:HxPos,
			resolvesValue:(String, TyFunctionEnv, TyperContext, HxPos) -> Bool):Void {
		final name = switch (receiver) {
			case EIdent(value) | EEnumValue(value): value;
			case _: return;
		};
		if (!ctx.hasDeclarationLoader()
			|| scope.isUntypedContext()
			|| !isUpperStart(name)
			|| ctx.importsLocalName(name)
			|| resolvesValue(name, scope, ctx, pos)
			|| namesType(name, ctx)
			|| ctx.namesModule(name)
			|| runsBuildMacro(ctx))
			return;
		if (sourceImportsName(ctx, name) || declaredBySameFile(name, ctx))
			return;
		throw new TyperError(ctx.getFilePath(), pos, "Type not found : " + name);
	}

	/**
		Whether a type of this name is indexed under the module that the current
		file's name implies. A caller can register a source under another module
		path than its file name (`Main` for `SelectedReflection.hx`); its sibling
		types are then indexed under the file's module and still declared.
	**/
	static function declaredBySameFile(name:String, ctx:TyperContext):Bool {
		final file = ctx.getFilePath();
		if (file == null)
			return false;
		final fileModule = haxe.io.Path.withoutExtension(haxe.io.Path.withoutDirectory(file));
		for (info in ctx.getIndex().getByShortName(name)) {
			final modulePath = info.getModulePath();
			if (modulePath == fileModule || StringTools.endsWith(modulePath, "." + fileModule))
				return true;
		}
		return false;
	}

	/**
		Whether the module source imports `name` in any conditional branch. Code
		in a `#if macro` block can be typed without the directives of that block
		(the imports are filtered for the current defines), so this deliberately
		reads every branch of the raw file. An import of a loaded module that
		declares no type of that name does not count (`import pack.Ops` of a
		module of module-level functions). The text is read once per index.
	**/
	public static function sourceImportsName(ctx:TyperContext, name:String):Bool {
		final text = ctx.getIndex().rawSourceText(ctx.getFilePath());
		if (text == null)
			return false;
		for (directive in importDirectives(text))
			if (directive.local == name && !ctx.importedModuleLacksType(directive.path, name))
				return true;
		return false;
	}

	/**
		The `import` and `using` directives written anywhere in `text`, without
		regular expressions (the native EReg runtime supports a small subset).
	**/
	static function importDirectives(text:String):Array<{path:String, local:String}> {
		final out = [];
		for (keyword in ["import", "using"]) {
			var at = text.indexOf(keyword);
			while (at >= 0) {
				final before = at == 0 ? " ".code : text.charCodeAt(at - 1);
				var cursor = at + keyword.length;
				if (!isIdentifierCode(before) && cursor < text.length && isSpaceCode(text.charCodeAt(cursor))) {
					while (cursor < text.length && isSpaceCode(text.charCodeAt(cursor)))
						cursor++;
					final start = cursor;
					while (cursor < text.length && (isIdentifierCode(text.charCodeAt(cursor)) || text.charCodeAt(cursor) == ".".code))
						cursor++;
					final path = text.substring(start, cursor);
					while (cursor < text.length && isSpaceCode(text.charCodeAt(cursor)))
						cursor++;
					var local = path.substr(path.lastIndexOf(".") + 1);
					if (StringTools.startsWith(text.substr(cursor, 3), "as ")) {
						cursor += 3;
						while (cursor < text.length && isSpaceCode(text.charCodeAt(cursor)))
							cursor++;
						final aliasStart = cursor;
						while (cursor < text.length && isIdentifierCode(text.charCodeAt(cursor)))
							cursor++;
						local = text.substring(aliasStart, cursor);
					}
					if (path.length > 0 && local.length > 0)
						out.push({path: path, local: local});
				}
				at = text.indexOf(keyword, at + keyword.length);
			}
		}
		return out;
	}

	static function isIdentifierCode(code:Int):Bool
		return (code >= "a".code && code <= "z".code)
			|| (code >= "A".code && code <= "Z".code)
			|| (code >= "0".code && code <= "9".code)
			|| code == "_".code;

	static function isSpaceCode(code:Int):Bool
		return code == " ".code || code == "\t".code || code == "\n".code || code == "\r".code;

	/**
		Whether a class of this module declares a build macro (`@:build`,
		`@:autoBuild`). Such a macro can add fields that use or declare the name.
		The native in-process lane does not apply build fields yet, so reporting
		the name would blame the program for a missing macro result. The
		module is left to the build-macro owner instead.
	**/
	static function runsBuildMacro(ctx:TyperContext):Bool {
		final text = ctx.getIndex().rawSourceText(ctx.getFilePath());
		return text != null && (text.indexOf("@:build(") >= 0 || text.indexOf("@:autoBuild(") >= 0);
	}

	static function isUpperStart(name:String):Bool {
		final code = name.length == 0 ? 0 : name.charCodeAt(0);
		return code >= "A".code && code <= "Z".code;
	}
}

/**
	The title-case value names one module source left unresolved, with the
	first position of each.

	After the module is typed, a name is reported as upstream reports it
	("Unknown identifier : Run") unless some pass selected it from an expected
	enum type, or a loaded enum or abstract declares it (an enum-abstract value
	such as `Element` in `node.nodeType != Element`).
**/
class TyUndeclaredValueNames {
	final filePath:String;
	final firstPosition = new Map<String, HxPos>();
	final order = new Array<String>();
	final contextual = new Map<String, Bool>();

	public function new(filePath:String) {
		this.filePath = filePath;
	}

	public function record(name:String, pos:HxPos):Void {
		if (firstPosition.exists(name))
			return;
		firstPosition.set(name, pos);
		order.push(name);
	}

	public function markContextual(name:String):Void
		contextual.set(name, true);

	public function requireDeclared(index:TyperIndex):Void {
		final pending = order.copy();
		order.resize(0);
		for (name in pending) {
			final pos = firstPosition.get(name);
			firstPosition.remove(name);
			if (contextual.exists(name) || index.declaresEnumMember(name))
				continue;
			throw new TyperError(filePath, pos, "Unknown identifier : " + name);
		}
	}
}
