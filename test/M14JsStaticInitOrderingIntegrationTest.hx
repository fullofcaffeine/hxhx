import backend.BackendContext;
import backend.js.JsBackend;
import backend.js.JsTargetCore;
import haxe.io.Path;
import hxhx.Stage1Compiler.Stage1Args;
import hxhx.Stage3SetupSupport;
import sys.FileSystem;
import sys.io.File;

/**
	Checks that lazy callbacks do not create false JavaScript startup dependencies.

	A class used only inside a callback does not need to exist when that callback is
	created. Treating the callback body as immediate work can invent dependency cycles
	and leave real static-field reads in the wrong order.
**/
class M14JsStaticInitOrderingIntegrationTest {
	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function deleteRecursive(path:String):Void {
		if (!FileSystem.exists(path))
			return;
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path))
				deleteRecursive(Path.join([path, entry]));
			FileSystem.deleteDirectory(path);
			return;
		}
		FileSystem.deleteFile(path);
	}

	/** Executable callbacks need the source-function identity supplied by normal parsing. */
	static function resolvedModule(name:String, source:String):ResolvedModule {
		final filePath = name.split(".").join("/") + ".hx";
		return new ResolvedModule(name, filePath, ParserStage.parse(source, filePath));
	}

	static function sysToolsClass():HxClassDecl {
		final lazyReference = HxExpr.ELambda([], HxExpr.EBinop("!=", HxExpr.EField(HxExpr.EIdent("StringTools"), "winMetaCharacters"), HxExpr.ENull));
		return new HxClassDecl("SysTools", false, [], [
			new HxFieldDecl("winMetaCharacters", HxVisibility.Public, true, "Array<Int>", HxExpr.EArrayDecl([HxExpr.EInt(32)])),
			new HxFieldDecl("lazyStringToolsCheck", HxVisibility.Public, true, "Void->Bool", lazyReference)
		]);
	}

	static function sysToolsModule():ResolvedModule {
		return resolvedModule("haxe.SysTools",
			"package haxe; class SysTools {"
			+ " public static var winMetaCharacters:Array<Int> = [32];"
			+ " public static var lazyStringToolsCheck:Void->Bool = () -> StringTools.winMetaCharacters != null;"
			+ " }");
	}

	static function stringToolsClass():HxClassDecl {
		// Native protocol decoding may preserve a qualified static read as one
		// compacted source fragment when the small bootstrap parser cannot lower it.
		final compactedInit = "casthaxe.SysTools.winMetaCharacters";
		return new HxClassDecl("StringTools", false, [], [
			new HxFieldDecl("winMetaCharacters", HxVisibility.Public, true, "Array<Int>", null, null, null, null, false, "", "", compactedInit)
		]);
	}

	static function stringToolsModule():ResolvedModule {
		return resolvedModule("StringTools",
			"class StringTools {" + " public static var winMetaCharacters:Array<Int> = cast haxe.SysTools.winMetaCharacters;" + " }");
	}

	static function main():Void {
		final tmpRoot = Path.normalize(".tmp/m14_js_static_init_ordering_" + Std.string(Date.now().getTime()));
		final outDir = Path.join([tmpRoot, "out"]);
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(outDir);

		var failure:Null<String> = null;
		try {
			final byFullName = new haxe.ds.StringMap<String>();
			byFullName.set("haxe.SysTools", "__hx_cls_haxe_SysTools");
			byFullName.set("StringTools", "__hx_cls_StringTools");
			final bySimpleFullName = new haxe.ds.StringMap<String>();
			bySimpleFullName.set("SysTools", "haxe.SysTools");
			bySimpleFullName.set("StringTools", "StringTools");
			final unit = {
				fullName: "haxe.SysTools",
				jsRef: "__hx_cls_haxe_SysTools",
				decl: sysToolsClass(),
				exposeToplevelMain: false
			};
			final eagerDependencies:Array<String> = @:privateAccess JsTargetCore.staticInitClassDeps(cast unit, byFullName, bySimpleFullName);
			assertTrue(eagerDependencies.indexOf("StringTools") < 0, "a class used only inside a callback must not block JavaScript startup ordering");
			final stringToolsUnit = {
				fullName: "StringTools",
				jsRef: "__hx_cls_StringTools",
				decl: stringToolsClass(),
				exposeToplevelMain: false
			};
			final stringToolsDependencies:Array<String> = @:privateAccess JsTargetCore.staticInitClassDeps(cast stringToolsUnit, byFullName, bySimpleFullName);
			assertTrue(stringToolsDependencies.indexOf("haxe.SysTools") >= 0, "a qualified static-field identifier should depend on its owning class");

			// Keep the dependent class first so the backend must reorder it.
			final resolved = [stringToolsModule(), sysToolsModule()];
			final args = Stage1Args.parse(["-main", "StringTools"], true);
			if (args == null)
				throw "startup fixture arguments did not parse";
			final paths = Stage3SetupSupport.projectClassPaths({
				explicitPaths: [],
				libraries: [],
				cwd: Sys.getCwd(),
				standardRoot: Stage1Args.getStandardLibraryRoot(args),
				targetDefine: "js"
			});
			final defines = Stage3SetupSupport.buildDefinesMap(["js-es=5"], "js", "js-native");
			final index = TyperIndex.buildHeaders(resolved);
			final loader = new ModuleLoader(paths, defines, index, null, false);
			loader.markResolvedAlready(resolved);
			final program = new MacroExpandedProgram([for (module in resolved) TyperStage.typeResolvedModule(module, index, loader)], false);
			final artifactPath = Path.join([outDir, "main.js"]);
			new JsBackend().emit(program, new BackendContext(outDir, artifactPath, "", true, false, defines));
			final js = File.getContent(artifactPath);
			final dependency = js.indexOf("var __hx_cls_haxe_SysTools = function");
			final eagerRead = js.indexOf("__hx_cls_StringTools.winMetaCharacters = __hx_cls_haxe_SysTools.winMetaCharacters");
			assertTrue(dependency >= 0, "generated JavaScript should contain haxe.SysTools");
			assertTrue(eagerRead >= 0, "generated JavaScript should contain the StringTools static-field read");
			assertTrue(dependency < eagerRead, "haxe.SysTools must be created before StringTools reads its static field");
			@:privateAccess M14JsFunctionLiteralRuntimeTest.command("node", [artifactPath]);
		} catch (message:String) {
			failure = message;
		} catch (error:haxe.Exception) {
			failure = error.message;
		}

		if (failure != null) {
			Sys.println("debug_out=" + tmpRoot);
			throw failure;
		}
		deleteRecursive(tmpRoot);
		Sys.println("JS_STATIC_INIT_ORDERING:PASS");
	}
}
