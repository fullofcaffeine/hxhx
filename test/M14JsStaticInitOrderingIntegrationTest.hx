import backend.BackendContext;
import backend.js.JsBackend;
import backend.js.JsTargetCore;
import haxe.io.Path;
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

	static function typedModule(packagePath:String, cls:HxClassDecl, filePath:String):TypedModule {
		final decl = new HxModuleDecl(packagePath, [], cls, [cls], false, false);
		return TyperStage.typeModule(new ParsedModule("", decl, filePath));
	}

	static function sysToolsClass():HxClassDecl {
		final lazyReference = HxExpr.ELambda([], HxExpr.EBinop("!=", HxExpr.EField(HxExpr.EIdent("StringTools"), "winMetaCharacters"), HxExpr.ENull));
		return new HxClassDecl("SysTools", false, [], [
			new HxFieldDecl("winMetaCharacters", HxVisibility.Public, true, "Array<Int>", HxExpr.EArrayDecl([HxExpr.EInt(32)])),
			new HxFieldDecl("lazyStringToolsCheck", HxVisibility.Public, true, "Void->Bool", lazyReference)
		]);
	}

	static function sysToolsModule():TypedModule {
		return typedModule("haxe", sysToolsClass(), "haxe/SysTools.hx");
	}

	static function stringToolsClass(collapsedPath:Bool):HxClassDecl {
		// Native protocol decoding may preserve a qualified static read as one
		// compacted source fragment when the small bootstrap parser cannot lower it.
		final compactedInit = "casthaxe.SysTools.winMetaCharacters";
		final fieldRead = HxExpr.EField(HxExpr.EField(HxExpr.EIdent("haxe"), "SysTools"), "winMetaCharacters");
		final eagerReference = collapsedPath ? null : HxExpr.ECast(fieldRead, "Array<Int>");
		return new HxClassDecl("StringTools", false, [], [
			new HxFieldDecl("winMetaCharacters", HxVisibility.Public, true, "Array<Int>", eagerReference, null, null, null, false, "", "",
				collapsedPath ? compactedInit : "")
		]);
	}

	static function stringToolsModule():TypedModule {
		return typedModule("", stringToolsClass(false), "StringTools.hx");
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
				decl: stringToolsClass(true),
				exposeToplevelMain: false
			};
			final stringToolsDependencies:Array<String> = @:privateAccess JsTargetCore.staticInitClassDeps(cast stringToolsUnit, byFullName, bySimpleFullName);
			assertTrue(stringToolsDependencies.indexOf("haxe.SysTools") >= 0, "a qualified static-field identifier should depend on its owning class");

			// Keep the dependent class first so the backend must reorder it.
			final program = new MacroExpandedProgram([stringToolsModule(), sysToolsModule()], false);
			final artifactPath = Path.join([outDir, "main.js"]);
			new JsBackend().emit(program, new BackendContext(outDir, artifactPath, "", true, false, HxDefineMap.fromRawDefines(["js=1", "js-es=5"])));
			final js = File.getContent(artifactPath);
			final dependency = js.indexOf("var __hx_cls_haxe_SysTools = function");
			final eagerRead = js.indexOf("__hx_cls_StringTools.winMetaCharacters = __hx_cls_haxe_SysTools.winMetaCharacters");
			assertTrue(dependency >= 0, "generated JavaScript should contain haxe.SysTools");
			assertTrue(eagerRead >= 0, "generated JavaScript should contain the StringTools static-field read");
			assertTrue(dependency < eagerRead, "haxe.SysTools must be created before StringTools reads its static field");
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
	}
}
