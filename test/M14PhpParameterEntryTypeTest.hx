import backend.BackendContext;
import backend.BackendRegistry;
import backend.source.PhpTypedProgramProjection;

/** Written call types and body-entry types must agree without confusing omission with a null rest collection. */
class M14PhpParameterEntryTypeTest {
	static function main():Void {
		final source = 'class Main {'
			+ ' static function optional(?value:Int):Void { Sys.println(value == null ? "missing" : "present"); }'
			+ ' static function defaults(value:Int=4, nullable:Int=null):Void { Sys.println(value + ":" + (nullable == null ? "null" : "set")); }'
			+ ' static function rest(...values:Int):Void { Sys.println(values.length); }'
			+ ' static function main():Void { optional(); optional(3); defaults(); defaults(8,2); rest(); rest(1,2); } }';
		final root = ".tmp/php_parameter_entry_" + Date.now().getTime();
		sys.FileSystem.createDirectory(root);
		sys.io.File.saveContent(root + "/Main.hx", source);
		final expected = "missing\npresent\n4:null\n8:set\n0\n2";
		if (StringTools.trim(run("haxe", ["-cp", root, "-main", "Main", "--interp"])) != expected)
			throw "upstream parameter entry behavior changed";
		final module = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		final program = new MacroExpandedProgram([typed], false);
		final projected = new PhpTypedProgramProjection(program);
		for (fn in typed.getBackendProjection().getClasses()[0].getFunctions()) {
			final declaration = fn.getDeclaration();
			final name = HxFunctionDecl.getName(declaration);
			final plan = projected.requireFunctionLoweringPlan(declaration);
			final locals = plan.copyLocals();
			if (name == "optional" && locals[0].typeIdentity != "nullable:primitive:Int")
				throw "optional parameter lost body nullability";
			if (name == "defaults" && (locals[0].typeIdentity != "primitive:Int" || locals[1].typeIdentity != "nullable:primitive:Int"))
				throw "default entry types were conflated";
			if (name == "rest" && (locals[0].semanticType.isNullable() || !locals[0].isRestCarrier))
				throw "omitted rest parameter must have a non-null collection";
			if (name == "optional") {
				final argument = plan.copyCurrentMethod().arguments[0];
				final wrongType = TyType.fromHintText("String");
				final conflicting:TypedBackendClassSemanticFacts.TypedBackendClassMethodArgumentFact = {
					name: argument.name,
					semanticType: wrongType,
					typeIdentity: wrongType.getSemanticKey(),
					typeDisplay: wrongType.getCanonicalDisplay(),
					isOptional: argument.isOptional,
					isRest: argument.isRest
				};
				var rejected = false;
				try {
					@:privateAccess plan.requireExactParameters([conflicting], fn.getParameterBindingIdentities(), HxFunctionDecl.getArgs(declaration));
				} catch (error:String) {
					rejected = error.indexOf("conflicting parameter type") >= 0;
				}
				if (!rejected)
					throw "PHP accepted a conflicting nullable parameter type";
			}
		}
		final result = BackendRegistry.requireForTarget("php-native")
			.emit(program, new BackendContext(root + "/php", null, "Main", true, false, new haxe.ds.StringMap<String>()));
		final actual = StringTools.trim(run("php", [result.entryPath]));
		if (actual != expected)
			throw "PHP parameter entry behavior differs: " + actual;
		Sys.println("PHP_PARAMETER_ENTRY_TYPES:PASS");
	}

	static function run(command:String, arguments:Array<String>):String {
		final process = new sys.io.Process(command, arguments);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0)
			throw command + " failed: " + errors;
		return output;
	}
}
