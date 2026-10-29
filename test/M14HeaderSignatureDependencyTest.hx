import sys.io.File;
import sys.FileSystem;

/** Parent declarations must be resolved before a lazy provider publishes its class signature. */
class M14HeaderSignatureDependencyTest {
	static function check(value:Bool, message:String):Void {
		if (!value)
			throw message;
	}

	static function main():Void {
		final root = ".tmp/header_signature_dependencies_" + Date.now().getTime();
		FileSystem.createDirectory(root);
		final sources = [
			{name: "Main", source: 'class Main { static function main() { var value = new Derived(); Sys.println("headers"); } }'},
			{name: "Derived", source: 'class Derived extends Base<Payload> implements Contract<Payload> {}'},
			{name: "Base", source: 'class Base<T> { public function new() {} }'},
			{name: "Contract", source: 'interface Contract<T> extends RootContract<T> {}'},
			{name: "RootContract", source: 'interface RootContract<T> {}'},
			{name: "Payload", source: 'class Payload {}'},
			{name: "GenericDerived", source: 'class GenericDerived<T> extends Base<T> {}'},
			{name: "T", source: 'This is not a module and must never be loaded for a binder.'}
		];
		for (entry in sources)
			File.saveContent(root + "/" + entry.name + ".hx", entry.source);
		final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["60", "node_modules/.bin/haxe", "-cp", root, "--run", "Main"]);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final status = process.exitCode();
		process.close();
		check(status == 0 && stdout == "headers\n", "upstream header contract failed: " + stdout + stderr);
		for (expand in [false, true]) {
			final module = new ResolvedModule("Main", root + "/Main.hx", ParserStage.parse(sources[0].source, root + "/Main.hx"));
			final index = TyperIndex.build([module]);
			final loader = new ModuleLoader([root], new haxe.ds.StringMap<String>(), index, null, expand);
			loader.markResolvedAlready([module]);
			final provider = loader.ensureTypeAvailable("Derived", "", []);
			check(Std.isOfType(provider, TyClassInfo), "missing class provider");
			// The provider's validated declaration kind owns its inheritance facts.
			final derived:TyClassInfo = cast provider;
			check(derived.getSuperType().getSemanticKey() == "nominal:Base<nominal:Payload>", "parent signature is unresolved before body typing");
			check(derived.getInterfaceTypes()[0].getSemanticKey() == "nominal:Contract<nominal:Payload>", "interface signature is unresolved");
			check(index.getByFullName("RootContract") != null, "transitive interface parent was not loaded");
			final generic = loader.ensureTypeAvailable("GenericDerived", "", []);
			check(Std.isOfType(generic, TyClassInfo), "missing generic class provider");
			final genericClass:TyClassInfo = cast generic;
			check(genericClass.getSuperType().getTypeArguments()[0].getTypeParameterIdentity().equals(genericClass.getTypeParameterIds()[0]),
				"header lost its exact local binder");
			check(index.getByFullName("T") == null, "a generic binder loaded a source module");
			final added = loader.drainNewModules();
			for (name in ["Derived", "Base", "Payload", "Contract", "RootContract", "GenericDerived"])
				check([for (loaded in added) if (ResolvedModule.getModulePath(loaded) == name) loaded].length == 1, "provider must load once: " + name);
			for (loaded in [module].concat(added))
				TyperStage.typeResolvedModule(loaded, index, loader);
		}
		for (entry in sources)
			FileSystem.deleteFile(root + "/" + entry.name + ".hx");
		FileSystem.deleteDirectory(root);
		Sys.println("HEADER_SIGNATURE_DEPENDENCY:PASS");
	}
}
