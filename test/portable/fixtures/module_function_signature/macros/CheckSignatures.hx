import haxe.macro.Context;
import reflaxe.ocaml.OcamlCompiler;
import reflaxe.ocaml.ast.OcamlASTPrinter;
import reflaxe.ocaml.ast.OcamlModuleReferences;
import reflaxe.ocaml.ast.OcamlModuleGroups.plan as planModules;
import reflaxe.ocaml.ast.OcamlFunctionModuleCheck.checkFunctionModule;

/** Checks metadata from actual function lowering, before relying on module signatures. */
@:access(reflaxe.ocaml.OcamlCompiler)
class CheckSignatures {
	public static function install():Void {
		Context.onAfterGenerate(() -> {
			check("CycleLeft", "value", "int -> int");
			check("CycleRight", "value", "int -> int");
			check("Main", "main", "unit -> unit");
			check("CycleLeft", "create", "unit -> t");
			check("CycleLeft", "__empty", "unit -> t");
			check("ConstructorProbe", "create", "int -> t");
			check("ConstructorProbe", "__empty", "unit -> t");
			final unrepresented = OcamlCompiler.instance.moduleChunks.itemsFor("UnrepresentedConstructorProbe", "UnrepresentedConstructorProbe");
			if (unrepresented == null)
				throw "missing unrepresented constructor syntax";
			switch (checkFunctionModule(unrepresented)) {
				case FunctionModuleRejected(MissingSignature("create")):
				case _: throw "unrepresented constructor acquired an inferred signature";
			}
			for (name in ["Main", "CycleLeft", "CycleRight", "ConstructorProbe"]) {
				final items = OcamlCompiler.instance.moduleChunks.itemsFor(name, name);
				if (items == null)
					throw "missing module syntax: " + name;
				switch (checkFunctionModule(items)) {
					case FunctionModuleReady(_):
					case FunctionModuleRejected(problem): throw "incomplete function module " + name + ": " + Std.string(problem);
				}
			}
			final nodes = [
				for (name in ["Main", "CycleLeft", "CycleRight"]) {
					final items = OcamlCompiler.instance.moduleChunks.itemsFor(name, name);
					if (items == null) throw "missing module syntax: " + name;
					final references = OcamlModuleReferences.collect(items);
					{
						name: name,
						dependencies: references.functionModules.concat(references.initializationModules).concat(references.typeModules)
					};
				}
			];
			final groups = planModules(nodes).groups;
			if (groups.map(group -> group.members.join(",")).join(";") != "CycleRight;CycleLeft;Main")
				throw "retained declarations lost module dependency order";
		});
	}

	/** Test-only access checks the target's retained declarations, not generated text. */
	static function check(moduleId:String, name:String, expected:String):Void {
		final items = OcamlCompiler.instance.moduleChunks.itemsFor(moduleId, moduleId);
		if (items == null)
			throw "missing module syntax: " + moduleId;
		final references = OcamlModuleReferences.collect(items);
		if (moduleId == "CycleLeft" && references.functionModules.indexOf("CycleRight") < 0)
			throw "lowered static call lost its module dependency";
		if (moduleId == "CycleLeft" && references.initializationModules.indexOf("CycleRight") >= 0)
			throw "delayed static call became an initializer dependency";
		for (item in items)
			switch (item) {
				case ILet(bindings, _):
					for (binding in bindings)
						if (binding.name == name) {
							if (binding.signature == null)
								throw "missing callable signature: " + moduleId + "." + name;
							final actual = new OcamlASTPrinter().printType(binding.signature);
							if (actual != expected)
								throw "wrong callable signature: " + actual + " expected " + expected;
							return;
						}
				case IType(_, _):
			}
		throw "missing callable binding: " + moduleId + "." + name;
	}
}
