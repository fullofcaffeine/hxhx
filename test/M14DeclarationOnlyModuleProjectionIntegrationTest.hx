import backend.vm.NekoTypedProgramProjection;

/** Declaration-only modules retain type facts without inventing runtime classes. */
class M14DeclarationOnlyModuleProjectionIntegrationTest {
	static function project(source:String, name:String):{module:TypedBackendModuleProjection, index:TyperIndex} {
		final parsed = ParserStage.parse(source, name + ".hx");
		final resolved = new ResolvedModule(name, name + ".hx", parsed);
		final index = TyperIndex.build([resolved]);
		final loader = new ModuleLoader(["."], new haxe.ds.StringMap<String>(), index, _ -> false);
		loader.markResolvedAlready([resolved]);
		return {module: TyperStage.typeResolvedModule(resolved, index, loader).getBackendProjection(), index: index};
	}

	static function main():Void {
		final record = project("typedef Record = { final count:Int; }", "Record");
		if (record.index.getByFullName("Record") == null)
			throw "the typedef lost its semantic declaration";
		if (record.module.getClasses().length != 1 || HxClassDecl.getName(record.module.getClasses()[0].getDeclaration()) != "Record")
			throw "the typedef catalog contains an invented class";
		new NekoTypedProgramProjection("neko-projection-test", [record.module]).requireClass("Record");
		if (record.module.getClasses()[0].requireSemanticFacts().findField("Record#instance#count") == null)
			throw "the typedef lost its structural field facts";
		for (result in [project("", "Empty"), project("import haxe.Json;", "Imports")]) {
			if (result.module.getClasses().length != 0)
				throw "a declaration-only module gained an invented runtime class";
			new NekoTypedProgramProjection("neko-projection-test", [result.module]);
		}
		final actual = project("class Unknown { public function new() {} } class Helper {}", "Unknown");
		if (actual.module.getClasses().length != 2)
			throw "a real class named Unknown was removed";
		new NekoTypedProgramProjection("neko-projection-test", [actual.module]).requireClass("Unknown");
		new NekoTypedProgramProjection("neko-projection-test", [actual.module]).requireClass("Unknown.Helper");
		final entry = project("function main():Void { Sys.println(42); }", "Entry");
		if (entry.module.getClasses().length != 1 || entry.module.getClasses()[0].getFunctions().length != 1)
			throw "the module-level entrypoint lost its callable declaration";
		new NekoTypedProgramProjection("neko-projection-test", [entry.module]);
		Sys.println("DECLARATION_ONLY_MODULE_PROJECTION:PASS");
	}
}
