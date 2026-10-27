import sys.FileSystem;
import sys.io.File;

/** Calls infer method parameters from public structural members and retain the inferred result. */
class M14GenericStructuralCallTest {
	static function require(value:Bool, message:String):Void {
		if (!value)
			throw message;
	}

	static function program(declarations:String, method:String, statements:String):String {
		return declarations + " class Main {" + method + " static function main():Void {" + statements + "}}";
	}

	/** Expectations are authored independently and checked against upstream before candidate typing. */
	static function main():Void {
		final reader = 'class Reader { public function new() {} public function read():String return "read"; } ';
		final cases = [
			{name: "concrete_class",
				source: 'typedef ReaderLike = {function read():String;}; '
				+ reader
				+ 'class Main {static function take(source:ReaderLike, value:String):String return source.read(); '
				+ 'static function main() {Sys.println(take(new Reader(), "item"));}}',
				accepted: true
			}
		];
		for (name in ["generic_class", "generic_record", "wrong_item"])
			cases.push({name: name,
				source: 'typedef ReaderLike<T> = {function read():T;}; '
				+ reader
				+ 'class Main {static function take<T>(source:ReaderLike<T>, value:T):T return source.read(); '
				+ 'static function main() {Sys.println(take('
				+ (name == "generic_record" ? '{read:function():String return "read"}' : 'new Reader()')
				+ ', '
				+ (name == "wrong_item" ? '7' : '"item"')
				+ '));}}',
				accepted: name != "wrong_item"
			});
		final contract = 'typedef ReaderLike<T> = {function read():T;}; ';
		final generic = 'static function take<T>(source:ReaderLike<T>):T return source.read();';
		cases.push({name: "member_only", source: program(contract + reader, generic, 'Sys.println(take(new Reader()));'), accepted: true});
		cases.push({
			name: "inherited",
			source: program(contract
				+ 'class Base<T> {final value:T; public function new(value:T) {this.value=value;} public function read():T return value;} '
				+ 'class Reader extends Base<String> {public function new() {super("read");}}',
				generic, 'Sys.println(take(new Reader()));'),
			accepted: true
		});
		cases.push({
			name: "nullable",
			source: program(contract + reader, 'static function take<T>(source:Null<ReaderLike<T>>):T return source.read();',
				'Sys.println(take(new Reader()));'),
			accepted: true
		});
		cases.push({
			name: "nested_reader",
			source: program('typedef Cursor<T>={function next():T;}; typedef Source<T>={function iterator():Cursor<T>;}; '
				+ 'class CursorValue {public function new() {} public function next():String return "read";} '
				+ 'class Reader {public function new() {} public function iterator():CursorValue return new CursorValue();}',
				'static function take<T>(source:Source<T>):T return source.iterator().next();', 'Sys.println(take(new Reader()));'),
			accepted: true
		});
		cases.push({
			name: "nested_array",
			source: program('typedef ReaderLike<T>={function read():Array<T>;}; '
				+ 'class Reader {public function new() {} public function read():Array<String> return ["read"];}',
				'static function take<T>(source:ReaderLike<T>):T return source.read()[0];', 'Sys.println(take(new Reader()));'),
			accepted: true
		});
		cases.push({
			name: "recursive",
			source: program('typedef Link<T>={final value:T; final ?next:Link<T>;}; typedef Other<T>={final value:T; final ?next:Other<T>;};',
				'static function take<T>(source:Link<T>):T return source.value;', 'var source:Other<String>={value:"read"}; Sys.println(take(source));'),
			accepted: true
		});
		cases.push({
			name: "rotating_recursive",
			source: program('typedef Link<A,B,C>={final value:A; final ?next:Link<B,C,A>;}; '
				+ 'typedef Other<A,B,C>={final value:A; final ?next:Other<B,C,A>;};',
				'static function take<A,B,C>(source:Link<A,B,C>):C return source.next.next.value;',
				'var source:Other<Int,Bool,String>={value:7,next:{value:true,next:{value:"read"}}}; Sys.println(take(source));'),
			accepted: true
		});
		for (wrong in [false, true])
			cases.push({
				name: wrong ? "wrong_bound" : "bound",
				source: program(contract + (wrong ? 'class Reader {public function new() {} public function read():Int return 7;}' : reader),
					'static function take<T:String>(source:ReaderLike<T>):T return source.read();', 'Sys.println(take(new Reader()));'),
				accepted: !wrong
			});
		cases.push({
			name: "repeated_conflict",
			source: program(contract + reader + 'class NumberReader {public function new() {} public function read():Int return 7;}',
				'static function take<T>(first:ReaderLike<T>, second:ReaderLike<T>):T return first.read();',
				'Sys.println(take(new Reader(), new NumberReader()));'),
			accepted: false
		});
		cases.push({
			name: "private",
			source: program(contract + 'class Reader {public function new() {} private function read():String return "read";}', generic,
				'Sys.println(take(new Reader()));'),
			accepted: false
		});
		cases.push({
			name: "overload_rollback",
			source: program(contract + reader,
				'@:overload(function<T>(source:ReaderLike<T>, value:T):T {}) ' +
				'static function take<T>(source:ReaderLike<T>, value:Int):T return source.read();',
				'Sys.println(take(new Reader(), 7));'),
			accepted: true
		});
		for (wanted in ["method", "variable"])
			for (provided in ["record", "method", "variable", "final"]) {
				final field = wanted == "method" ? 'function read():String;' : 'var read:()->String;';
				final supplied = provided == "method" ? 'public function read():String return "read";' : 'public '
					+ (provided == "final" ? 'final ' : 'var ')
					+ 'read:()->String = function():String return "read";';
				final value = provided == "record" ? '{read:function():String return "read"}' : 'new Reader()';
				cases.push({
					name: wanted + "_" + provided,
					source: program('typedef Contract={'
						+ field
						+ '}; class Reader {public function new() {} '
						+ supplied
						+ '}',
						'static function take(source:Contract):String return source.read();', 'Sys.println(take('
						+ value
						+ '));'),
					accepted: provided != "final" && !(wanted == "variable" && provided == "method")
				});
			}
		final root = ".tmp/generic_structural_call";
		for (input in cases) {
			final directory = root + "/" + input.name;
			FileSystem.createDirectory(directory);
			File.saveContent(directory + "/Main.hx", input.source);
			final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout",
				["30", "node_modules/.bin/haxe", "-cp", directory, "--run", "Main"]);
			final stdout = process.stdout.readAll().toString();
			final stderr = process.stderr.readAll().toString();
			final code = process.exitCode();
			process.close();
			require(input.accepted ? code == 0 && stdout == "read\n" && stderr == "" : code == 1 && stderr != "",
				"upstream structural call differs: "
				+ input.name
				+ " "
				+ stdout
				+ stderr);
		}
		Sys.println("GENERIC_STRUCTURAL_UPSTREAM:PASS");
		final nativeCases = new Array<{name:String, directory:String, typed:TypedModule}>();
		for (input in cases) {
			final directory = root + "/" + input.name;
			var typed:Null<TypedModule> = null;
			var diagnostic = "";
			try {
				typed = M14Stage3RuntimeFixture.typeMain({source: input.source, path: directory + "/Main.hx", root: directory});
			} catch (error:TyperError) {
				diagnostic = error.message;
			}
			require((typed != null) == input.accepted, "generic structural acceptance differs: " + input.name + " " + diagnostic);
			if (typed == null) {
				Sys.println("GENERIC_STRUCTURAL_REJECTION:PASS " + input.name + " " + diagnostic);
				continue;
			}
			var calls = 0;
			function inspect(expression:TypedExpr):Void {
				final declaration = expression.getDeclaration();
				if (expression.getTag() == Call && declaration != null && declaration.getSignature().getName() == "take") {
					calls++;
					require(expression.getType().getSemanticKey() == "primitive:String", "structural call lost its String result: " + input.name);
				}
				for (child in expression.getExpressions())
					inspect(child);
			}
			for (owner in typed.getTypedClasses())
				for (fn in owner.getFunctions())
					for (statement in fn.getBody().getStatements())
						for (expression in statement.getExpressions())
							inspect(expression);
			require(calls == 1, "structural call observer lost the selected declaration");
			Sys.println("GENERIC_STRUCTURAL_CASE:PASS " + input.name);
			if (input.name == "generic_class" || input.name == "generic_record")
				nativeCases.push({name: input.name, directory: directory, typed: typed});
		}
		Sys.println("GENERIC_STRUCTURAL_CALL:PASS");
		for (input in nativeCases) {
			final executable = EmitterStage.emitToDir(new MacroExpandedProgram([input.typed], false), input.directory + "/out");
			M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: "read\n"});
			Sys.println("GENERIC_STRUCTURAL_NATIVE:PASS " + input.name);
		}
	}
}
