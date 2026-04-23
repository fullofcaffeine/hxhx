package hxhx;

/**
	Stage3 build-macro metadata and hook support helpers.

	Why
	- `Stage3Compiler` still owned build-macro snippet parsing, build-field payload
	  encoding, metadata collection, and `onTypeNotFound` hook dispatch.
	- Those pieces are macro-support glue around the Stage3 driver, not the driver
	  control flow itself.

	What
	- Parses generated member snippets into `HxFunctionDecl`/`HxFieldDecl`.
	- Encodes build-field payloads from parsed modules.
	- Collects build-macro expressions from source text.
	- Dispatches `Context.onTypeNotFound` hooks through the active macro session.

	How
	- Preserve the existing parsing behavior and logging contract.
	- Keep the helper surface narrow and Stage3-specific.
**/
class Stage3BuildMacroSupport {
	public static function parseGeneratedMembers(members:Array<String>):{functions:Array<HxFunctionDecl>, fields:Array<HxFieldDecl>} {
		if (members == null || members.length == 0)
			return {functions: [], fields: []};
		#if hxhx_stage0_no_hx_parser
		return {functions: [], fields: []};
		#else
		final combined = members.join("\n");
		final fake = "class __HxHxBuildFields {\n" + combined + "\n}\n";
		final parser = new HxParser(fake);
		final decl = parser.parseModule();
		final cls = HxModuleDecl.getMainClass(decl);
		return {
			functions: HxClassDecl.getFunctions(cls),
			fields: HxClassDecl.getFields(cls)
		};
		#end
	}

	public static function buildFieldsPayloadForParsed(pm:ParsedModule):String {
		return hxhx.macro.BuildFieldSnapshotPayload.encodeParsedModule(pm);
	}

	public static function collectBuildMacroExprs(source:String, modulePath:String):Array<String> {
		return BuildMetadataCollector.collectBuildMacroExprs(source, modulePath);
	}

	public static function dispatchOnTypeNotFoundHooks(macroSession:Null<MacroRuntimeSession>, typePath:String):Bool {
		if (macroSession == null || typePath == null || typePath.length == 0)
			return false;
		final hooks = hxhx.macro.MacroState.listOnTypeNotFoundHookIds();
		if (hooks.length == 0)
			return false;
		for (i in 0...hooks.length) {
			if (macroSession.runTypeNotFoundHook(hooks[i], typePath)) {
				Sys.println("hook_onTypeNotFound[" + i + "]=" + typePath);
				return true;
			}
		}
		return false;
	}
}
