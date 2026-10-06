import backend.cpp.CppManagedStoragePlan;
import backend.cpp.CppManagedRuntime;
import backend.cpp.CppManagedEnvironmentEmitter;
import backend.cpp.CppManagedCallEmitter;
import backend.cpp.CppManagedEnvironmentEmitter.CppManagedEnvironmentCapture;
import backend.cpp.CppManagedCellEmitter;
import backend.cpp.CppManagedParameterEmitter;
import backend.cpp.CppManagedFunctionBody;
import backend.cpp.CppManagedLocalAccess;
import backend.cpp.CppManagedRootedExpression;
import backend.cpp.CppManagedRootedExpression.CppManagedClosureLink;
import backend.cpp.CppControlRegion.CppControlRegionServices;

/** Compile typed closure ABI output against the real native memory and callable headers. */
class M14CppManagedClosureAbiIntegrationTest {
	/** Flush CPU and wall time before expensive phases so interrupted runs retain useful evidence. */
	static function phase(name:String):Void {
		Sys.println("CPP_MANAGED_CLOSURE_PHASE:" + name + ":cpu=" + Sys.cpuTime() + ":wall=" + Sys.time());
		Sys.stdout().flush();
	}

	/** Production code owns declaration and value emission; unused loop hooks remain fixture-specific. */
	public static function returnServices(access:CppManagedLocalAccess, links:Array<CppManagedClosureLink>):CppControlRegionServices {
		return backend.cpp.CppManagedBodyServices.create({
			owner: CallableBody(access),
			heap: "heap",
			temporaryPrefix: "hxhx_value_fixture_",
			resolve: expression -> {
				for (link in links)
					if (link.expression == expression)
						return link;
				throw "fixture lacks the exact child entry link";
			}
		});
	}

