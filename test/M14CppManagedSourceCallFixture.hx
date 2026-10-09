import backend.cpp.CppManagedStoragePlan;
import backend.cpp.CppManagedLocalAccess;
import backend.cpp.CppManagedEnvironmentEmitter;
import backend.cpp.CppManagedFunctionBody;

/** Authored argument effects replace the selected function and allocate an escaping argument. */
function append(declarations:Array<String>):Void {
	final source = "class Main { static function test():Void { var caller = function(selected:Dynamic->Dynamic->Dynamic, replacement:Dynamic->Dynamic->Dynamic, value:Dynamic):Dynamic { return selected(selected = replacement, function():Dynamic { return value; }); }; } }";
	final parsed = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
	final typed = TyperStage.typeResolvedModule(parsed, TyperIndex.build([parsed])).getTypedClasses()[0].getFunctions()[0];
	final revision = CompilerTypedTreeRevision.functionBody(typed);
	final projection = TypedBodySource.functionProjection(typed);
	final plan = new CppManagedStoragePlan(projection);
	final closures = projection.requireCaptureCatalog().getExpressions();
	if (closures.length != 2)
		throw "source call fixture lost its authored argument closure";
	for (index in 0...2)
		declarations.push(new CppManagedEnvironmentEmitter(plan, closures[index], "hxhx_env_SourceCall" + index).render());
	final child = new CppManagedLocalAccess({
		projection: projection,
		plan: plan,
		owner: Closure(closures[1]),
		parameters: [],
		temporaryPrefix: "hxhx_parameters_source_call_child_",
		environmentName: "hxhx_env_SourceCall1",
		environmentSymbol: "environment"
	});
	declarations.push("inline void generatedSourceCallChild(hxhx::managed::Heap& heap, hxhx::managed::ErasedRef environment, hxhx::managed::Root<hxhx::managed::Value>& output) {\nheap.collect();\n"
		+ new CppManagedFunctionBody(plan, Closure(closures[1])).render("output", null, M14CppManagedClosureAbiIntegrationTest.returnServices(child, []))
		+ "\n}");
	final caller = new CppManagedLocalAccess({
		projection: projection,
		plan: plan,
		owner: Closure(closures[0]),
		parameters: ["selected", "replacement", "value"],
		temporaryPrefix: "hxhx_parameters_source_call_",
		environmentName: "hxhx_env_SourceCall0",
		environmentSymbol: "environment"
	});
	declarations.push("inline void generatedSourceCall(hxhx::managed::Heap& heap, hxhx::managed::ErasedRef environment, hxhx::managed::Root<hxhx::managed::Value>& output, hxhx::managed::Value selected, hxhx::managed::Value replacement, hxhx::managed::Value value) {\n(void)environment;\n"
		+ caller.parameters.render("heap")
		+ "\n"
		+ new CppManagedFunctionBody(plan, Closure(closures[0])).render("output", null, M14CppManagedClosureAbiIntegrationTest.returnServices(caller, [
			{
				expression: closures[1],
				environmentName: "hxhx_env_SourceCall1",
				entrySymbol: "generatedSourceCallChild"
			}
		]))
		+ "\n}");
	if (revision != CompilerTypedTreeRevision.functionBody(typed))
		throw "source call emission mutated authored typing";
	appendLeafAndVoid(declarations);
	appendDirectReturn(declarations);
	appendStringReturn(declarations);
	M14CppManagedCounterFixture.append(declarations);
	M14CppManagedIntegerFixture.append(declarations);
	M14CppManagedRootFixture.append(declarations);
	M14CppManagedStaticCallFixture.append(declarations);
	M14CppManagedConditionFixture.append(declarations);
	M14CppManagedAggregateFixture.append(declarations);
	M14CppManagedControlValueFixture.append(declarations);
}

/** Plain String remains null-capable even without an explicit Null wrapper. */
private function appendStringReturn(declarations:Array<String>):Void {
	final source = "class Main { static function test():Void { var direct = function(callback:String->String, value:String):String { return callback(value); }; } }";
	final parsed = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
	final typed = TyperStage.typeResolvedModule(parsed, TyperIndex.build([parsed])).getTypedClasses()[0].getFunctions()[0];
	final projection = TypedBodySource.functionProjection(typed);
	final plan = new CppManagedStoragePlan(projection);
	final closure = projection.requireCaptureCatalog().getExpressions()[0];
	declarations.push(new CppManagedEnvironmentEmitter(plan, closure, "hxhx_env_StringReturn").render());
	final access = new CppManagedLocalAccess({
		projection: projection,
		plan: plan,
		owner: Closure(closure),
		parameters: ["callback", "value"],
		temporaryPrefix: "hxhx_parameters_string_return_",
		environmentName: "hxhx_env_StringReturn",
		environmentSymbol: "environment"
	});
	declarations.push("inline void generatedStringReturn(hxhx::managed::Heap& heap, hxhx::managed::ErasedRef environment, hxhx::managed::Root<hxhx::managed::Value>& output, hxhx::managed::Value callback, hxhx::managed::Value value) {\n(void)environment;\n"
		+ access.parameters.render("heap")
		+ "\n"
		+ new CppManagedFunctionBody(plan, Closure(closure)).render("output", null, M14CppManagedClosureAbiIntegrationTest.returnServices(access, []))
		+ "\n}");
}

