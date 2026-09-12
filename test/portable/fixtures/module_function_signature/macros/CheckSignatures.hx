import haxe.macro.Context;
import reflaxe.ocaml.OcamlCompiler;
import reflaxe.ocaml.ast.OcamlASTPrinter;
import reflaxe.ocaml.ast.OcamlModuleReferences;
import reflaxe.ocaml.ast.OcamlModuleGroups.plan as planModules;

/** Checks metadata from actual function lowering, before relying on module signatures. */
@:access(reflaxe.ocaml.OcamlCompiler)
class CheckSignatures {
	public static function install():Void {
		Context.onAfterGenerate(() -> {
			check("CycleLeft", "value", "int -> int");
			check("CycleRight", "value", "int -> int");
			check("Main", "main", "unit -> unit");
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