	static function main():Void {
		phase("start");
		// Dynamic is intentional input-language coverage for erased value transport.
		// The compiler test itself retains typed projections and native signatures.
		final source = "class Main { var base:Int = 23; function test():Void { var seed = 17; var scalar = function(value:Int):Int { return seed + value; }; var managed = function(value:Dynamic, other:Dynamic, choose:Bool):Dynamic { if (choose) { return value; } return other; }; var empty = function():Void {}; var receiver = function():Int { return this.base; }; function named():Int { return named(); } var erased:Dynamic = null; var erasedClosure = function():Dynamic { return erased; }; var promoter = function(value:Dynamic, spare:Dynamic):Void->Dynamic { return function():Dynamic { return value; }; }; } }";
		final parsed = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		phase("type-main");
		final typed = TyperStage.typeResolvedModule(parsed, TyperIndex.build([parsed])).getTypedClasses()[0].getFunctions()[0];
		final revision = CompilerTypedTreeRevision.functionBody(typed);
		phase("project-main");
		final projection = TypedBodySource.functionProjection(typed);
		phase("storage-main");
		final plan = new CppManagedStoragePlan(projection);
		final closures = projection.requireCaptureCatalog().getExpressions();
		final names = [
			"Scalar",
			"Managed",
			"Empty",
			"Receiver",
			"Named",
			"Erased",
			"Promoter",
			"Forward"
		];
		if (closures.length != names.length)
			throw "native ABI fixture lost a typed closure";
		final declarations = ["#pragma once", "#include \"ManagedCallable.hpp\""];
		final cells = plan.getCells();
		if (cells.length != 4)
			throw "native cell fixture lost a promoted declaration";
		phase("cells");
		for (index in 0...cells.length) {
			final emitter = new CppManagedCellEmitter(plan, cells[index].source.binding);
			declarations.push("inline void allocateCell"
				+ index
				+ "(hxhx::managed::Heap& heap, hxhx::managed::Root<hxhx::managed::Ref<hxhx::managed::CellPayload>>& output) { "
				+ emitter.renderAllocation("heap", "output", cells[index].source)
				+ " }");
			declarations.push("inline void readCell"
				+ index
				+ "(hxhx::managed::Ref<hxhx::managed::CellPayload> cell, hxhx::managed::Root<hxhx::managed::Value>& output) { "
				+ emitter.renderRead("cell", "output")
				+ " }");
			declarations.push("template<class Select, class Evaluate> void writeCell"
				+ index
				+ "(hxhx::managed::Heap& heap, Select select, Evaluate evaluate, hxhx::managed::Root<hxhx::managed::Value>& output) "
				+ emitter.renderWrite({
					heap: "heap",
					cell: "select()",
					value: "evaluate()",
					destination: "output",
					temporaryPrefix: "hxhx_cell_fixture_"
				}));
		}
		phase("closures");
		for (index in 0...closures.length) {
			final environmentName = "hxhx_env_" + names[index];
			final environment = new CppManagedEnvironmentEmitter(plan, closures[index], environmentName);
			declarations.push(environment.render());
			declarations.push("using " + names[index] + "Environment = " + environmentName + ";");
			declarations.push("using "
				+ names[index]
				+ " = hxhx::managed::CallablePayload<"
				+ plan.requireClosure(closures[index]).abi.nativeSignature()
				+ ">;");
			final abi = plan.requireClosure(closures[index]).abi;
			final constructorInputs = [
				"hxhx::managed::Heap& heap",
				"hxhx::managed::Root<hxhx::managed::Ref<" + names[index] + ">>& output",
				names[index] + "::Entry entry"
			];
			final captures = new Array<CppManagedEnvironmentCapture>();
			final selected = plan.requireClosure(closures[index]);
			for (cellIndex in 0...selected.getCells().length) {
				final name = "cell" + cellIndex;
				constructorInputs.push("hxhx::managed::Ref<hxhx::managed::CellPayload> " + name);
				captures.push({binding: selected.getCells()[cellIndex].source.binding, reference: name});
			}
			if (selected.facts.capturesReceiver)
				constructorInputs.push("hxhx::managed::Ref<hxhx::managed::CellPayload> receiver");
			declarations.push("inline void construct" + names[index] + "(" + constructorInputs.join(", ") + ") " + environment.renderConstruction({
				heap: "heap",
				destination: "output",
				entry: "entry",
				captures: captures,
				receiver: selected.facts.capturesReceiver ? "receiver" : null,
				temporaryPrefix: "hxhx_construct_fixture_"
			}));
			final templates = ["class Select"];
			final inputs = ["hxhx::managed::Heap& heap", "Select select"];
			final arguments = new Array<String>();
			for (parameter in abi.getParameters()) {
				templates.push("class A" + parameter.slot);
				inputs.push("A" + parameter.slot + " arg" + parameter.slot);
				arguments.push("arg" + parameter.slot + "()");
			}
			if (abi.result != NoResult) {
				templates.push("class Result");
				inputs.push("Result& output");
			}
			declarations.push("template<" + templates.join(", ") + "> void generated" + names[index] + "(" + inputs.join(", ") + ") "
				+ new CppManagedCallEmitter(plan, closures[index]).render({
					heap: "heap",
					calleeSetup: [],
					callee: "select()",
					arguments: [for (value in arguments) {setup: [], value: value}],
					destination: abi.result == NoResult ? null : "output",
					temporaryPrefix: "hxhx_call_fixture_"
				}));
		}
		phase("body-entries");
		final returnedAccess = new CppManagedLocalAccess({
			projection: projection,
			plan: plan,
			owner: Closure(closures[1]),
			parameters: ["first", "spare", "choose"],
			temporaryPrefix: "hxhx_parameters_return_",
			environmentName: "hxhx_env_Managed",
			environmentSymbol: "environment"
		});
		declarations.push("inline void generatedManagedBody(hxhx::managed::Heap& heap, hxhx::managed::ErasedRef environment, hxhx::managed::Root<hxhx::managed::Value>& output, hxhx::managed::Value first, hxhx::managed::Value spare, hxhx::managed::Value choose) {\n(void)environment;\n"
			+ returnedAccess.parameters.render("heap")
			+ "\nheap.collect();\n"
			+ new CppManagedFunctionBody(plan, Closure(closures[1])).render("output", null, returnServices(returnedAccess, []))
			+ "\n}");
		final forwardedAccess = new CppManagedLocalAccess({
			projection: projection,
			plan: plan,
			owner: Closure(closures[7]),
			parameters: [],
			temporaryPrefix: "hxhx_parameters_forward_",
			environmentName: "hxhx_env_Forward",
			environmentSymbol: "environment"
		});
		declarations.push("inline void generatedForwardBody(hxhx::managed::Heap& heap, hxhx::managed::ErasedRef environment, hxhx::managed::Root<hxhx::managed::Value>& output) {\nheap.collect();\n"
			+ new CppManagedFunctionBody(plan, Closure(closures[7])).render("output", null, returnServices(forwardedAccess, []))
			+ "\n}");
		final promoterAccess = new CppManagedLocalAccess({
			projection: projection,
			plan: plan,
			owner: Closure(closures[6]),
			parameters: ["first", "spare"],
			temporaryPrefix: "hxhx_parameters_fixture_",
			environmentName: "hxhx_env_Promoter",
			environmentSymbol: "environment"
		});
		declarations.push("static void observeParameterRoots(hxhx::managed::Heap&, hxhx::managed::Value);");
		declarations.push("inline void generatedPromoterEntry(hxhx::managed::Heap& heap, hxhx::managed::ErasedRef environment, hxhx::managed::Root<hxhx::managed::Value>& output, hxhx::managed::Value first, hxhx::managed::Value spare) {\n(void)environment;\n"
			+ promoterAccess.parameters.render("heap")
			+ "\nobserveParameterRoots(heap, "
			+ promoterAccess.parameters.value(plan.requireClosure(closures[6]).getParameters()[1].binding)
			+ ");\n"
			+ new CppManagedFunctionBody(plan, Closure(closures[6])).render("output", null, returnServices(promoterAccess, [
				{
					expression: closures[7],
					environmentName: "hxhx_env_Forward",
					entrySymbol: "generatedForwardBody"
				}
			]))
			+ "\n}");
		phase("local-creator");
		addLocalCreator(declarations);
		phase("mutable-capture");
		addMutableCapture(declarations);
		phase("source-calls");
		M14CppManagedSourceCallFixture.append(declarations);
		phase("iteration");
		M14CppManagedIterationFixture.append(declarations);
		phase("original-program");
		M14CppManagedOriginalProgramFixture.append(declarations);
		phase("record-read");
		M14CppManagedRecordReadFixture.append(declarations);
		phase("validate");
		plan.assertCurrent();
		if (revision != CompilerTypedTreeRevision.functionBody(typed))
			throw "native ABI planning mutated the authored typed function";
		phase("publish");
		final output = ".tmp/managed-closure-abi";
		sys.FileSystem.createDirectory(output);
		final runtime = new CppManagedRuntime();
		final runtimeDirectory = output + "/runtime";
		final artifacts = runtime.publish(runtimeDirectory);
		final requiredHeaders = [
			"ManagedHeap.hpp",
			"ManagedValue.hpp",
			"ManagedEquality.hpp",
			"ManagedMap.hpp",
			"ManagedThrow.hpp",
			"ManagedStack.hpp",
			"ManagedCallable.hpp",
			"ManagedOutput.hpp",
			"ManagedString.hpp"
		];
		if (artifacts.length != requiredHeaders.length || runtime.getFiles().map(file -> file.name).join(",") != requiredHeaders.join(","))
			throw "managed runtime packaging lost a native header";
		for (file in runtime.getFiles()) {
			final expected = sys.io.File.getContent("packages/hxhx-core/runtime/cpp/" + file.name);
			if (file.content != expected
				|| file.sha256 != haxe.crypto.Sha256.encode(expected)
				|| sys.io.File.getContent(runtimeDirectory + "/" + file.name) != expected)
				throw "managed runtime packaging changed native source identity";
		}
		runtime.getFiles().pop();
		if (runtime.getFiles().map(file -> file.name).join(",") != requiredHeaders.join(","))
			throw "managed runtime exposed a mutable file inventory";
		sys.io.File.saveContent(output + "/ClosureAbi.generated.hpp", declarations.join("\n") + "\n");
		sys.io.File.copy("test/cpp_managed_heap/GeneratedAbiTest.cpp", output + "/GeneratedAbiTest.cpp");
		sys.io.File.copy("test/cpp_managed_heap/IterationObserver.hpp", output + "/IterationObserver.hpp");
		sys.io.File.copy("test/cpp_managed_heap/RecordReadObserver.hpp", output + "/RecordReadObserver.hpp");
		final selectedCompiler = Sys.getEnv("CXX");
		final compiler = selectedCompiler == null || selectedCompiler.length == 0 ? "clang++" : selectedCompiler;
		final timeout = Sys.systemName() == "Mac" ? "gtimeout" : "timeout";
		final executable = output + "/test";
		phase("native-compile");
		final code = Sys.command(timeout, ["60", compiler].concat([
			"-std=c++17",
			"-Wall",
			"-Wextra",
			"-Werror",
			"-O0",
			"-g",
			"-fno-omit-frame-pointer",
			"-fsanitize=address,undefined",
			"-I",
			runtimeDirectory,
			"-I",
			output,
			output + "/GeneratedAbiTest.cpp",
			"-o",
			executable
		]));
		if (code != 0)
			throw "generated callable ABI does not compile against the native runtime";
		phase("native-observer");
		final process = new sys.io.Process(timeout, ["60", executable]);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final result = process.exitCode();
		process.close();
		if (result != 0 || stdout != "CPP_MANAGED_ABI:PASS\n")
			throw "generated callable ABI changed invocation or result transport: " + stdout + stderr;
		Sys.println("CPP_MANAGED_CLOSURE_ABI_INTEGRATION:PASS");
		phase("original-observer");
		M14CppManagedOriginalProgramFixture.observe(executable, timeout);
		phase("output-observer");
		M14CppManagedOutputFixture.verify(output + "/output", compiler, timeout);
		phase("complete");
	}

