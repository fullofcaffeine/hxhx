import sys.io.File;

/** Optional pattern suffixes keep the full constructor shape without changing authored cases. */
class M14OptionalEnumPatternTest {
	static function typed(source:String):TypedModule {
		final module = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		return TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
	}

	/** Compare admission with upstream on the same source, including extractor versus singleton syntax. */
	static function admission(declaration:String, construction:String, pattern:String, accepted:Bool, extraDeclarations:String = ""):Void {
		final source = 'enum Value {'
			+ declaration
			+ '} '
			+ extraDeclarations
			+ ' class Main { static function main():Void { final value='
			+ construction
			+ '; switch value { case '
			+ pattern
			+ ': case _: } } }';
		final root = ".tmp/optional-enum-pattern-oracle";
		sys.FileSystem.createDirectory(root);
		File.saveContent(root + "/Main.hx", source);
		final process = new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "--run", "Main"]);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if ((code == 0) != accepted)
			throw "upstream pattern expectation differs: " + pattern + ": " + stdout + stderr;
		var localAccepted = false;
		try {
			typed(source).getBackendProjection();
			localAccepted = true;
		} catch (error:TyperError) {
			if (error.getMessage().indexOf("Invalid enum pattern") < 0)
				throw error;
		}
		if (localAccepted != accepted)
			throw "local pattern expectation differs: " + pattern;
	}

	static function names(projection:TypedBackendFunctionProjection):Array<HxSwitchPattern> {
		final result = new Array<HxSwitchPattern>();
		TypedBackendSourceWalk.functionDeclaration(projection.getDeclaration(), expression -> TypedBackendNamedPattern.inExpression(expression, result.push),
			statement -> TypedBackendNamedPattern.inStatement(statement, result.push));
		return result;
	}

	/** Nested qualified selections keep exact owners and source children while execution gains wildcards. */
	static function identity():Void {
		final module = typed('enum Box<T> { Item(value:T,?tail:Bool); } enum Outer { Wrap(value:Box<Int>,?tail:String); }'
			+ 'class Main { static function read(value:Outer):Int return switch value { case Outer.Wrap(Box.Item(number)):number; case _:0; }; }');
		final source = module.getTypedClasses().filter(owner -> HxClassDecl.getName(owner.getSourceDeclaration()) == "Main")[0].getFunctions()[0];
		final before = TypedBodyFingerprint.exactStatements(HxFunctionDecl.getBody(source.getSourceDeclaration()));
		final projection = TypedBodySource.functionProjection(source);
		final patterns = names(projection);
		if (patterns.length != 2)
			throw "optional projection changed named occurrence count";
		switch patterns[0] {
			case PEnumExtract("Outer.Wrap", [PEnumExtract("Box.Item", [PBind(_), PWildcard]), PWildcard]):
			case _:
				throw "optional projection lost its complete executable payload shape";
		}
		final expected = ["Main.Outer", "Main.Box"];
		for (index in 0...patterns.length) {
			final selected = projection.findNamedPattern(patterns[index]);
			if (selected == null)
				throw "optional projection lost its exact selected occurrence";
			switch selected.getKind() {
				case Constructor(owner, _, _, 2) if (owner.getCanonicalName() == expected[index]):
				case _:
					throw "optional projection replaced full declared arity or owner";
			}
		}
		final again = TypedBodySource.functionProjection(source);
		if (again.findNamedPattern(patterns[1]) != null
			|| projection.findNamedPattern(PEnumExtract("Box.Item", [PBind("number"), PWildcard])) != null)
			throw "another optional pattern borrowed an occurrence's declaration";
		if (TypedBodyFingerprint.exactStatements(HxFunctionDecl.getBody(source.getSourceDeclaration())) != before)
			throw "optional projection mutated authored syntax";
		final locals = source.getEnvironment().getLocals().filter(local -> local.getKind() == PatternVariable);
		if (locals.length != 1 || locals[0].getType().getSemanticKey() != "primitive:Int")
			throw "omitted optional slots created locals or changed a generic payload binding";

		final child:HxSwitchPattern = PBind("kept");
		final original:HxSwitchPattern = PEnumExtract("Box.Item", [child]);
		final selection = projection.findNamedPattern(patterns[1]);
		final facts = new TypedSwitchPatterns(TyType.unknown(), [original], [selection]);
		final copied = facts.projectPayloads([original]);
		switch [original, copied[0]] {
			case [PEnumExtract(_, [a]), PEnumExtract(_, [b, PWildcard])] if (a == child && b == child):
			case _:
				throw "catalog-free padding changed the original child or mutated its array";
		}
		var rejected = false;
		try {
			facts.projectPayloads([PEnumExtract("Box.Item", [child, PWildcard])]);
		} catch (_:String) {
			rejected = true;
		}
		if (!rejected)
			throw "optional payload facts accepted an edited written count";
	}

	/** Guards and alternatives keep capture order when omitted payloads add no bindings. */
	static function bindingOrder():Void {
		final module = typed('enum Value { Build(a:Int,?tail:Bool); Other(a:Int,?tail:Bool); }'
			+ 'class Main { static function read(value:Value):Void { switch value {'
			+ 'case captured=(Build(a) | Other(a)) if (a > 0): final kept:Int=a; case _: } } }');
		final source = module.getTypedClasses().filter(owner -> HxClassDecl.getName(owner.getSourceDeclaration()) == "Main")[0].getFunctions()[0];
		final locals = source.getEnvironment().getLocals().filter(local -> local.getKind() == PatternVariable);
		if (locals.length != 2
			|| locals[0].getName() != "captured"
			|| locals[0].getType().getSemanticKey() != "nominal:Main.Value"
			|| locals[1].getName() != "a"
			|| locals[1].getType().getSemanticKey() != "primitive:Int")
			throw "optional guarded alternatives changed exact capture binding order";
		final projection = TypedBodySource.functionProjection(source);
		final patterns = names(projection);
		if (patterns.length != 2)
			throw "optional guarded alternatives changed named occurrence order";
		for (pattern in patterns)
			switch pattern {
				case PEnumExtract(_, [PBind(_), PWildcard]) if (projection.findNamedPattern(pattern) != null):
				case _:
					throw "optional guarded projection lost its complete payload or exact selection";
			}
	}

	public static function check():Void {
		admission("Build(a:Int,b:Int,?tail:String);", 'Build(1,2,"kept")', "Build(a,b)", true);
		admission("Build(a:Int,?middle:String,?tail:Bool);", 'Build(1,"kept",true)', "Build(a)", true);
		admission("Build(?a:Int,?tail:Bool);", "Build(1,true)", "Build()", true);
		admission("Build(?a:Int,?tail:Bool);", "Build(1,true)", "Build", false);
		admission("Build(a:Int,b:Int,tail:String);", 'Build(1,2,"kept")', "Build(a,b)", false);
		admission("Build(?a:Int,last:Bool);", "Build(1,true)", "Build(a)", false);
		admission("Build(a:Int,?tail:Bool);", "Build(1,true)", "Build(a,b,c)", false);
		admission("Empty;", "Empty", "Empty", true);
		admission("Empty;", "Empty", "Empty()", false);
		admission("Build(a:Int,?tail:Bool);", "Value.Build(1,true)", "Other.Build(a)", false, "enum Other { Build(a:Int,?tail:Bool); }");
		admission("Build(a:Int,?tail:Bool); Other(a:Int,?tail:Bool);", "Build(1,true)", "captured=(Build(a) | Other(a)) if (a > 0)", true);
		identity();
		bindingOrder();
		Sys.println("OPTIONAL_ENUM_PATTERN:PASS");
	}
}
