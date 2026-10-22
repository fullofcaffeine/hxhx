import sys.io.File;
import sys.FileSystem;

/** Each payload call infers fresh enum arguments while the shared declaration retains its binders. */
class M14EnumConstructorInferenceTest {
	static function main():Void {
		final positionedSource = 'class Main {}\n\n enum Result<T:String> {Value(item:T);}';
		final positioned = ParserStage.parse(positionedSource, "Main.hx");
		for (cls in HxModuleDecl.getClasses(positioned.getDecl()))
			if (HxClassDecl.getName(cls) == "Result") {
				final bound = HxClassDecl.getTypeParameters(cls)[0].constraints[0].getPos();
				if (bound.getIndex() != positionedSource.indexOf("String") || bound.getLine() != 3 || bound.getColumn() != 16)
					throw "enum bound lost its original source position: " + bound;
			}
		final prefix = 'enum Result<T> {Empty;Value(item:T);} ';
		final cases:Array<{name:String, source:String, accepts:Bool}> = [
			{
				name: "independent",
				source: prefix + 'class Main {static function main():Void {var number=Result.Value(4);var text=Result.Value("text");}}',
				accepts: true
			},
			{name: "expected", source: prefix + 'class Main {static function main():Void {var value:Result<Int>=Result.Value(4);}}', accepts: true},
			{name: "wrong_expected", source: prefix + 'class Main {static function main():Void {var value:Result<Int>=Result.Value("bad");}}', accepts: false},
			{
				name: "wrong_call",
				source: prefix + 'class Main {static function consume(value:Result<Int>):Void {} static function main():Void {consume(Result.Value("bad"));}}',
				accepts: false
			},
			{
				name: "bounded",
				source: 'enum Result<T:String> {Value(item:T);} class Main {static function main():Void {var value=Result.Value("text");}}',
				accepts: true
			},
			{
				name: "wrong_bound",
				source: 'enum Result<T:String> {Value(item:T);} class Main {static function main():Void {var value=Result.Value(4);}}',
				accepts: false
			},
			{
				name: "record_bound",
				source: 'enum Result<T:{name:String}> {Value(item:T);} class Main {static function main():Void {var value=Result.Value({name:"text"});}}',
				accepts: true
			},
			{
				name: "wrong_record_bound",
				source: 'enum Result<T:{name:String}> {Value(item:T);} class Main {static function main():Void {var value=Result.Value({name:4});}}',
				accepts: false
			}
		];
		for (entry in cases) {
			final folder = ".tmp/enum_constructor_inference/" + entry.name;
			FileSystem.createDirectory(folder);
			File.saveContent(folder + "/Main.hx", entry.source);
			final upstream = new sys.io.Process("haxe", ["-cp", folder, "-main", "Main", "--no-output"]);
			final diagnostic = upstream.stderr.readAll().toString();
			final upstreamAccepted = upstream.exitCode() == 0;
			upstream.close();
			if (upstreamAccepted != entry.accepts)
				throw "upstream enum expectation differs: " + entry.name + " " + diagnostic;
			final module = new ResolvedModule("Main", folder + "/Main.hx", ParserStage.parse(entry.source, folder + "/Main.hx"));
			final index = TyperIndex.build([module]);
			final owner = index.getByFullName("Main.Result");
			final signature = owner.staticMethod("Value");
			final original = signature.getArgs()[0].getSemanticKey();
			var accepted = true;
			var nativeDiagnostic = "";
			var typed:Null<TypedModule> = null;
			try
				typed = TyperStage.typeResolvedModule(module, index)
			catch (error:haxe.Exception) {
				accepted = false;
				nativeDiagnostic = error.message;
			}
			File.saveContent(folder
				+ "/diagnostics.txt",
				"upstream="
				+ upstreamAccepted
				+ "\n"
				+ diagnostic
				+ "native="
				+ accepted
				+ "\n"
				+ nativeDiagnostic
				+ "\n");
			if (accepted != entry.accepts)
				throw "enum constructor acceptance differs: " + entry.name + " " + nativeDiagnostic;
			if (!signature.getArgs()[0].isTypeParameter() || signature.getArgs()[0].getSemanticKey() != original)
				throw "enum call specialized the shared declaration";
			if (entry.name == "independent") {
				final observed = new Map<String, String>();
				for (cls in typed.getTypedClasses())
					for (fn in cls.getFunctions())
						for (local in fn.getEnvironment().getLocals())
							observed.set(local.getName(), local.getType().getCanonicalDisplay());
				if (observed.get("number") != "Main.Result<Int>" || observed.get("text") != "Main.Result<String>")
					throw "enum calls did not infer independent payload types: " + observed;
			}
			Sys.println("ENUM_CONSTRUCTOR_INFERENCE:PASS " + entry.name);
		}
	}
}
