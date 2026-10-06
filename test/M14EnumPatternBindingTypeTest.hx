import sys.io.File;

/** Enum payload locals must retain the constructor's applied argument types. */
class M14EnumPatternBindingTypeTest {
	static function check(source:String, method:String, expected:Array<String>):Void {
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		for (owner in typed.getTypedClasses())
			for (fn in owner.getFunctions()) {
				if (HxFunctionDecl.getName(fn.getSourceDeclaration()) != method)
					continue;
				final locals = fn.getEnvironment().getLocals().filter(local -> local.getKind() == PatternVariable);
				final actual = [for (local in locals) local.getName() + ":" + local.getType().getSemanticKey()];
				if (actual.join("|") != expected.join("|"))
					throw "enum payload bindings: expected " + expected + "; got " + actual;
				final projected = typed.getBackendProjection();
				var foundProjection = false;
				for (cls in projected.getClasses())
					for (body in cls.getFunctions()) {
						if (HxFunctionDecl.getName(body.getDeclaration()) != method)
							continue;
						foundProjection = true;
						final bindings = body.getLocalCatalog().getEntries().filter(entry -> entry.getBinding().getKind() == PatternVariable);
						final transported = [
							for (entry in bindings)
								entry.getBinding().getSourceName() + ":" + entry.getBinding().getType().getSemanticKey()
						];
						transported.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
						final sorted = expected.copy();
						sorted.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
						if (transported.join("|") != sorted.join("|"))
							throw "enum payload projection lost its declared types: " + transported;
					}
				if (!foundProjection)
					throw "missing projected function " + method;
				return;
			}
		throw "missing function " + method;
	}

	/** Wrong declarations and argument counts must fail before branch locals exist. */
	static function reject(pattern:String, reason:String):Void {
		final source = 'enum First { Item(value:Int); } enum Second { Item(value:Int); } class Main { static function read(v:First):Int return switch v {case '
			+ pattern
			+ ': 1; case _: 0;}; }';
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		try {
			TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		} catch (error:TyperError) {
			if (error.getMessage().indexOf(reason) < 0)
				throw error;
			return;
		}
		throw "invalid enum pattern accepted: " + pattern;
	}

	/** Qualified constructors share a prefix with extractors, but retain distinct grammar. */
	static function checkParser():Void {
		final expression = HxParser.parseExprText('switch value { case Box.Item(flag): 1; case Box.Empty: 2; case Std.parseInt(_) => code: 3; }');
		switch (expression) {
			case ESwitch(_, [
				PEnumExtract("Box.Item", [PBind("flag")]),
				PEnumValue("Box.Empty"),
				PExtractor("Std.parseInt(_)", PBind("code"))
			], _):
			case _:
				throw "qualified patterns lost their constructor, constant, or extractor grammar";
		}
	}

	static function main():Void {
		checkParser();
		reject("Second.Item(x)", "constructor belongs to another enum");
		reject("Item(x,y)", "expected 1 payload patterns but received 2");
		reject("Missing(x)", "constructor does not belong to Main.First");
		check(File.getContent("test/fixtures/stage3_enum_patterns/Main.hx"), "read", [
			"number:primitive:Int",
			"flag:primitive:Bool",
			"number:primitive:Int", // Wrap(Pair(number, true))
			"number:primitive:Int" // Maybe(Pair(number, true))
		]);
		check('enum Box<T> { Item(value:T); } class Main { static function read(v:Box<String>):String return switch v {case Item(text): text; case _: "none";}; }',
			"read", ["text:primitive:String"]);
		check('enum Box<T> { Item(value:T); } class Main { static function read(v:Box<Array<Bool>>):Bool return switch v {case Item([flag]): flag; case _: false;}; }',
			"read", ["flag:primitive:Bool"]);
		check('enum Box<T> { Item(value:T); } class Main { static function read(v:Box<Bool>):Bool return switch v {case Box.Item(flag): flag; case _: false;}; }',
			"read", ["flag:primitive:Bool"]);
		check('enum Box<T> { Item(value:T); Other(value:T); } class Main { static function read(v:Box<Bool>):Bool return switch v {case Item(flag) | Other(flag): flag; case _: false;}; }',
			"read", ["flag:primitive:Bool"]);
		check('enum First { Item(value:Int); } enum Second { Item(value:Bool); } class Main { static function read(v:Second):Bool return switch v {case Item(flag): flag; case _: false;}; }',
			"read", ["flag:primitive:Bool"]);
		check('enum Box<T> { Item(value:T); } class Main { static function read(v:Null<Box<Bool>>):Bool return switch v {case Item(flag): flag; case _: false;}; }',
			"read", ["flag:primitive:Bool"]);
		Sys.println("ENUM_PATTERN_BINDING_TYPE:PASS");
	}
}
