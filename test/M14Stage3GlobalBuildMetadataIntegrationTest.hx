import hxhx.BuildMetadataCollector;
import hxhx.Stage3BuildMacroSupport;
import hxhx.Stage3BuildMacroPreparer;
import hxhx.macro.MacroState;
import hxhx.macro.MacroRuntimeMode;

class M14Stage3GlobalBuildMetadataIntegrationTest {
	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function assertContains(label:String, values:Array<String>, expected:String):Void {
		if (values.indexOf(expected) >= 0)
			return;
		throw label + ': expected "' + expected + '" in [' + values.join(", ") + ']';
	}

	static function assertNotContains(label:String, values:Array<String>, unexpected:String):Void {
		if (values.indexOf(unexpected) < 0)
			return;
		throw label + ': did not expect "' + unexpected + '" in [' + values.join(", ") + ']';
	}

	static function generatedReturnType(module:ResolvedModule, functionName:String):String {
		final declaration = ResolvedModule.getParsed(module).getDecl();
		for (fn in HxClassDecl.getFunctions(HxModuleDecl.getMainClass(declaration)))
			if (HxFunctionDecl.getName(fn) == functionName)
				return HxFunctionDecl.getReturnTypeHint(fn);
		return "<missing>";
	}

	static function main():Void {
		final source = [
			"@:build(hxhxmacros.BuildFieldMacros.addGeneratedField())",
			"class Target {",
			"}"
		].join("\n");

		MacroState.reset();
		MacroState.registerGlobalMetadata("", "@:build(hxhxmacros.BuildFieldMacros.addGeneratedField())", true, true, false);
		MacroState.registerGlobalMetadata("demo.Target", "@:autoBuild(hxhxmacros.ReturnFieldMacros.addGeneratedFieldReturn())", false, true, false);
		MacroState.registerGlobalMetadata("demo.pkg", '@:build(hxhxmacros.ArgsMacros.setArg("pkg"))', true, true, false);
		MacroState.registerGlobalMetadata("demo.Target", "@:build(hxhxmacros.ArgsMacros.setArg(\"field-only\"))", false, false, true);
		MacroState.registerGlobalMetadata("demo.Target", "@:demoMeta", false, true, true);

		final targetExprs = BuildMetadataCollector.collectBuildMacroExprs(source, "demo.Target");
		assertTrue(targetExprs.length == 2, "expected deduped source+global build exprs for exact target");
		assertContains("exact target source/global build", targetExprs, "hxhxmacros.BuildFieldMacros.addGeneratedField()");
		assertContains("exact target autoBuild", targetExprs, "hxhxmacros.ReturnFieldMacros.addGeneratedFieldReturn()");
		assertNotContains("exact target field-only rule", targetExprs, 'hxhxmacros.ArgsMacros.setArg("field-only")');
		assertNotContains("exact target non-build metadata", targetExprs, "@:demoMeta");

		final recursiveExprs = BuildMetadataCollector.collectBuildMacroExprs("class Other {}", "demo.pkg.Inner");
		assertTrue(recursiveExprs.length == 2, "expected root recursive rule plus package-recursive rule");
		assertContains("recursive package root rule", recursiveExprs, "hxhxmacros.BuildFieldMacros.addGeneratedField()");
		assertContains("recursive package match", recursiveExprs, 'hxhxmacros.ArgsMacros.setArg("pkg")');
		assertNotContains("recursive package exact rule", recursiveExprs, "hxhxmacros.ReturnFieldMacros.addGeneratedFieldReturn()");

		final unrelatedExprs = BuildMetadataCollector.collectBuildMacroExprs("class Other {}", "elsewhere.Main");
		assertTrue(unrelatedExprs.length == 1, "expected only root recursive build rule for unrelated module");
		assertContains("unrelated module root rule", unrelatedExprs, "hxhxmacros.BuildFieldMacros.addGeneratedField()");
		assertNotContains("unrelated module package rule", unrelatedExprs, 'hxhxmacros.ArgsMacros.setArg("pkg")');

		final parsed = ParserStage.parse(source, "Target.hx");
		final resolved = new ResolvedModule("Target", "Target.hx", parsed);
		final generatedIntText = "public static function generated_answer():Int return 42;";
		final generatedStringText = 'public static function generated_answer():String return "private-generated-value";';
		final generatedInt = Stage3BuildMacroSupport.applyGeneratedMembers(resolved, [generatedIntText]);
		final generatedString = Stage3BuildMacroSupport.applyGeneratedMembers(resolved, [generatedStringText]);
		assertTrue(generatedReturnType(generatedInt, "generated_answer") == "Int", "generated Int member should be merged before typing");
		assertTrue(generatedReturnType(generatedString, "generated_answer") == "String", "generated String member should be merged before typing");
		final intObservation = ResolvedModule.getGeneratedDeclarations(generatedInt);
		final stringObservation = ResolvedModule.getGeneratedDeclarations(generatedString);
		assertTrue(intObservation.getCanonicalIdentity() != stringObservation.getCanonicalIdentity(),
			"different generated declarations should have different observations");
		assertTrue(intObservation.getCanonicalIdentity().indexOf(generatedIntText) < 0
			&& stringObservation.getCanonicalIdentity().indexOf("private-generated-value") < 0,
			"generated-declaration observations must not retain raw member text");
		final index = TyperIndex.build([generatedInt]);
		final loader = new ModuleLoader(["."], new haxe.ds.StringMap<String>(), index);
		loader.markResolvedAlready([generatedInt]);
		final typed = TyperStage.typeResolvedModule(generatedInt, index, loader, true);
		assertTrue(typed.getGeneratedDeclarations().getCanonicalIdentity() == intObservation.getCanonicalIdentity(),
			"typing should preserve the exact generated-declaration observation");

		var runCount = 0;
		var sessionClosed = false;
		final session:hxhx.macro.MacroRuntimeSession = {
			run: function(_):String {
				runCount += 1;
				MacroState.emitBuildFields("Target", generatedIntText);
				return "ok";
			},
			runHook: function(_, _):Void {},
			runTypeNotFoundHook: function(_, _):Bool return false,
			expandExpr: function(expr):String return expr,
			close: function():Void sessionClosed = true
		};
		final request = hxhx.CompilationRequestContext.direct();
		final preparer = new Stage3BuildMacroPreparer(MacroRuntimeMode.INPROC, false, true, [], request, session);
		final firstPrepared = preparer.prepare(resolved);
		final repeatedPrepared = preparer.prepare(resolved);
		assertTrue(runCount == 1, "one request should run a module's build macro only once");
		assertTrue(ResolvedModule.getGeneratedDeclarations(firstPrepared).getCanonicalIdentity() == intObservation.getCanonicalIdentity(),
			"request-owned preparation should produce the same generated-declaration identity as direct root preparation");
		assertTrue(ResolvedModule.getGeneratedDeclarations(firstPrepared)
			.getCanonicalIdentity() == ResolvedModule.getGeneratedDeclarations(repeatedPrepared)
			.getCanonicalIdentity(),
			"repeated preparation should return the same generated-declaration result");
		preparer.close();
		assertTrue(sessionClosed, "closing module preparation should close its request-owned macro session");
		request.close(false);

		final failingSession:hxhx.macro.MacroRuntimeSession = {
			run: function(_):String throw "forced build-macro failure",
			runHook: function(_, _):Void {},
			runTypeNotFoundHook: function(_, _):Bool return false,
			expandExpr: function(expr):String return expr,
			close: function():Void {}
		};
		final failingRequest = hxhx.CompilationRequestContext.server(1);
		final failingPreparer = new Stage3BuildMacroPreparer(MacroRuntimeMode.INPROC, false, true, [], failingRequest, failingSession);
		var failure:Null<String> = null;
		try {
			failingPreparer.prepare(resolved);
		} catch (error:hxhx.Stage3BuildMacroPreparationError) {
			failure = error.message;
		}
		assertTrue(failure != null && failure.indexOf("forced build-macro failure") >= 0,
			"module preparation should report a macro failure instead of exposing a partial module");
		failingPreparer.close();
		failingRequest.close(false);

		var cancelledRunCount = 0;
		final cancelledSession:hxhx.macro.MacroRuntimeSession = {
			run: function(_):String {
				cancelledRunCount += 1;
				return "unexpected";
			},
			runHook: function(_, _):Void {},
			runTypeNotFoundHook: function(_, _):Bool return false,
			expandExpr: function(expr):String return expr,
			close: function():Void {}
		};
		final cancelledRequest = hxhx.CompilationRequestContext.server(2);
		cancelledRequest.requestCancellation("fixture-cancelled");
		final cancelledPreparer = new Stage3BuildMacroPreparer(MacroRuntimeMode.INPROC, false, true, [], cancelledRequest, cancelledSession);
		var cancellationObserved = false;
		try {
			cancelledPreparer.prepare(resolved);
		} catch (error:hxhx.Stage3BuildMacroPreparationError) {
			cancellationObserved = error.cancelled;
		}
		assertTrue(cancellationObserved && cancelledRunCount == 0, "a cancelled request should stop before running or publishing a build-macro result");
		cancelledPreparer.close();
		cancelledRequest.close(false);
		MacroState.reset();
	}
}
