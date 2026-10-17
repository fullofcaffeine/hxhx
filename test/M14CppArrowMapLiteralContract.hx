import backend.BackendContext;
import backend.BackendRegistry;
import sys.io.File;

/**
	Preserve the original Map program through source-only and native backend routes.
	Storage checks require the shared tracing heap; runtime output checks distinguish
	Map key families and keep ordinary array reads covered by the same program.
	Keeping this contract separate lets focused tests avoid the broad smoke harness.
**/
function run():Void {
	BackendRegistry.clearDynamicRegistrations();
	final root = haxe.io.Path.join([Sys.getCwd(), ".tmp", "m14_cpp_arrow_map_literal"]);
	final program = CppMapFixture.load();
	final defines = new haxe.ds.StringMap<String>();
	defines.set("no-compilation", "1");
	final sourceOnly = BackendRegistry.createForTarget("cpp-native")
		.emit(program, new BackendContext(root + "/source-only", null, "Main", true, true, defines));
	if (sourceOnly.builtExecutable)
		throw "source-only Map emission unexpectedly built an executable";
	final source = File.getContent(sourceOnly.entryPath);
	for (required in [
		"hxhx::managed::IntMapPayload",
		"hxhx::managed::StringMapPayload",
		"hxhx::managed::ObjectMapPayload",
		"hxhx::managed::InstancePayload",
		"hxhx::managed::EnumPayload",
		"hxhx::managed::ArrayPayload",
		"->constructorIndex(hxhx_enum_",
		"->insert(",
		"->contains(",
		"->readExisting("
	]) {
		if (source.indexOf(required) < 0)
			throw "Map fixture is missing managed storage operation: " + required;
	}
	for (forbidden in [
		"struct Map {",
		"__hxhx_make_shared_Map",
		"std::shared_ptr<",
		"std::vector<std::pair<"
	]) {
		if (source.indexOf(forbidden) >= 0)
			throw "Map fixture restored a retired storage representation: " + forbidden;
	}
	final built = BackendRegistry.createForTarget("cpp-native")
		.emit(program, new BackendContext(root + "/build", null, "Main", true, true, new haxe.ds.StringMap<String>()));
	if (!built.builtExecutable)
		throw "Map contract requires a native executable";
	final sources = built.artifacts.filter(artifact -> artifact.kind == "entry_cpp_source");
	if (sources.length != 1 || File.getContent(sources[0].path) != source)
		throw "source-only and native Map emission differ";
	final child = new sys.io.Process(built.entryPath, []);
	final stdout = child.stdout.readAll().toString();
	final stderr = child.stderr.readAll().toString();
	final code = child.exitCode();
	child.close();
	if (code != 0 || stderr != "" || stdout != File.getContent("test/oracle/cpp_arrow_map_literal_seed/expected.stdout"))
		throw "original Map contract failed: " + stdout + stderr;
}
