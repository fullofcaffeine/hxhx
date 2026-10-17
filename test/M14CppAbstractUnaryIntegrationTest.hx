import backend.BackendContext;
import backend.BackendRegistry;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/** Builds and executes the repo-owned abstract-unary contract through native C++. **/
class M14CppAbstractUnaryIntegrationTest {
	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	/** Inspect the prepared entry rather than incidental names assigned to C++ functions. */
	static function mainExpressions(program:MacroExpandedProgram):Array<TypedExpr> {
		final expressions = new Array<TypedExpr>();
		function expression(value:TypedExpr):Void {
			expressions.push(value);
			for (child in value.getExpressions())
				expression(child);
		}
		function statement(value:TypedStmt):Void {
			for (child in value.getExpressions())
				expression(child);
			for (child in value.getStatements())
				statement(child);
		}
		for (module in program.getTypedModules())
			if (module.getSourceOrigin().sourceModulePath == "Main")
				for (owner in module.getTypedClasses())
					if (HxClassDecl.getName(owner.getSourceDeclaration()) == "Main")
						for (fn in owner.getFunctions())
							if (HxFunctionDecl.getName(fn.getSourceDeclaration()) == "main") {
								for (child in fn.getBody().getStatements())
									statement(child);
								return expressions;
							}
		throw "abstract-unary fixture lost its exact Main.main body";
	}

	/** Keep the selected owner, helper, and source operand independent of native symbol numbering. */
	static function selectedCalls(expressions:Array<TypedExpr>, owner:String, method:String, ?argumentLocal:String):Array<TypedExpr> {
		final calls = new Array<TypedExpr>();
		for (expression in expressions) {
			final declaration = expression.getDeclaration();
			if (expression.getTag() != Call
				|| declaration == null
				|| declaration.getModulePath() != "Main"
				|| declaration.getOwner().getCanonicalName() != "Main." + owner
				|| declaration.getSignature().getName() != method)
				continue;
			if (argumentLocal != null) {
				final arguments = expression.getExpressions();
				var argument:TypedExpr;
				if (declaration.getIsStatic()) {
					assertTrue(arguments.length == 2, "static unary helper lost its single argument: " + method);
					argument = arguments[1];
				} else {
					assertTrue(arguments.length == 1 && arguments[0].getTag() == FieldRead && arguments[0].getExpressions().length == 1,
						"instance unary helper lost its receiver: " + method);
					argument = arguments[0].getExpressions()[0];
				}
				while (argument.getTag() == Cast && argument.isRepresentationPreservingCast())
					argument = argument.getExpressions()[0];
				assertTrue(argument.getTag() == LocalRead && argument.getTexts()[0] == argumentLocal, "unary helper changed its source operand: " + method);
			}
			calls.push(expression);
		}
		return calls;
	}

