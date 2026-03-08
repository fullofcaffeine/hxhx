import haxe.io.Path;
import hxhx.macro.MacroHostClient;
import hxhx.macro.MacroState;
import sys.io.Process;

class M14MacroHostRuntimeApiIntegrationTest {
	static function fail(message:String):Void {
		throw message;
	}

	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			fail(message);
	}

	static function assertContains(label:String, actual:String, expected:String):Void {
		if (actual.indexOf(expected) >= 0)
			return;
		fail(label + ': expected "' + expected + '" in "' + actual + '"');
	}

	static function runShell(command:String):{code:Int, stdout:String, stderr:String} {
		final process = new Process("sh", ["-lc", command]);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		return {code: code, stdout: stdout, stderr: stderr};
	}

	static function lastNonEmptyLine(text:String):String {
		if (text == null)
			return "";
		final lines = text.split("\n");
		var i = lines.length - 1;
		while (i >= 0) {
			final trimmed = StringTools.trim(lines[i]);
			if (trimmed.length > 0)
				return trimmed;
			i -= 1;
		}
		return "";
	}

	static function buildMacroHostWithProbe():String {
		final exprs = [
			"hxhxmacros.RuntimeContextApiMacros.probeConfigAndPosition()",
			"hxhxmacros.RuntimeContextApiMacros.probeAfterInitMacros()",
			"hxhxmacros.RuntimeContextApiMacros.probeBuiltinTypePlumbing()",
			"hxhxmacros.RuntimeContextApiMacros.probeTypeParameterSubstitution()",
			"hxhxmacros.RuntimeContextApiMacros.probeLocalContextSnapshot()",
			"hxhxmacros.RuntimeContextApiMacros.probeCallArguments()",
			"hxhxmacros.RuntimeContextApiMacros.probeLocalImports()",
			"hxhxmacros.RuntimeContextApiMacros.probeLocalUsing()",
			"hxhxmacros.RuntimeContextApiMacros.probeLocalTVars()",
			"hxhxmacros.RuntimeContextApiMacros.probeModuleLookup()",
			"hxhxmacros.RuntimeContextApiMacros.probeModuleFieldCarrier()",
			"hxhxmacros.RuntimeContextApiMacros.probeSyntheticTypeStatics()",
			"hxhxmacros.RuntimeContextApiMacros.probeTypedExprPlumbing()",
			"hxhxmacros.RuntimeContextApiMacros.probeTypedVarExprPlumbing()",
			"hxhxmacros.RuntimeContextApiMacros.probeMainExpr()",
			"hxhxmacros.RuntimeContextApiMacros.probeStoreExprPlumbing()",
			"hxhxmacros.RuntimeContextApiMacros.probeCompilerInclude()",
			"hxhxmacros.RuntimeContextApiMacros.probeCompilerMetadataRegistration()",
			"hxhxmacros.RuntimeContextApiMacros.probeOnTypeNotFoundRegistration()",
			"hxhxmacros.RuntimeContextApiMacros.probeRegisterModuleDependency()",
			"hxhxmacros.RuntimeContextApiMacros.probeDefineType()",
			"hxhxmacros.RuntimeContextApiMacros.probeDefineModule()",
			"hxhxmacros.RuntimeContextApiMacros.probeResources()",
			"hxhxmacros.RuntimeContextApiMacros.probeMessages()",
			"hxhxmacros.RuntimeContextApiMacros.probeParse()",
			"hxhxmacros.RuntimeContextApiMacros.probeMakeExprAndSignature()",
			"hxhxmacros.RuntimeContextApiMacros.probeTimer()"
		];
		final command = [
			'HXHX_MACRO_HOST_FORCE_STAGE0=1',
			'HXHX_MACRO_HOST_ENTRYPOINTS=\'${exprs.join(";")}\'',
			'HXHX_MACRO_HOST_EXTRA_CP=\'test/fixtures/hxhx-macros/src\'',
			'bash scripts/hxhx/build-hxhx-macro-host.sh 2>&1'
		].join(" ");
		final result = runShell(command);
		if (result.code != 0)
			fail("macro host build failed: " + result.stdout + result.stderr);
		final exe = lastNonEmptyLine(result.stdout);
		if (exe.length == 0)
			fail("macro host build produced no executable path: " + result.stdout);
		return exe;
	}

	static function main():Void {
		final originalHostExe = Sys.getEnv("HXHX_MACRO_HOST_EXE");
		final generatedHxDir = ".tmp/m14-runtime-generated-hx";
		MacroState.reset();
		MacroState.seedFromCliDefines(["reflaxe-target=ocaml", "target.name=ocaml"]);
		MacroState.seedCompilerConfiguration(["--ocaml", "-main", "Main", "--no-output"], ["/virtual/haxe/std"], "ocaml");
		MacroState.addClassPath("test/fixtures/hxhx-macros/src");
		MacroState.setGeneratedHxDir(generatedHxDir);
		MacroState.setCurrentPos({
			file: Path.normalize("test/fixtures/hxhx-macros/src/hxhxmacros/RuntimeContextApiMacros.hx"),
			min: 12,
			max: 34
		});
		MacroState.setLocalContext({
			modulePath: "hxhxmacros.RuntimeContextApiMacros",
			methodName: "probeLocalContextSnapshot",
			localTypeText: "String",
			expectedTypeText: "Bool",
			callArgumentExprTexts: ["1", "2 + 3", "{ ok: true }"],
			localTVars: [
				{
					name: "count",
					typeText: "Int",
					id: 1,
					capture: false,
					isStatic: false
				},
				{
					name: "label",
					typeText: "String",
					id: 2,
					capture: true,
					isStatic: false
				}
			]
		});
		MacroState.setMainExprText("1 + 2");
		MacroState.registerGlobalMetadata("hxhxmacros.RuntimeModuleState", "@:runtimeEnumMeta", false, true, false);
		MacroState.registerGlobalMetadata("hxhxmacros.RuntimeModuleData", "@:runtimeTypedefMeta", false, true, false);
		MacroState.registerGlobalMetadata("hxhxmacros.RuntimeModuleId", "@:runtimeAbstractMeta", false, true, false);
		MacroState.registerGlobalMetadata("generated.runtime.RuntimeMacroDefined", "@:generatedMeta", false, true, false);
		MacroState.registerGlobalMetadata("generated.runtime.RuntimeMacroDefined", "@:nullSafety(Strict)", false, true, false);
		MacroState.registerGlobalMetadata("generated.runtime.RuntimeMacroModule", "@:moduleMeta", false, true, false);
		MacroState.registerGlobalMetadata("generated.runtime.RuntimeMacroModule.RuntimeMacroHelper", "@:helperMeta", false, true, false);

		var failure = "";
		try {
			final exe = buildMacroHostWithProbe();
			assertContains("macro host build dir", exe, ".tmp/hxhx-macro-host-build.");
			Sys.putEnv("HXHX_MACRO_HOST_EXE", exe);

			final output = MacroHostClient.run("hxhxmacros.RuntimeContextApiMacros.probeConfigAndPosition()");
			assertContains("probe version", output, "cfg.version=40307");
			assertContains("probe args", output, "args=4");
			assertContains("probe std", output, "std=1");
			assertContains("probe unicode", output, "unicode=1");
			assertContains("probe classpath", output, "cp=");
			assertContains("probe display", output, "display=None");
			assertContains("probe file", output, "file=test/fixtures/hxhx-macros/src/hxhxmacros/RuntimeContextApiMacros.hx");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_CONTEXT_ARGS") == "4", "expected runtime args define");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_CONTEXT_FILE") == "test/fixtures/hxhx-macros/src/hxhxmacros/RuntimeContextApiMacros.hx",
				"expected runtime file define");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_CONTEXT_MODE") == "None", "expected runtime display mode define");
			assertTrue(Std.parseInt(MacroState.definedValue("HXHX_RUNTIME_CONTEXT_CP")) > 0, "expected runtime classpath define");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_CONTEXT_RESOLVED").indexOf("RuntimeContextApiMacros.hx") >= 0,
				"expected resolved fixture path define");

			final afterInitOutput = MacroHostClient.run("hxhxmacros.RuntimeContextApiMacros.probeAfterInitMacros()");
			assertContains("after init output", afterInitOutput, "afterInit=callback;after");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_AFTER_INIT") == "ok", "expected runtime after-init define");

			final typeOutput = MacroHostClient.run("hxhxmacros.RuntimeContextApiMacros.probeBuiltinTypePlumbing()");
			assertContains("type probe getType", typeOutput, "getType=String");
			assertContains("type probe module getType", typeOutput, "moduleType=hxhxmacros.RuntimeContextApiMacros");
			assertContains("type probe module enum getType", typeOutput, "moduleEnumType=hxhxmacros.RuntimeModuleState");
			assertContains("type probe module typedef getType", typeOutput, "moduleTypedefType=hxhxmacros.RuntimeModuleData");
			assertContains("type probe module abstract getType", typeOutput, "moduleAbstractType=hxhxmacros.RuntimeModuleId");
			assertContains("type probe resolveType", typeOutput, "resolveType=Bool");
			assertContains("type probe nullType", typeOutput, "nullType=Null<String>");
			assertContains("type probe typeof", typeOutput, "typeof=Int");
			assertContains("type probe follow", typeOutput, "follow=Null<String>");
			assertContains("type probe unify", typeOutput, "unify=1");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_TYPE_BOOL") == "Bool", "expected runtime bool type define");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_TYPE_NULL") == "Null<String>", "expected runtime null type define");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_TYPE_LITERAL") == "Int", "expected runtime literal type define");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_TYPE_FOLLOW") == "Null<String>", "expected runtime follow define");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_TYPE_UNIFY") == "1", "expected runtime unify define");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_TYPE_MODULE") == "hxhxmacros.RuntimeContextApiMacros", "expected runtime module type define");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_TYPE_MODULE_ENUM") == "hxhxmacros.RuntimeModuleState", "expected runtime module enum type define");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_TYPE_MODULE_TYPEDEF") == "hxhxmacros.RuntimeModuleData",
				"expected runtime module typedef type define");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_TYPE_MODULE_ABSTRACT") == "hxhxmacros.RuntimeModuleId",
				"expected runtime module abstract type define");

			final typeParamOutput = MacroHostClient.run("hxhxmacros.RuntimeContextApiMacros.probeTypeParameterSubstitution()");
			assertContains("type param output", typeParamOutput, "typeParams=(String) -> Null<String>");
			assertContains("type param output", typeParamOutput, "iter=String|Null<String>");
			assertContains("type param output", typeParamOutput, "typedef=Bool");
			assertContains("type param output", typeParamOutput, "abstract=synthetic.AbstractBox<String>");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_TYPE_PARAMS") == "(String) -> Null<String>;String|Null<String>;Bool;synthetic.AbstractBox<String>",
				"expected runtime type-parameter define");

			final localContextOutput = MacroHostClient.run("hxhxmacros.RuntimeContextApiMacros.probeLocalContextSnapshot()");
			assertContains("local context module", localContextOutput, "module=hxhxmacros.RuntimeContextApiMacros");
			assertContains("local context method", localContextOutput, "method=probeLocalContextSnapshot");
			assertContains("local context local type", localContextOutput, "localType=String");
			assertContains("local context expected type", localContextOutput, "expectedType=Bool");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_LOCAL_MODULE") == "hxhxmacros.RuntimeContextApiMacros", "expected local module define");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_LOCAL_METHOD") == "probeLocalContextSnapshot", "expected local method define");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_LOCAL_TYPE") == "String", "expected local type define");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_EXPECTED_TYPE") == "Bool", "expected expected type define");

			final callArgumentsOutput = MacroHostClient.run("hxhxmacros.RuntimeContextApiMacros.probeCallArguments()");
			assertContains("call arguments summary", callArgumentsOutput, "callArgs=1;(2+3);{ok:true}");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_CALL_ARGUMENTS") == "1;(2+3);{ok:true}", "expected call arguments define");

			final localImportsOutput = MacroHostClient.run("hxhxmacros.RuntimeContextApiMacros.probeLocalImports()");
			assertContains("local imports String", localImportsOutput, "INormal:String");
			assertContains("local imports Template alias", localImportsOutput, "IAsName(T):haxe.Template");
			assertContains("local imports wildcard", localImportsOutput, "IAll:haxe.macro");
			assertContains("local imports define", MacroState.definedValue("HXHX_RUNTIME_LOCAL_IMPORTS"), "IAsName(T):haxe.Template");

			final localUsingOutput = MacroHostClient.run("hxhxmacros.RuntimeContextApiMacros.probeLocalUsing()");
			assertContains("local using StringTools", localUsingOutput, "StringTools");
			assertContains("local using Path", localUsingOutput, "haxe.io.Path");
			assertContains("local using define", MacroState.definedValue("HXHX_RUNTIME_LOCAL_USING"), "haxe.io.Path");

			final localTVarsOutput = MacroHostClient.run("hxhxmacros.RuntimeContextApiMacros.probeLocalTVars()");
			assertContains("local tvars count", localTVarsOutput, "count:Int:1:plain");
			assertContains("local tvars label", localTVarsOutput, "label:String:2:capture");
			assertContains("local tvars define", MacroState.definedValue("HXHX_RUNTIME_LOCAL_TVARS"), "label:String:2:capture");

			final moduleOutput = MacroHostClient.run("hxhxmacros.RuntimeContextApiMacros.probeModuleLookup()");
			assertContains("module lookup output", moduleOutput, "hxhxmacros.RuntimeModuleMembers");
			assertContains("module lookup output", moduleOutput, "hxhxmacros.RuntimeModuleHelper");
			assertContains("module lookup output", moduleOutput, "hxhxmacros.RuntimeModuleState");
			assertContains("module lookup output", moduleOutput, "hxhxmacros.RuntimeModuleData");
			assertContains("module lookup output", moduleOutput, "hxhxmacros.RuntimeModuleId");
			final moduleLookupDefine = MacroState.definedValue("HXHX_RUNTIME_MODULE_LOOKUP");
			assertContains("module lookup define", moduleLookupDefine, "hxhxmacros.RuntimeModuleMembers");
			assertContains("module lookup define", moduleLookupDefine, "hxhxmacros.RuntimeModuleState");

			final moduleFieldOutput = MacroHostClient.run("hxhxmacros.RuntimeContextApiMacros.probeModuleFieldCarrier()");
			assertContains("module field output", moduleFieldOutput,
				"moduleFields=featureEnabled;renderSummary;retryCount;routeTag;routerMarker;schemaMarker;sourceTag");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_MODULE_FIELDS") == "featureEnabled;renderSummary;retryCount;routeTag;routerMarker;schemaMarker;sourceTag",
				"expected runtime module field define");

			final typeStaticsOutput = MacroHostClient.run("hxhxmacros.RuntimeContextApiMacros.probeSyntheticTypeStatics()");
			assertContains("type statics output", typeStaticsOutput, "typeStatics=class=buildTag,classLabel;abstract=abstractLabel,renderTag");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_TYPE_STATICS") == "class=buildTag,classLabel;abstract=abstractLabel,renderTag",
				"expected runtime type statics define");

			final typedExprOutput = MacroHostClient.run("hxhxmacros.RuntimeContextApiMacros.probeTypedExprPlumbing()");
			assertContains("typed expr output", typedExprOutput, "typedExpr=");
			assertContains("typed expr type", typedExprOutput, "typedType=Int");
			assertContains("typed expr call type", typedExprOutput, "typedCallType=Dynamic");
			assertContains("typed expr object type", typedExprOutput, "typedObjectType=Dynamic");
			assertContains("typed expr array type", typedExprOutput, "typedArrayType=Dynamic");
			assertContains("typed expr type path", typedExprOutput, "typedTypeExprPath=hxhxmacros.RuntimeModuleMembers.RuntimeModuleState");
			assertContains("typed expr lambda type", typedExprOutput, "typedLambdaType=(Dynamic) -> Dynamic");
			assertTrue(Std.parseInt(MacroState.definedValue("HXHX_RUNTIME_TYPED_EXPR_VISITS")) > 0, "expected typed expr visits define");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_TYPED_EXPR").indexOf("+") >= 0, "expected typed expr string define");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_TYPED_EXPR_DYNAMIC") == "Dynamic;Dynamic;Dynamic", "expected dynamic typed expr define");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_TYPED_EXPR_TYPE_PATH") == "hxhxmacros.RuntimeModuleMembers.RuntimeModuleState",
				"expected typed type-path define");
			assertContains("typed expr lambda define", MacroState.definedValue("HXHX_RUNTIME_TYPED_EXPR_LAMBDA"), "(Dynamic) -> Dynamic");
			assertContains("typed expr lambda define", MacroState.definedValue("HXHX_RUNTIME_TYPED_EXPR_LAMBDA"), "item");
			assertContains("typed expr lambda define", MacroState.definedValue("HXHX_RUNTIME_TYPED_EXPR_LAMBDA"), ".name");

			final typedVarExprOutput = MacroHostClient.run("hxhxmacros.RuntimeContextApiMacros.probeTypedVarExprPlumbing()");
			assertContains("typed var expr output", typedVarExprOutput, "typedVarExpr=");
			assertContains("typed var expr outer type", typedVarExprOutput, "typedVarType=Void");
			assertContains("typed var inner type", typedVarExprOutput, "varType=String");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_TYPED_VAR_EXPR").indexOf("var prefix") >= 0, "expected typed var string define");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_TYPED_VAR_TYPE") == "String", "expected typed var type define");

			final mainExprOutput = MacroHostClient.run("hxhxmacros.RuntimeContextApiMacros.probeMainExpr()");
			assertContains("main expr output", mainExprOutput, "mainExpr=");
			assertContains("main expr type", mainExprOutput, "mainType=Int");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_MAIN_EXPR").indexOf("+") >= 0, "expected runtime main expr define");

			final storeExprOutput = MacroHostClient.run("hxhxmacros.RuntimeContextApiMacros.probeStoreExprPlumbing()");
			assertContains("store expr output", storeExprOutput, "storeExpr=ok");
			assertContains("store typed expr output", storeExprOutput, "storeTypedExpr=binop");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_STORE_EXPR") == "ok", "expected runtime store expr define");

			final includeOutput = MacroHostClient.run("hxhxmacros.RuntimeContextApiMacros.probeCompilerInclude()");
			assertContains("include output", includeOutput, "include=hxhxmacros.RuntimeContextApiMacros");
			assertContains("include output recursive", includeOutput, "hxhxmacros.ArgsMacros");
			assertContains("include output recursive", includeOutput, "hxhxmacros.ReturnFieldMacros");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_INCLUDE").indexOf("hxhxmacros.ArgsMacros") >= 0, "expected recursive include define");
			assertTrue(MacroState.listIncludedModules().indexOf("hxhxmacros.RuntimeContextApiMacros") >= 0, "expected included module snapshot");
			assertTrue(MacroState.listIncludedModules().indexOf("hxhxmacros.ArgsMacros") >= 0, "expected recursive package include");
			assertTrue(MacroState.listIncludedModules().indexOf("hxhxmacros.RuntimeContextApiMacros") >= 0, "expected exact module include");

			final metadataOutput = MacroHostClient.run("hxhxmacros.RuntimeContextApiMacros.probeCompilerMetadataRegistration()");
			assertContains("metadata output", metadataOutput, "metadata=ok");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_METADATA") == "ok", "expected runtime metadata define");
			final metadataRules = MacroState.listGlobalMetadataRules();
			assertTrue(metadataRules.length >= 3, "expected global metadata rules snapshot");
			final metadataRuleSummary = [
				for (rule in metadataRules)
					rule.pathFilter
					+ "|"
					+ rule.metadata
					+ "|r="
					+ rule.recursive
					+ "|t="
					+ rule.toTypes
					+ "|f="
					+ rule.toFields].join(" ; ");
			var sawBuildRule = false;
			var sawDemoRule = false;
			var sawNullSafetyRule = false;
			for (rule in metadataRules) {
				if (rule.pathFilter == ""
					&& rule.metadata == "@:build(hxhxmacros.BuildFieldMacros.addGeneratedField())"
					&& rule.recursive
					&& rule.toTypes
					&& !rule.toFields)
					sawBuildRule = true;
				if (rule.pathFilter == "demo.Target" && rule.metadata == "@:demoMeta" && !rule.recursive && rule.toTypes && rule.toFields)
					sawDemoRule = true;
				if (rule.pathFilter == "demo.strict"
					&& rule.metadata == "@:nullSafety(Strict)"
					&& rule.recursive
					&& rule.toTypes
					&& !rule.toFields)
					sawNullSafetyRule = true;
			}
			assertTrue(sawBuildRule, "expected build metadata rule, got: " + metadataRuleSummary);
			assertTrue(sawDemoRule, "expected demo metadata rule, got: " + metadataRuleSummary);
			assertTrue(sawNullSafetyRule, "expected nullSafety metadata rule, got: " + metadataRuleSummary);
			final customMetadata = MacroState.listCustomMetadataEntries();
			assertTrue(customMetadata.length > 0, "expected custom metadata snapshot");
			assertTrue(customMetadata[customMetadata.length - 1].metadata == ":demoCustom", "expected custom metadata name");
			assertTrue(customMetadata[customMetadata.length - 1].doc == "runtime metadata probe", "expected custom metadata doc");
			assertTrue(customMetadata[customMetadata.length - 1].source == "runtime-probe", "expected custom metadata source");

			final typeNotFoundBefore = MacroState.listOnTypeNotFoundHookIds().length;
			final onTypeNotFoundOutput = MacroHostClient.run("hxhxmacros.RuntimeContextApiMacros.probeOnTypeNotFoundRegistration()");
			assertContains("onTypeNotFound output", onTypeNotFoundOutput, "onTypeNotFound=registered");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_ON_TYPE_NOT_FOUND") == "registered", "expected runtime onTypeNotFound define");
			assertTrue(MacroState.listOnTypeNotFoundHookIds().length == typeNotFoundBefore + 1, "expected onTypeNotFound hook count increment");

			MacroHostClient.run("hxhxmacros.RuntimeContextApiMacros.probeRegisterModuleDependency()");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_MODULE_DEP") == "hxhxmacros.RuntimeContextApiMacros->runtime/macro-probe.txt",
				"expected runtime module dependency define");
			final moduleDependencies = MacroState.listModuleDependencies();
			assertTrue(moduleDependencies.length > 0, "expected module dependency snapshot");
			assertTrue(moduleDependencies[moduleDependencies.length - 1].modulePath == "hxhxmacros.RuntimeContextApiMacros",
				"expected module dependency module path");
			assertTrue(moduleDependencies[moduleDependencies.length - 1].externFile == "runtime/macro-probe.txt", "expected module dependency extern file");

			final defineTypeOutput = MacroHostClient.run("hxhxmacros.RuntimeContextApiMacros.probeDefineType()");
			assertContains("defineType output", defineTypeOutput, "defineType=generated.runtime.RuntimeMacroDefined");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_DEFINE_TYPE") == "generated.runtime.RuntimeMacroDefined", "expected runtime defineType define");
			assertTrue(MacroState.listGeneratedHxModuleNames().indexOf("generated.runtime.RuntimeMacroDefined") >= 0, "expected generated module snapshot");
			final generatedSource = MacroState.getGeneratedHxModuleSource("generated.runtime.RuntimeMacroDefined");
			assertTrue(generatedSource != null, "expected generated module source");
			assertContains("generated source package", generatedSource, "package generated.runtime;");
			assertContains("generated source generated meta", generatedSource, "@:generatedMeta");
			assertContains("generated source nullSafety", generatedSource, "@:nullSafety(Strict)");
			assertContains("generated source class", generatedSource, "class RuntimeMacroDefined");
			final defineTypeDeps = MacroState.listModuleDependencies();
			assertTrue(defineTypeDeps[defineTypeDeps.length - 1].modulePath == "generated.runtime.RuntimeMacroDefined",
				"expected defineType dependency module path");
			assertTrue(defineTypeDeps[defineTypeDeps.length - 1].externFile == "runtime/generated-defined.txt", "expected defineType dependency extern file");

			final defineModuleOutput = MacroHostClient.run("hxhxmacros.RuntimeContextApiMacros.probeDefineModule()");
			assertContains("defineModule output", defineModuleOutput, "defineModule=generated.runtime.RuntimeMacroModule");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_DEFINE_MODULE") == "generated.runtime.RuntimeMacroModule", "expected runtime defineModule define");
			assertTrue(MacroState.listGeneratedHxModuleNames().indexOf("generated.runtime.RuntimeMacroModule") >= 0,
				"expected generated module snapshot for defineModule");
			final generatedModuleSource = MacroState.getGeneratedHxModuleSource("generated.runtime.RuntimeMacroModule");
			assertTrue(generatedModuleSource != null, "expected generated defineModule source");
			assertContains("generated module package", generatedModuleSource, "package generated.runtime;");
			assertContains("generated module import", generatedModuleSource, "import haxe.Template as Tpl;");
			assertContains("generated module using", generatedModuleSource, "using StringTools;");
			assertContains("generated module metadata", generatedModuleSource, "@:moduleMeta");
			assertContains("generated module primary type", generatedModuleSource, "class RuntimeMacroModule");
			assertContains("generated module helper metadata", generatedModuleSource, "@:helperMeta");
			assertContains("generated module helper type", generatedModuleSource, "class RuntimeMacroHelper");

			final resourceOutput = MacroHostClient.run("hxhxmacros.RuntimeContextApiMacros.probeResources()");
			assertContains("resource output", resourceOutput, "resource=resource=ok");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_RESOURCE") == "resource=ok", "expected runtime resource define");

			final messagesOutput = MacroHostClient.run("hxhxmacros.RuntimeContextApiMacros.probeMessages()");
			assertContains("messages output warning", messagesOutput, "warning:runtime-warning@");
			assertContains("messages output info", messagesOutput, "info:runtime-info@");
			assertContains("messages define", MacroState.definedValue("HXHX_RUNTIME_MESSAGES"), "info:runtime-info@");

			final parseOutput = MacroHostClient.run("hxhxmacros.RuntimeContextApiMacros.probeParse()");
			assertContains("parse output", parseOutput, "parse=call+inline");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_PARSE") == "call+inline", "expected runtime parse define");

			final makeExprOutput = MacroHostClient.run("hxhxmacros.RuntimeContextApiMacros.probeMakeExprAndSignature()");
			assertContains("makeExpr output", makeExprOutput, "makeExpr=object;signature=");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_MAKE_EXPR") == "object", "expected runtime makeExpr define");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_SIGNATURE").length == 32, "expected runtime signature define");

			final timerOutput = MacroHostClient.run("hxhxmacros.RuntimeContextApiMacros.probeTimer()");
			assertContains("timer output", timerOutput, "timer=ok");
			assertTrue(MacroState.definedValue("HXHX_RUNTIME_TIMER") == "ok", "expected runtime timer define");
		} catch (e:String) {
			failure = e;
		} catch (e:haxe.Exception) {
			failure = e.message;
		}

		Sys.putEnv("HXHX_MACRO_HOST_EXE", originalHostExe);
		MacroState.clearCurrentPos();
		MacroState.clearLocalContext();
		MacroState.clearMainExprText();
		if (sys.FileSystem.exists(generatedHxDir))
			deleteRecursive(generatedHxDir);

		if (failure.length > 0)
			fail(failure);
		Sys.println("OK m14 macro host runtime api");
	}

	static function deleteRecursive(path:String):Void {
		if (!sys.FileSystem.exists(path))
			return;
		if (sys.FileSystem.isDirectory(path)) {
			for (entry in sys.FileSystem.readDirectory(path))
				deleteRecursive(Path.join([path, entry]));
			sys.FileSystem.deleteDirectory(path);
		} else {
			sys.FileSystem.deleteFile(path);
		}
	}
}