	/** Writes through an escaped child share one cell, including a collecting replacement initializer. */
	static function addMutableCapture(declarations:Array<String>):Void {
		final source = "class Main { static function test():Void { var maker = function(seed:Dynamic):Dynamic->Bool->Dynamic { var state = seed; return function(next:Dynamic, wrap:Bool):Dynamic { if(wrap) { state = function():Dynamic { return state; }; } else { var copy = next; state = copy = next; next = state; } return state; }; }; } }";
		final parsed = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final typed = TyperStage.typeResolvedModule(parsed, TyperIndex.build([parsed])).getTypedClasses()[0].getFunctions()[0];
		final revision = CompilerTypedTreeRevision.functionBody(typed);
		final projection = TypedBodySource.functionProjection(typed);
		final plan = new CppManagedStoragePlan(projection);
		final closures = projection.requireCaptureCatalog().getExpressions();
		if (closures.length != 3 || plan.getCells().length != 1)
			throw "mutation fixture lost the one shared captured location";
		for (index in 0...3)
			declarations.push(new CppManagedEnvironmentEmitter(plan, closures[index], "hxhx_env_Mutation" + index).render());
		final inputs = [["seed"], ["next", "wrap"], []];
		final signatures = [
			", hxhx::managed::Value seed",
			", hxhx::managed::Value next, hxhx::managed::Value wrap",
			""
		];
		var index = 2;
		while (index >= 0) {
			final access = new CppManagedLocalAccess({
				projection: projection,
				plan: plan,
				owner: Closure(closures[index]),
				parameters: inputs[index],
				temporaryPrefix: "hxhx_parameters_mutation" + index + "_",
				environmentName: "hxhx_env_Mutation" + index,
				environmentSymbol: "environment"
			});
			final links:Array<CppManagedClosureLink> = index == 2 ? [] : [
				{expression: closures[index + 1], environmentName: "hxhx_env_Mutation" + (index + 1), entrySymbol: "generatedMutation" + (index + 1)}
			];
			declarations.push("inline void generatedMutation"
				+ index
				+ "(hxhx::managed::Heap& heap, hxhx::managed::ErasedRef environment, hxhx::managed::Root<hxhx::managed::Value>& output"
				+ signatures[index]
				+ ") {\n(void)environment;\n"
				+ access.parameters.render("heap")
				+ "\nheap.collect();\n"
				+ new CppManagedFunctionBody(plan, Closure(closures[index])).render("output", null, returnServices(access, links))
				+ "\n}");
			index--;
		}
		if (revision != CompilerTypedTreeRevision.functionBody(typed))
			throw "mutable capture emission changed authored typed source";
	}

