import backend.BackendContext;
import backend.vm.NekoTargetCore;
import sys.io.File;

/** Abstract evaluation temporaries remain exact locals before and after control lowering. */
class M14AbstractCaptureTemporaryTest {
	/** A temporary needs a real compiler declaration; a matching spelling cannot supply its authority. */
	static function assertTemporaryOwnership(fn:TypedFunction):Void {
		var selected:Null<TypedExpr> = null;
		function visit(expression:TypedExpr):Void {
			if (selected == null && expression.getTag() == Temporary)
				selected = expression;
			for (child in expression.getExpressions())
				visit(child);
		}
		function statement(node:TypedStmt):Void {
			for (expression in node.getExpressions())
				visit(expression);
			for (child in node.getStatements())
				statement(child);
		}
		for (node in fn.getBody().getStatements())
			statement(node);
		if (selected == null)
			throw "fixture must contain an operator-generated temporary";
		final original = selected;
		final binding = original.getLocalBindings()[0];
		function reject(replacement:TypedExpr, fragment:String):Void {
			final changed = @:privateAccess M14TypedCaptureLoweringTest.replace(fn, original, replacement);
			var diagnostic = "";
			try
				TypedCapturePlan.analyze(changed)
			catch (failure:haxe.Exception)
				diagnostic = failure.message;
			if (diagnostic.indexOf(fragment) < 0)
				throw "capture analysis accepted invalid temporary ownership: " + diagnostic;
		}
		function temporary(local:Null<TyLocalBinding>):TypedExpr {
			return TypedExpr.temporary(binding.getSourceName(), binding.getType().getDisplay(), original.getExpressions()[0], original.getType(),
				original.getPosition(), local);
		}
		reject(temporary(null), "one exact compiler binding");
		final foreign = new TyCompilerTemporaryAllocator("foreign-function", "test-v1", "temporary_").allocate("value", binding.getType());
		reject(temporary(foreign), "another typed function");
		final impostor = new TyLocalBinding(TyLocalId.forSourceDeclaration(fn.getStableIdentity(), 999, CompilerTemporary, binding.getSourceName()),
			binding.getSourceName(), binding.getType(), CompilerTemporary);
		reject(temporary(impostor), "one exact compiler binding");
		reject(original.withExpressions([TypedExpr.boolLiteral(true, TyType.fromHintText("Bool"), null)]), "matching initializer type");
		Sys.println("ABSTRACT_CAPTURE_TEMPORARY_OWNERSHIP:PASS");
	}

	static function main():Void {
		final source = 'abstract Counter(Int) from Int to Int {
@:op(A+B) public static function add(left:Counter, right:Counter):Counter {return (left:Int)+(right:Int);}
}
class Main {
static var effects=0;
static function operand():Counter {effects++; if(effects==2) throw 5; return 1;}
static function branchOperand(value:Int):Counter {effects++;return value;}
static function branch(flag:Bool):Int {var value:Counter=2; return flag ? value+branchOperand(3) : value+branchOperand(5);}
static function conjunction(flag:Bool):Bool {var value:Counter=2;return flag && (value+branchOperand(3):Int)>0;}
static function disjunction(flag:Bool):Bool {var value:Counter=2;return flag || (value+branchOperand(3):Int)>0;}
static function make(seed:Int):Void->Int {
var value:Counter=seed;
return function():Int {value=value+1;return value;};
}
static function main():Void {
var first=make(2); var second=make(8);
Sys.println(first()); Sys.println(first()); Sys.println(second());
try {var unused=operand()+operand(); Sys.println("wrong");} catch(error:Dynamic) {Sys.println(error);}
Sys.println(effects);
effects=0; Sys.println(branch(true)); Sys.println(branch(false)); Sys.println(effects);
effects=0; Sys.println(conjunction(false)); Sys.println(disjunction(true)); Sys.println(effects);
Sys.println(conjunction(true)); Sys.println(disjunction(false)); Sys.println(effects);
}
}';
		final expected = "3\n4\n9\n5\n2\n5\n7\n2\nfalse\ntrue\n0\ntrue\ntrue\n2\n";
		final root = ".tmp/abstract_capture_temporary_" + Date.now().getTime();
		sys.FileSystem.createDirectory(root);
		File.saveContent(root + "/Main.hx", source);
		@:privateAccess M14JsRuntimeTypeOperandsTest.run("haxe", ["-cp", root, "-main", "Main", "-neko", root + "/upstream.n"]);
		if (@:privateAccess M14JsRuntimeTypeOperandsTest.run("neko", [root + "/upstream.n"]) != expected)
			throw "upstream abstract capture behavior changed";
		Sys.println("ABSTRACT_CAPTURE_UPSTREAM:PASS");
		final resolved = new ResolvedModule("Main", root + "/Main.hx", ParserStage.parse(source, root + "/Main.hx"));
		final index = TyperIndex.buildHeaders([resolved]);
		final defines = HxDefineMap.fromRawDefines(["neko=1"]);
		final loader = new ModuleLoader([root], defines, index);
		loader.markResolvedAlready([resolved]);
		final typed = TyperStage.typeResolvedModule(resolved, index, loader);
		final lowered = TypedAbstractOperatorLowering.lowerModules([typed], index);
		for (owner in lowered[0].getTypedClasses())
			for (fn in owner.getFunctions())
				if (HxFunctionDecl.getName(fn.getSourceDeclaration()) == "make") {
					assertTemporaryOwnership(fn);
					final plan = TypedCapturePlan.analyze(fn);
					if (plan.getFunctions().length != 2
						|| plan.getFunctions()[1].getCaptures().length != 1
						|| plan.getFunctions()[1].getCaptures()[0].getSourceName() != "value")
						throw "abstract lowering changed the authored closure captures";
					TypedCapturePlan.afterLowering(fn, TypedControlLowering.functionBody(fn));
				}
		final program = new MacroExpandedProgram(lowered, false);
		final context = new BackendContext(root, root + "/main.n", "Main", true, false, defines);
		final split = @:privateAccess NekoTargetCore.renderSplitProgram(program, context, root + "/main.neko");
		File.saveContent(split.entryPath, split.entrySource);
		for (part in split.support)
			File.saveContent(part.path, part.source);
		File.saveContent(root + "/single.neko", @:privateAccess NekoTargetCore.renderProgram(program, context));
		for (name in sys.FileSystem.readDirectory(root))
			if (StringTools.endsWith(name, ".neko"))
				@:privateAccess M14JsRuntimeTypeOperandsTest.run("nekoc", [root + "/" + name]);
		for (layout in ["main", "single"]) {
			if (@:privateAccess M14JsRuntimeTypeOperandsTest.run("neko", [root + "/" + layout + ".n"]) != expected)
				throw "abstract capture runtime differs in " + layout;
			Sys.println("ABSTRACT_CAPTURE_NATIVE:PASS layout=" + layout);
		}
	}
}
