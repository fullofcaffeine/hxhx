import backend.cpp.CppTypedProgramProjection;
import backend.cpp.CppManagedProgramPlan;
import backend.cpp.CppManagedStaticStorage;

/** Defaults and inline reads must retain exact owners rather than equal-looking source copies. */
class M14CppDefaultProjectionTest {
	static function program(source:String):CppTypedProgramProjection {
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		return new CppTypedProgramProjection(new MacroExpandedProgram([TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]))], false));
	}

	static function rejects(run:Void->Void, expected:String):Void {
		try {
			run();
		} catch (error:haxe.Exception) {
			if (error.message.indexOf(expected) >= 0)
				return;
			throw error;
		}
		throw "default projection accepted invalid ownership: " + expected;
	}

	static function defaultFunction(program:CppTypedProgramProjection):TypedBackendFunctionProjection {
		return program.getModules()[0].projection.getClasses()[0].getFunctions()[0];
	}

	static function main():Void {
		final source = 'class Main { public static inline var TEXT:String="value"; static function read(value:String=TEXT):String return value; }';
		final owned = program(source);
		final fn = defaultFunction(owned);
		final values = fn.getDefaults();
		if (values.length != 1 || values[0].slot != 0 || values[0].type.getSemanticKey() != "primitive:String")
			throw "projected default lost its parameter or type";
		final occurrence = fn.findField(values[0].expression);
		if (occurrence == null)
			throw "default field was omitted from the declaration catalog";
		final storage = new CppManagedStaticStorage(owned, "hxhx_statics_defaults");
		storage.inlineInitializer(occurrence);
		rejects(() -> {
			storage.member(occurrence, true);
		}, "exact field");
		final foreign = defaultFunction(program(source));
		rejects(() -> {
			storage.inlineInitializer(foreign.findField(foreign.getDefaults()[0].expression));
		}, "exact declaration");
		values.pop();
		if (fn.getDefaults().length != 1)
			throw "default list exposed mutable ownership";
		final arguments = HxFunctionDecl.getArgs(fn.getDeclaration());
		final original = arguments[0];
		final copied = switch HxFunctionArg.getDefaultValue(original) {
			case Default(EIdent(name)): HxExpr.EIdent(name);
			case _: throw "default fixture lost its bare constant read";
		};
		arguments[0] = new HxFunctionArg(original.name, original.typeHint, HxDefaultValue.Default(copied), original.isOptional, original.isRest,
			original.defaultValueText, original.metadata);
		rejects(() -> {
			fn.getDefaults();
		}, "original occurrence");
		final cycle = program('class Main { static inline var A:Int=B; static inline var B:Int=A; static function main():Void { var value=A; } }');
		rejects(() -> {
			new CppManagedProgramPlan(cycle, "Main").render();
		}, "cyclic managed inline field");
		rejects(() -> {
			new CppManagedProgramPlan(program('class Main { static function main():Void { new Box(null); } } class Box { public function new(value:Int=4) {} }'),
				"Main").render();
		}, "literal null requires a nullable or question-mark parameter");
		for (scalar in [{type: "Int", value: "4"}, {type: "Bool", value: "true"}]) {
			final bare = 'value:${scalar.type}=${scalar.value}';
			rejects(() -> {
				program('class Main { static function take($bare):Void {} static function main():Void { take(null); } }');
			}, "named call literal null requires a nullable or question-mark parameter");
			for (parameter in ['?$bare', 'value:Null<${scalar.type}>=${scalar.value}'])
				new CppManagedProgramPlan(program('class Main { static function take($parameter):Void {} static function main():Void { take(null); } }'),
					"Main").render();
			new CppManagedProgramPlan(program('class Main { static function take($bare):Void {} static function main():Void { var absent:Null<${scalar.type}>=null; take(absent); take(); } }'),
				"Main").render();
		}
		Sys.println("CPP_DEFAULT_PROJECTION:PASS");
	}
}
