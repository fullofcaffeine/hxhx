import hxhx.Stage1Compiler.Stage1Args;
import hxhx.Stage3SetupSupport;
import backend.source.SourceNativeTarget;
import backend.source.SourceTargetCommon;
import backend.source.SourceFunctionRenderFrame.SourceFunctionRenderFrameTools;

/**
	Execute a typed read/write body using the real Lua Table declaration. The host
	supplies a table so this check isolates indexing from table creation and class
	initialization. Whole-program Lua execution remains a separate acceptance test.
 */
class M14ArrayAccessLuaObserver {
	public static function run():Void {
		final root = ".tmp/lua_array_access_observer";
		sys.FileSystem.createDirectory(root);
		final source = "class Main {static function change(store:lua.Table<Int,Int>):Int {store[1] = store[1] + 2; return store[1];}}";
		final upstreamRoot = root + "/upstream";
		sys.FileSystem.createDirectory(upstreamRoot);
		final upstreamSource = "class Main {static function change(store:lua.Table<Int,Int>):Int {store[1] = store[1] + 2; return store[1];} static function main():Void {final store:lua.Table<Int,Int> = lua.Table.create([5]); Sys.println(change(store)); Sys.println(store[1]);}}";
		sys.io.File.saveContent(upstreamRoot + "/Main.hx", upstreamSource);
		M14Stage3RuntimeFixture.observe({
			command: "node_modules/.bin/haxe",
			arguments: [
				"-D",
				"lua_vanilla",
				"-cp",
				upstreamRoot,
				"-main",
				"Main",
				"-lua",
				upstreamRoot + "/Main.lua"
			],
			expected: ""
		});
		M14Stage3RuntimeFixture.observe({command: "lua", arguments: [upstreamRoot + "/Main.lua"], expected: "7\n7\n"});
		Sys.println("LUA_ARRAY_ACCESS_UPSTREAM:PASS");
		final path = root + "/Main.hx";
		sys.io.File.saveContent(path, source);
		final args = Stage1Args.parse(["-cp", root, "-main", "Main"], true);
		final paths = Stage3SetupSupport.projectClassPaths({
			explicitPaths: [root],
			libraries: [],
			cwd: Sys.getCwd(),
			standardRoot: Stage1Args.getStandardLibraryRoot(args),
			targetDefine: "lua"
		});
		final defines = Stage3SetupSupport.buildDefinesMap(["lua_vanilla"], "lua", "lua-native");
		final resolved = new ResolvedModule("Main", path, ParserStage.parse(source, path));
		final index = TyperIndex.buildHeaders([resolved]);
		final loader = new ModuleLoader(paths, defines, index);
		loader.markResolvedAlready([resolved]);
		if (loader.ensureTypeAvailable("lua.Table", "", []) == null)
			throw "missing actual Lua Table provider";
		final typed = TyperStage.typeResolvedModule(resolved, index, loader, true);
		final projection = typed.getBackendProjection().getClasses()[0].getFunctions()[0];
		final program = new MacroExpandedProgram([typed], false);
		final frame = SourceFunctionRenderFrameTools.forTypedFunction(Lua, projection, program);
		final body = @:privateAccess SourceTargetCommon.renderFunctionStmtsWithFrame(frame, projection.getBody(), " ", projection.getStableIdentity())
			.join("\n");
		final output = root + "/observer.lua";
		sys.io.File.saveContent(output, "local function change(store)\n" + body + "\nend\nlocal store = {[1]=5}\nprint(change(store))\nprint(store[1])\n");
		M14Stage3RuntimeFixture.observe({command: "lua", arguments: [output], expected: "7\n7\n"});
		Sys.println("LUA_ARRAY_ACCESS:PASS");
	}
}