	/** A source local, rather than a parameter, owns the escaped child's shared storage. */
	static function addLocalCreator(declarations:Array<String>):Void {
		final source = "class Main { static function test():Void { var creator = function(value:Dynamic):Void->Dynamic { var copy = value; var kept = copy; return function():Dynamic { return kept; }; }; var recursive = function():Void->Dynamic { function self():Dynamic { return self; } return self; }; } }";
		final parsed = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final typed = TyperStage.typeResolvedModule(parsed, TyperIndex.build([parsed])).getTypedClasses()[0].getFunctions()[0];
		final revision = CompilerTypedTreeRevision.functionBody(typed);
		final projection = TypedBodySource.functionProjection(typed);
		final plan = new CppManagedStoragePlan(projection);
		final closures = projection.requireCaptureCatalog().getExpressions();
		if (closures.length != 4
			|| plan.getCells().length != 2
			|| plan.getCells()[0].source.creation != Declaration
			|| plan.getCells()[1].mode != InitializeOnce)
			throw "local creator fixture lost its declaration allocation event";
		for (index in 0...4)
			declarations.push(new CppManagedEnvironmentEmitter(plan, closures[index], "hxhx_env_Local" + index).render());
		final child = new CppManagedLocalAccess({
			projection: projection,
			plan: plan,
			owner: Closure(closures[1]),
			parameters: [],
			temporaryPrefix: "hxhx_parameters_local_child_",
			environmentName: "hxhx_env_Local1",
			environmentSymbol: "environment"
		});
		declarations.push("inline void generatedLocalChild(hxhx::managed::Heap& heap, hxhx::managed::ErasedRef environment, hxhx::managed::Root<hxhx::managed::Value>& output) {\nheap.collect();\n"
			+ new CppManagedFunctionBody(plan, Closure(closures[1])).render("output", null, returnServices(child, []))
			+ "\n}");
		final creator = new CppManagedLocalAccess({
			projection: projection,
			plan: plan,
			owner: Closure(closures[0]),
			parameters: ["value"],
			temporaryPrefix: "hxhx_parameters_local_creator_",
			environmentName: "hxhx_env_Local0",
			environmentSymbol: "environment"
		});
		declarations.push("inline void generatedLocalCreator(hxhx::managed::Heap& heap, hxhx::managed::ErasedRef environment, hxhx::managed::Root<hxhx::managed::Value>& output, hxhx::managed::Value value) {\n(void)environment;\n"
			+ creator.parameters.render("heap")
			+ "\n"
			+ new CppManagedFunctionBody(plan, Closure(closures[0])).render("output", null, returnServices(creator, [
				{
					expression: closures[1],
					environmentName: "hxhx_env_Local1",
					entrySymbol: "generatedLocalChild"
				}
			]))
			+ "\n}");
		final selfAccess = new CppManagedLocalAccess({
			projection: projection,
			plan: plan,
			owner: Closure(closures[3]),
			parameters: [],
			temporaryPrefix: "hxhx_parameters_self_",
			environmentName: "hxhx_env_Local3",
			environmentSymbol: "environment"
		});
		declarations.push("inline void generatedSelf(hxhx::managed::Heap& heap, hxhx::managed::ErasedRef environment, hxhx::managed::Root<hxhx::managed::Value>& output) {\nheap.collect();\n"
			+ new CppManagedFunctionBody(plan, Closure(closures[3])).render("output", null, returnServices(selfAccess, []))
			+ "\n}");
		final recursive = new CppManagedLocalAccess({
			projection: projection,
			plan: plan,
			owner: Closure(closures[2]),
			parameters: [],
			temporaryPrefix: "hxhx_parameters_recursive_",
			environmentName: "hxhx_env_Local2",
			environmentSymbol: "environment"
		});
		declarations.push("inline void generatedRecursiveCreator(hxhx::managed::Heap& heap, hxhx::managed::ErasedRef environment, hxhx::managed::Root<hxhx::managed::Value>& output) {\n(void)environment;\n"
			+ new CppManagedFunctionBody(plan, Closure(closures[2])).render("output", null, returnServices(recursive, [
				{
					expression: closures[3],
					environmentName: "hxhx_env_Local3",
					entrySymbol: "generatedSelf"
				}
			]))
			+ "\n}");
		if (revision != CompilerTypedTreeRevision.functionBody(typed))
			throw "local storage emission mutated the authored typed function";
	}
}