/** A scalar callback result must preserve the collecting call's statement sequence and rooted output. */
private function appendDirectReturn(declarations:Array<String>):Void {
	final source = "class Main { static function test():Void { var direct = function(callback:Int->Int, value:Int):Int { return callback(value); }; } }";
	final parsed = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
	final typed = TyperStage.typeResolvedModule(parsed, TyperIndex.build([parsed])).getTypedClasses()[0].getFunctions()[0];
	final projection = TypedBodySource.functionProjection(typed);
	final plan = new CppManagedStoragePlan(projection);
	final closure = projection.requireCaptureCatalog().getExpressions()[0];
	declarations.push(new CppManagedEnvironmentEmitter(plan, closure, "hxhx_env_DirectReturn").render());
	final access = new CppManagedLocalAccess({
		projection: projection,
		plan: plan,
		owner: Closure(closure),
		parameters: ["callback", "value"],
		temporaryPrefix: "hxhx_parameters_direct_return_",
		environmentName: "hxhx_env_DirectReturn",
		environmentSymbol: "environment"
	});
	declarations.push("inline void generatedDirectReturn(hxhx::managed::Heap& heap, hxhx::managed::ErasedRef environment, hxhx::managed::Root<hxhx::managed::Value>& output, hxhx::managed::Value callback, hxhx::managed::Value value) {\n(void)environment;\n"
		+ access.parameters.render("heap")
		+ "\n"
		+ new CppManagedFunctionBody(plan, Closure(closure)).render("output", null, M14CppManagedClosureAbiIntegrationTest.returnServices(access, []))
		+ "\n}");
}

/** Boolean results and discarded Void calls must use the same source-call owner. */
private function appendLeafAndVoid(declarations:Array<String>):Void {
	final source = "class Main { static function test():Void { var leaf = function(callback:Bool->Bool, flag:Bool):Dynamic { return callback(flag); }; var ignored = function(callback:Void->Void):Void { callback(); }; var nested = function(selected:Dynamic->Dynamic, effect:Void->Dynamic):Dynamic { return selected(effect()); }; } }";
	final parsed = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
	final typed = TyperStage.typeResolvedModule(parsed, TyperIndex.build([parsed])).getTypedClasses()[0].getFunctions()[0];
	final projection = TypedBodySource.functionProjection(typed);
	final plan = new CppManagedStoragePlan(projection);
	final closures = projection.requireCaptureCatalog().getExpressions();
	final inputs = [["callback", "flag"], ["callback"], ["selected", "effect"]];
	final signatures = [
		", hxhx::managed::Root<hxhx::managed::Value>& output, hxhx::managed::Value callback, hxhx::managed::Value flag",
		", hxhx::managed::Value callback",
		", hxhx::managed::Root<hxhx::managed::Value>& output, hxhx::managed::Value selected, hxhx::managed::Value effect"
	];
	for (index in 0...3) {
		final environment = "hxhx_env_SourceLeaf" + index;
		declarations.push(new CppManagedEnvironmentEmitter(plan, closures[index], environment).render());
		final access = new CppManagedLocalAccess({
			projection: projection,
			plan: plan,
			owner: Closure(closures[index]),
			parameters: inputs[index],
			temporaryPrefix: "hxhx_parameters_leaf_call" + index + "_",
			environmentName: environment,
			environmentSymbol: "environment"
		});
		declarations.push("inline void generatedSourceLeaf"
			+ index
			+ "(hxhx::managed::Heap& heap, hxhx::managed::ErasedRef environment"
			+ signatures[index]
			+ ") {\n(void)environment;\n"
			+ access.parameters.render("heap")
			+ "\n"
			+ new CppManagedFunctionBody(plan,
				Closure(closures[index])).render(index == 1 ? null : "output", null, M14CppManagedClosureAbiIntegrationTest.returnServices(access, []))
			+ "\n}");
	}
}
