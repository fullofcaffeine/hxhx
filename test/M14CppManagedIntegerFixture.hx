import backend.cpp.CppManagedStoragePlan;
import backend.cpp.CppManagedLocalAccess;
import backend.cpp.CppManagedEnvironmentEmitter;
import backend.cpp.CppManagedFunctionBody;

/** Check integer wraparound, update result selection, and operand effect order independently. */
function append(declarations:Array<String>):Void {
	final cases = [
		{name: "Add", body: "return value + 1;"},
		{name: "Subtract", body: "return value - 1;"},
		{name: "PostIncrement", body: "var local = value; return local++;"},
		{name: "PreIncrement", body: "var local = value; return ++local;"},
		{name: "PostDecrement", body: "var local = value; return local--;"},
		{name: "PreDecrement", body: "var local = value; return --local;"},
		{name: "Effects", body: "return callback() - callback();"}
	];
	for (entry in cases) {
		final effects = entry.name == "Effects";
		final source = "class Main { static function test():Void { var operation = function("
			+ (effects ? "callback:Void->Int" : "value:Int")
			+ "):Int { "
			+ entry.body
			+ " }; } }";
		final parsed = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final typed = TyperStage.typeResolvedModule(parsed, TyperIndex.build([parsed])).getTypedClasses()[0].getFunctions()[0];
		final projection = TypedBodySource.functionProjection(typed);
		final plan = new CppManagedStoragePlan(projection);
		final closure = projection.requireCaptureCatalog().getExpressions()[0];
		final environment = "hxhx_env_Integer" + entry.name;
		declarations.push(new CppManagedEnvironmentEmitter(plan, closure, environment).render());
		final access = new CppManagedLocalAccess({
			projection: projection,
			plan: plan,
			owner: Closure(closure),
			parameters: [effects ? "callback" : "value"],
			temporaryPrefix: "hxhx_parameters_integer_",
			environmentName: environment,
			environmentSymbol: "environment"
		});
		declarations.push("inline void generatedInteger"
			+ entry.name
			+ "(hxhx::managed::Heap& heap, hxhx::managed::ErasedRef environment, hxhx::managed::Root<hxhx::managed::Value>& output, "
			+ (effects ? "hxhx::managed::Value callback" : "hxhx::managed::Value value")
			+ ") {\n(void)environment;\n"
			+ access.parameters.render("heap")
			+ "\n"
			+ new CppManagedFunctionBody(plan, Closure(closure)).render("output", null, M14CppManagedClosureAbiIntegrationTest.returnServices(access, []))
			+ "\n}");
	}
}
