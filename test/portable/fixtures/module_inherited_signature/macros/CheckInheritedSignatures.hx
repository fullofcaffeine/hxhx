import haxe.macro.Context;
import reflaxe.ocaml.OcamlCompiler;
import reflaxe.ocaml.CompilationContext;
import reflaxe.ocaml.ast.OcamlASTPrinter;
import reflaxe.ocaml.ast.OcamlRecursiveModuleCheck.checkRecursiveModule;
import reflaxe.ocaml.ast.OcamlDeclarationSignature.projectDeclarationSignature;
import reflaxe.ocaml.lowered.OcamlRepresentationRegistry;

/** Verifies that named dispatch records do not gain direct-field optimization authority. */
@:access(reflaxe.ocaml.OcamlCompiler)
class CheckInheritedSignatures {
	public static function install():Void {
		Context.onAfterTyping(_ -> {
			for (name in ["Root", "Base", "Child"]) {
				final signature = projectDeclarationSignature([Context.getType(name)], Context.getType("String"), new OcamlRepresentationRegistry(),
					_ -> throw "class mapped before inheritance scan", new CompilationContext());
				if (signature != null)
					throw "inherited declaration did not require complete inheritance facts";
			}
		});
		Context.onAfterGenerate(() -> {
			final compiler = OcamlCompiler.instance;
			for (name in ["Root", "Base", "Child"])
				if (compiler.representationRegistry.monomorphicClassForType(Context.getType(name)) != null)
					throw "inherited record incorrectly gained direct-field optimization authority";
			for (name in ["Root", "Base", "Child"]) {
				final items = compiler.moduleChunks.itemsFor(name, name);
				if (items == null)
					throw "missing inherited class: " + name;
				switch (checkRecursiveModule(items)) {
					case RecursiveModuleReady(_, _):
					case RecursiveModuleRejected(problem): throw "incomplete inherited class: " + name + ": " + Std.string(problem);
				}
				final expected:Map<String,
					String> = name == "Root" ? ["__ctor" => "t -> unit -> unit", "marker__impl" => "t -> unit -> string"] : ["__ctor" => "t -> int -> unit", "describe__impl" => "t -> unit -> string"];
				for (item in items)
					switch (item) {
						case ILet(bindings, _):
							for (binding in bindings)
								if (expected.exists(binding.name)) {
									if (binding.signature == null
										|| new OcamlASTPrinter().printType(binding.signature) != expected.get(binding.name))
										throw "wrong inherited member signature: " + name + "." + binding.name;
									expected.remove(binding.name);
								}
						case IType(_, _):
					}
				if (expected.keys().hasNext())
					throw "missing inherited member: " + name;
			}
			for (moduleId in ["First", "Second"]) {
				final items = compiler.moduleChunks.itemsFor(moduleId, moduleId);
				if (items == null)
					throw "missing inherited-value module: " + moduleId;
				final expected:Map<String, String> = [
					"observe" => "Base.t -> string",
					"retain" => "Base.t -> Base.t",
					"child" => "Child.t -> Child.t"
				];
				if (moduleId == "First")
					expected.set("maybe", "Base.t -> string");
				for (item in items)
					switch (item) {
						case ILet(bindings, _):
							for (binding in bindings)
								if (expected.exists(binding.name)) {
									if (binding.signature == null
										|| new OcamlASTPrinter().printType(binding.signature) != expected.get(binding.name))
										throw "inherited declaration lost its existing record type: " + moduleId + "." + binding.name;
									expected.remove(binding.name);
								}
						case IType(_, _):
					}
				if (expected.keys().hasNext())
					throw "missing inherited-value export: " + moduleId;
			}
		});
	}
}
