/**
	Detects accidental mutation of a parsed module retained by the native server.

	Haxe arrays are mutable even when the field holding them is final. The parser
	cache therefore records this deterministic structural description when it
	admits a module and rechecks it before every reuse. This is an internal
	lifecycle guard, not the cache key: exact source and parser-configuration
	identities decide whether a lookup is eligible.
**/
class ParsedModuleIntegrity {
	public static function revision(parsed:ParsedModule):String {
		if (parsed == null)
			return "parsed-module:null";
		final out = new StringBuf();
		add(out, parsed.getFilePath());
		add(out, parsed.getSource());
		addModule(out, parsed.getDecl());
		return out.toString();
	}

	static function addModule(out:StringBuf, module:HxModuleDecl):Void {
		add(out, HxModuleDecl.getPackagePath(module));
		final directives = HxModuleDecl.getDirectives(module);
		add(out, Std.string(directives.length));
		for (directive in directives)
			add(out, HxModuleDirective.canonicalIdentity(directive));
		add(out, HxModuleDecl.getHeaderOnly(module) ? "header" : "complete");
		add(out, HxModuleDecl.getHasToplevelMain(module) ? "toplevel-main" : "class-main");
		final classes = HxModuleDecl.getClasses(module);
		add(out, Std.string(classes.length));
		for (parsedClass in classes)
			addClass(out, parsedClass);
	}

	static function addClass(out:StringBuf, parsedClass:HxClassDecl):Void {
		add(out, HxClassDecl.getName(parsedClass));
		add(out, HxClassDecl.getHasStaticMain(parsedClass) ? "static-main" : "no-static-main");
		add(out, HxClassDecl.getExtendsPath(parsedClass));
		add(out, HxClassDecl.getIsInterface(parsedClass) ? "interface" : "class");
		add(out, HxClassDecl.getVisibility(parsedClass) == HxVisibility.Public ? "public" : "private");
		addStrings(out, HxClassDecl.getImplementsPaths(parsedClass));
		addStrings(out, HxClassDecl.getMetadata(parsedClass));

		final fields = HxClassDecl.getFields(parsedClass);
		add(out, Std.string(fields.length));
		for (field in fields) {
			add(out, HxFieldDecl.getName(field));
			add(out, visibilityName(HxFieldDecl.getVisibility(field)));
			add(out, HxFieldDecl.getIsStatic(field) ? "static" : "instance");
			add(out, HxFieldDecl.getTypeHint(field));
			add(out, HxFieldDecl.getIsFinal(field) ? "final" : "mutable");
			add(out, HxFieldDecl.getPropertyGet(field));
			add(out, HxFieldDecl.getPropertySet(field));
			add(out, HxFieldDecl.getInitText(field));
			addStrings(out, HxFieldDecl.getMetadata(field));
			addPosition(out, HxFieldDecl.getPos(field));
			addPosition(out, HxFieldDecl.getEndPos(field));
			add(out, TypedBodyFingerprint.forExpression(HxFieldDecl.getInit(field)));
		}

		final functions = HxClassDecl.getFunctions(parsedClass);
		add(out, Std.string(functions.length));
		for (fn in functions) {
			add(out, HxFunctionDecl.getName(fn));
			add(out, visibilityName(HxFunctionDecl.getVisibility(fn)));
			add(out, HxFunctionDecl.getIsStatic(fn) ? "static" : "instance");
			add(out, HxFunctionDecl.getReturnTypeHint(fn));
			add(out, HxFunctionDecl.getReturnStringLiteral(fn));
			add(out, HxFunctionDecl.getBodyText(fn));
			add(out, HxFunctionDecl.getHasBody(fn) ? "body" : "declaration");
			addStrings(out, HxFunctionDecl.getMetadata(fn));
			addPosition(out, HxFunctionDecl.getPos(fn));
			addPosition(out, HxFunctionDecl.getEndPos(fn));
			final args = HxFunctionDecl.getArgs(fn);
			add(out, Std.string(args.length));
			for (arg in args) {
				add(out, HxFunctionArg.getName(arg));
				add(out, HxFunctionArg.getTypeHint(arg));
				add(out, HxFunctionArg.getIsOptional(arg) ? "optional" : "required");
				add(out, HxFunctionArg.getIsRest(arg) ? "rest" : "ordinary");
				add(out, HxFunctionArg.getDefaultValueText(arg));
				switch (HxFunctionArg.getDefaultValue(arg)) {
					case NoDefault:
						add(out, "no-default");
					case Default(expression):
						add(out, TypedBodyFingerprint.forExpression(expression));
				}
			}
			add(out, TypedBodyFingerprint.forStatements(HxFunctionDecl.getBody(fn)));
		}
	}

	static function addStrings(out:StringBuf, values:Array<String>):Void {
		add(out, values == null ? "-1" : Std.string(values.length));
		if (values != null)
			for (value in values)
				add(out, value);
	}

	static function addPosition(out:StringBuf, position:HxPos):Void {
		if (position == null) {
			add(out, "unknown-position");
			return;
		}
		add(out, '${position.getIndex()}:${position.getLine()}:${position.getColumn()}');
	}

	static function visibilityName(visibility:HxVisibility):String {
		return switch (visibility) {
			case Public: "public";
			case Private: "private";
		}
	}

	static function add(out:StringBuf, value:Null<String>):Void {
		if (value == null) {
			out.add("-1:");
			return;
		}
		out.add(value.length);
		out.add(":");
		out.add(value);
	}
}
