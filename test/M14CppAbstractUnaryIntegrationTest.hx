import backend.BackendContext;
import backend.BackendRegistry;
import haxe.ds.StringMap;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/** Builds and executes the repo-owned abstract-unary contract through native C++. **/
class M14CppAbstractUnaryIntegrationTest {
	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function assertContains(content:String, needle:String, message:String):Void {
		assertTrue(content.indexOf(needle) >= 0, message + " (missing `" + needle + "`)");
	}

	static function deleteRecursive(path:String):Void {
		if (!FileSystem.exists(path))
			return;
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path))
				deleteRecursive(Path.join([path, entry]));
			FileSystem.deleteDirectory(path);
		} else {
			FileSystem.deleteFile(path);
		}
	}

	static function commandOutput(command:String):{code:Int, stdout:String, stderr:String} {
		final process = new sys.io.Process(command, []);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		return {code: code, stdout: stdout, stderr: stderr};
	}

	static function main():Void {
		final source = [
			"class Payload {",
			"  public var value:Int;",
			"  public function new(value:Int) this.value = value;",
			"}",
			"abstract Boxed(Payload) from Payload to Payload {",
			"  public var value(get, set):Int;",
			"  public function get_value():Int return this.value;",
			"  public function set_value(value:Int):Int return this.value = value;",
			"  @:op(-A) public static function turnInsideOut(input:Boxed):Boxed return new Payload(-input.value);",
			"  public inline function get():Payload return this;",
			"}",
			"abstract Step(Int) {",
			"  public inline function new(value:Int) this = value;",
			"  @:op(-A) public function reverseSign():Step return new Step(-this);",
			"  @:op(++A) public inline function advanceBefore():Step { this += 10; return cast this; }",
			"  @:op(A++) public inline function advanceAfter():Step { var old = this; this += 100; return cast old; }",
			"  public function get():Int return this;",
			"}",
			"abstract StaticStep(Int) {",
			"  public inline function new(value:Int) this = value;",
			"  @:op(++A) public static function surprising(value:StaticStep):Int return value.get() + 10;",
			"  public function get():Int return this;",
			"}",
			"class Counter {",
			"  public var indexCalls:Int = 0;",
			"  public var receiverCalls:Int = 0;",
			"  public var holder:Holder;",
			"  public function new() holder = new Holder(5);",
			"  public function chooseIndex():Int { indexCalls++; return 0; }",
			"  public function chooseHolder():Holder { receiverCalls++; return holder; }",
			"}",
			"class Holder {",
			"  public var step:Step;",
			"  public function new(value:Int) step = new Step(value);",
			"}",
			"class Main {",
			"  static function main() {",
			"    var counter = new Counter();",
			"    var boxed:Boxed = new Payload(7);",
			"    var boxedResult = -boxed;",
			"    Sys.println(boxedResult.get().value);",
			"    var step:Step = new Step(12);",
			"    Sys.println((-step).get());",
			"    Sys.println(step.get());",
			"    var prefixResult = ++step;",
			"    Sys.println(prefixResult.get());",
			"    Sys.println(step.get());",
			"    var postfixResult = step++;",
			"    Sys.println(postfixResult.get());",
			"    Sys.println(step.get());",
			"    var staticStep:StaticStep = new StaticStep(1);",
			"    var staticResult = ++staticStep;",
			"    Sys.println(staticResult);",
			"    Sys.println(staticStep.get());",
			"    var values:Array<Step> = [new Step(4)];",
			"    var indexedPrefix:Step = ++values[counter.chooseIndex()];",
			"    var indexedPostfix:Step = values[counter.chooseIndex()]++;",
			"    var indexedValue:Step = values[0];",
			"    Sys.println(indexedPrefix.get());",
			"    Sys.println(indexedPostfix.get());",
			"    Sys.println(indexedValue.get());",
			"    Sys.println(counter.indexCalls);",
			"    var fieldPrefix:Step = ++counter.chooseHolder().step;",
			"    var fieldPostfix:Step = counter.chooseHolder().step++;",
			"    var fieldValue:Step = counter.holder.step;",
			"    Sys.println(fieldPrefix.get());",
			"    Sys.println(fieldPostfix.get());",
			"    Sys.println(fieldValue.get());",
			"    Sys.println(counter.receiverCalls);",
			"    var ordinary = 8;",
			"    Sys.println(++ordinary);",
			"    Sys.println(ordinary++);",
			"    Sys.println(ordinary);",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(source, "Main.hx");
		final resolved = new ResolvedModule("Main", "Main.hx", parsed);
		final index = TyperIndex.build([resolved]);
		final loader = new ModuleLoader(["."], new StringMap<String>(), index, function(_):Bool return false);
		loader.markResolvedAlready([resolved]);
		final typed = TyperStage.typeResolvedModule(resolved, index, loader);
		final program = new MacroExpandedProgram([typed], false);

		final root = Path.join([Sys.getCwd(), ".tmp", "m14_cpp_abstract_unary"]);
		deleteRecursive(root);
		FileSystem.createDirectory(root);
		final context = new BackendContext(root, null, "Main", true, true, new StringMap<String>());
		final result = BackendRegistry.createForTarget("cpp-native").emit(program, context);
		assertTrue(result.builtExecutable, "focused abstract-unary C++ artifact did not build");
		final sourcePath = Path.join([root, "src", "Main.cpp"]);
		final generated = File.getContent(sourcePath);
		assertContains(generated, "Boxed::turnInsideOut(boxed)", "class-backed unary minus did not call its arbitrary-name helper");
		assertContains(generated, "Step::reverseSign(step)", "primitive-backed unary minus did not call its arbitrary-name helper");
		assertContains(generated, "StaticStep::surprising(staticStep)", "static prefix helper was not emitted as a call");
		assertContains(generated, "Step::get(", "primitive abstract results lost the exact get helper after carrier erasure");
		assertTrue(generated.indexOf("advanceBefore(") < 0 && generated.indexOf("advanceAfter(") < 0,
			"inline mutation helpers survived for backend reinterpretation");
		assertTrue(generated.indexOf("(-boxed)") < 0, "C++ applied raw unary minus to the class-backed abstract wrapper");

		final executed = commandOutput(result.entryPath);
		assertTrue(executed.code == 0, "focused abstract-unary executable failed: " + executed.stderr);
		final expected = "-7\n-12\n12\n22\n22\n22\n122\n11\n1\n14\n14\n114\n4\n15\n15\n115\n2\n9\n9\n10\n";
		assertTrue(executed.stdout == expected, "unexpected focused abstract-unary stdout:\n" + executed.stdout);
		deleteRecursive(root);
	}
}
