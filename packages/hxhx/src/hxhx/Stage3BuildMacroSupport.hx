package hxhx;

import hxhx.macro.BuildFieldSnapshotPayload;
import hxhx.macro.MacroRuntimeSession;

/**
	Stage3 build-macro metadata and hook support helpers.

	Why
	- `Stage3Compiler` still owned build-macro snippet parsing, build-field payload
	  encoding, metadata collection, and `onTypeNotFound` hook dispatch.
	- Those pieces are macro-support glue around the Stage3 driver, not the driver
	  control flow itself.

	What
	- Parses generated member snippets into `HxFunctionDecl`/`HxFieldDecl`.
	- Applies add-or-replace member behavior and attaches a privacy-safe result
	  revision to the rebuilt module.
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

	/**
		Apply all generated member snippets to one resolved module.

		Build macros currently use add-or-replace behavior: a generated member with
		the same name replaces the source member, while other source members remain.
		The rebuilt module carries a SHA-256 identity of the generated snippets so a
		future server cannot reuse stale typed declarations when macro output changes.
	**/
	public static function applyGeneratedMembers(module:ResolvedModule, members:Array<String>):ResolvedModule {
		if (module == null)
			throw "build-macro generated members require a resolved module";
		if (members == null || members.length == 0)
			return module;
		final generated = parseGeneratedMembers(members);
		final parsed = ResolvedModule.getParsed(module);
		final oldDeclaration = parsed.getDecl();
		final oldClass = HxModuleDecl.getMainClass(oldDeclaration);
		final generatedFunctionNames = new Map<String, Bool>();
		for (fn in generated.functions)
			generatedFunctionNames.set(HxFunctionDecl.getName(fn), true);
		final generatedFieldNames = new Map<String, Bool>();
		for (field in generated.fields)
			generatedFieldNames.set(HxFieldDecl.getName(field), true);

		final mergedFunctions = new Array<HxFunctionDecl>();
		for (fn in HxClassDecl.getFunctions(oldClass))
			if (!generatedFunctionNames.exists(HxFunctionDecl.getName(fn)))
				mergedFunctions.push(fn);
		for (fn in generated.functions)
			mergedFunctions.push(fn);

		final mergedFields = new Array<HxFieldDecl>();
		for (field in HxClassDecl.getFields(oldClass))
			if (!generatedFieldNames.exists(HxFieldDecl.getName(field)))
				mergedFields.push(field);
		for (field in generated.fields)
			mergedFields.push(field);

		final newClass = new HxClassDecl(HxClassDecl.getName(oldClass), HxClassDecl.getHasStaticMain(oldClass), mergedFunctions, mergedFields,
			HxClassDecl.getExtendsPath(oldClass), HxClassDecl.getMetadata(oldClass));
		final newClasses = new Array<HxClassDecl>();
		for (candidate in HxModuleDecl.getClasses(oldDeclaration))
			newClasses.push(HxClassDecl.getName(candidate) == HxClassDecl.getName(oldClass) ? newClass : candidate);
		final newDeclaration = new HxModuleDecl(HxModuleDecl.getPackagePath(oldDeclaration), HxModuleDecl.getImports(oldDeclaration), newClass, newClasses,
			HxModuleDecl.getHeaderOnly(oldDeclaration), HxModuleDecl.getHasToplevelMain(oldDeclaration));
		final newParsed = new ParsedModule(parsed.getSource(), newDeclaration, parsed.getFilePath());
		return new ResolvedModule(ResolvedModule.getModulePath(module), ResolvedModule.getFilePath(module), newParsed, ResolvedModule.getSourceOrigin(module),
			ResolvedModule.getConditionalCompilation(module), CompilerGeneratedDeclarationObservation.fromGeneratedMemberSnippets(members));
	}

	public static function buildFieldsPayloadForParsed(pm:ParsedModule):String {
		return BuildFieldSnapshotPayload.encodeParsedModule(pm);
	}

	public static function collectBuildMacroExprs(source:String, modulePath:String):Array<String> {
		return BuildMetadataCollector.collectBuildMacroExprs(source, modulePath);
	}

	public static function dispatchOnTypeNotFoundHooks(macroSession:Null<MacroRuntimeSession>, typePath:String, ?output:CompilationRequestOutput):Bool {
		if (macroSession == null || typePath == null || typePath.length == 0)
			return false;
		final hooks = hxhx.macro.MacroState.listOnTypeNotFoundHookIds();
		if (hooks.length == 0)
			return false;
		for (i in 0...hooks.length) {
			if (macroSession.runTypeNotFoundHook(hooks[i], typePath)) {
				CompilationRequestOutput.writeStdoutLine(output, "hook_onTypeNotFound[" + i + "]=" + typePath);
				return true;
			}
		}
		return false;
	}
}