	/** Exact shared decisions plus native output preserve the old generated-call assertions. */
	static function assertPreparedOperators(program:MacroExpandedProgram):Void {
		final expressions = mainExpressions(program);
		for (helper in [
			{owner: "Boxed", method: "turnInsideOut", operand: "boxed"},
			{owner: "Step", method: "reverseSign", operand: "step"},
			{owner: "StaticStep", method: "surprising", operand: "staticStep"}
		])
			assertTrue(selectedCalls(expressions, helper.owner, helper.method, helper.operand).length == 1,
				"unary operator lost its exact arbitrary-name helper: "
				+ helper.owner
				+ "."
				+ helper.method);
		assertTrue(selectedCalls(expressions, "PropertyHolder", "get_step").length == 2, "property updates lost their exact getters");
		assertTrue(selectedCalls(expressions, "PropertyHolder", "set_step").length == 2, "property updates lost their exact setters");
		assertTrue(selectedCalls(expressions, "Step", "get").length > 0, "primitive abstract results lost the exact get helper");
		for (method in ["advanceBefore", "advanceAfter"])
			assertTrue(selectedCalls(expressions, "Step", method).length == 0, "inline mutation helper survived for backend reinterpretation: " + method);
		for (expression in expressions)
			if (expression.getTag() == Unary) {
				final identity = expression.getExpressions()[0].getType().getNominalIdentity();
				assertTrue(identity == null
					|| identity.getCanonicalName() != "Main.Boxed", "raw unary operator retained its class-backed operand");
			}
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

	static function commandOutput(command:String, ?arguments:Array<String>):{code:Int, stdout:String, stderr:String} {
		final process = new sys.io.Process(command, arguments == null ? [] : arguments);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		return {code: code, stdout: stdout, stderr: stderr};
	}

	/** Compare every output value under collection at each allocation and both sanitizer build profiles. */
	static function assertSanitized(root:String, expected:String):Void {
		File.copy("test/cpp_managed_heap/StandardStringObserver.cpp", root + "/Observer.cpp");
		final compiler = Sys.getEnv("CXX") == null ? "clang++" : Sys.getEnv("CXX");
		final timeout = Sys.systemName() == "Mac" ? "gtimeout" : "timeout";
		for (optimization in ["-O0", "-O2"]) {
			final executable = root + "/observer" + optimization;
			final compiled = Sys.command(timeout, [
				"90",
				compiler,
				"-std=c++17",
				optimization,
				"-g1",
				"-fno-omit-frame-pointer",
				"-fsanitize=address,undefined",
				"-fno-sanitize-recover=all",
				'-DHXHX_LOCAL_PROGRAM="src/Main.cpp"',
				root + "/Observer.cpp",
				"-o",
				executable
			]);
			assertTrue(compiled == 0, "abstract-unary sanitizer compilation failed: " + optimization + " exit=" + compiled);
			final executed = commandOutput(timeout, ["30", executable]);
			assertTrue(executed.code == 0 && executed.stderr == "" && executed.stdout == expected,
				"abstract-unary sanitizer behavior differs: "
				+ optimization
				+ " exit="
				+ executed.code
				+ "\n"
				+ executed.stdout
				+ executed.stderr);
			Sys.println("CPP_ABSTRACT_UNARY:SANITIZERS:" + optimization + ":PASS");
		}
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
			"  public var propertyReceiverCalls:Int = 0;",
			"  public var holder:Holder;",
			"  public var propertyHolder:PropertyHolder;",
			"  public function new() { holder = new Holder(5); propertyHolder = new PropertyHolder(9); }",
			"  public function chooseIndex():Int { indexCalls++; return 0; }",
			"  public function chooseHolder():Holder { receiverCalls++; return holder; }",
			"  public function choosePropertyHolder():PropertyHolder { propertyReceiverCalls++; return propertyHolder; }",
			"}",
			"class Holder {",
			"  public var step:Step;",
			"  public function new(value:Int) step = new Step(value);",
			"}",
			"class PropertyHolder {",
			"  public var getterCalls:Int = 0;",
			"  public var setterCalls:Int = 0;",
			"  var stored:Step;",
			"  public var step(get, set):Step;",
			"  public function new(value:Int) stored = new Step(value);",
			"  public function get_step():Step { getterCalls++; return stored; }",
			"  public function set_step(value:Step):Step { setterCalls++; stored = value; return value; }",
			"  public function value():Step return stored;",
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
			"    var propertyPrefix:Step = ++counter.choosePropertyHolder().step;",
			"    var propertyPostfix:Step = counter.choosePropertyHolder().step++;",
			"    var propertyValue:Step = counter.propertyHolder.value();",
			"    Sys.println(propertyPrefix.get());",
			"    Sys.println(propertyPostfix.get());",
			"    Sys.println(propertyValue.get());",
			"    Sys.println(counter.propertyReceiverCalls);",
			"    Sys.println(counter.propertyHolder.getterCalls);",
			"    Sys.println(counter.propertyHolder.setterCalls);",
			"    var ordinary = 8;",
			"    Sys.println(++ordinary);",
			"    Sys.println(ordinary++);",
			"    Sys.println(ordinary);",
			"  }",
			"}",
		].join("\n");
		final root = Path.join([Sys.getCwd(), ".tmp", "m14_cpp_abstract_unary"]);
		deleteRecursive(root);
		final sourceRoot = Path.join([root, "input"]);
		FileSystem.createDirectory(sourceRoot);
		File.saveContent(Path.join([sourceRoot, "Main.hx"]), source);
		final expected = "-7\n-12\n12\n22\n22\n22\n122\n11\n1\n14\n14\n114\n4\n15\n15\n115\n2\n10\n10\n11\n2\n2\n2\n9\n9\n10\n";
		final upstream = commandOutput("haxe", ["-cp", sourceRoot, "--run", "Main"]);
		assertTrue(upstream.code == 0 && upstream.stderr == "" && upstream.stdout == expected,
			"upstream abstract-unary contract differs: " + upstream.stdout + upstream.stderr);
		Sys.println("CPP_ABSTRACT_UNARY:UPSTREAM:PASS");
		// Output and array calls need their real declarations before native emission.
		// Retain every provider body through the same preparation used by other native fixtures.
		final fixture = CppResolvedFixture.load({sourceRoot: sourceRoot, mainModule: "Main", requiredModules: ["Sys", "Array"]});
		final revisions = [
			for (module in fixture.modules)
				CompilerTypedModuleRevision.fromTypedModule(module).getCanonicalIdentity()
		];
		Sys.println("CPP_ABSTRACT_UNARY:LOADED modules=" + fixture.modules.length);
		final program = CppResolvedFixture.prepare(fixture);
		assertPreparedOperators(program);
		Sys.println("CPP_ABSTRACT_UNARY:PREPARED");
		final context = new BackendContext(root, null, "Main", true, true, fixture.defines);
		final result = BackendRegistry.createForTarget("cpp-native").emit(program, context);
		assertTrue(result.builtExecutable, "focused abstract-unary C++ artifact did not build");
		for (index in 0...fixture.modules.length)
			assertTrue(revisions[index] == CompilerTypedModuleRevision.fromTypedModule(fixture.modules[index]).getCanonicalIdentity(),
				"abstract-unary preparation changed an authored typed module");

		final executed = commandOutput(result.entryPath);
		assertTrue(executed.code == 0 && executed.stderr == "", "focused abstract-unary executable failed: " + executed.stderr);
		assertTrue(executed.stdout == expected, "unexpected focused abstract-unary stdout:\n" + executed.stdout);
		assertSanitized(root, expected);
		Sys.println("CPP_ABSTRACT_UNARY:PASS");
		deleteRecursive(root);
	}
}
