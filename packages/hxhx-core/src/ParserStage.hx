/**
	Build the compiler's parsed-module facts from Haxe source.

	`HxParser` is the single language parser for native and bootstrap builds.
	This stage adds module-local declaration facts needed by the current typed
	pipeline, then wraps the immutable declaration in a `ParsedModule`.
**/
class ParserStage {
	public function new() {}

	static function expectedMainClassFromFile(filePath:Null<String>):Null<String> {
		if (filePath == null || filePath.length == 0)
			return null;
		final name = haxe.io.Path.withoutDirectory(filePath);
		final dot = name.lastIndexOf(".");
		return dot <= 0 ? name : name.substr(0, dot);
	}

	public static function parse(source:String, ?filePath:String):ParsedModule {
		final expectedMainClass = expectedMainClassFromFile(filePath);
		final decl = enrichPureParserDecl(source, expectedMainClass, new HxParser(source).parseModule(expectedMainClass));
		final path = filePath == null || filePath.length == 0 ? "<memory>" : filePath;
		return new ParsedModule(source, decl, path);
	}

	static function enrichPureParserDecl(source:String, expectedMainClass:Null<String>, parsed:HxModuleDecl):HxModuleDecl {
		final enumDecls = ParserStageScanHelpers.scanModuleLocalHelperEnums(source, null);
		final typedefDecls = ParserStageScanHelpers.scanModuleLocalHelperTypedefs(source, null);
		final abstractDecls = ParserStageScanHelpers.scanModuleLocalHelperAbstracts(source, null);
		if ((enumDecls == null || enumDecls.length == 0)
			&& (typedefDecls == null || typedefDecls.length == 0)
			&& (abstractDecls == null || abstractDecls.length == 0))
			return parsed;

		final scannedOverlayByName:Map<String, HxClassDecl> = new Map();
		for (c in abstractDecls) {
			final nm = c == null ? null : HxClassDecl.getName(c);
			if (nm != null && nm.length > 0 && !scannedOverlayByName.exists(nm))
				scannedOverlayByName.set(nm, c);
		}
		for (c in enumDecls) {
			final nm = c == null ? null : HxClassDecl.getName(c);
			if (nm != null
				&& nm.length > 0
				&& HxClassDecl.getMetadata(c).indexOf("__hxhx_abstract") >= 0
				&& !scannedOverlayByName.exists(nm))
				scannedOverlayByName.set(nm, c);
		}
		for (c in typedefDecls) {
			final nm = c == null ? null : HxClassDecl.getName(c);
			if (nm != null && nm.length > 0)
				scannedOverlayByName.set(nm, c);
		}

		function hasMetadata(values:Array<String>, marker:String):Bool {
			if (values == null)
				return false;
			for (value in values)
				if (value == marker)
					return true;
			return false;
		}

		function mergeMetadata(existing:Array<String>, scanned:Array<String>):Array<String> {
			function metadataKey(raw:String):String {
				var text = raw == null ? "" : StringTools.trim(raw);
				if (StringTools.startsWith(text, "@"))
					text = text.substr(1);
				if (StringTools.startsWith(text, ":"))
					text = text.substr(1);
				final paren = text.indexOf("(");
				if (paren >= 0)
					text = text.substr(0, paren);
				return StringTools.trim(text);
			}

			final out = existing == null ? [] : existing.copy();
			if (scanned == null)
				return out;
			for (value in scanned) {
				final key = metadataKey(value);
				var exists = hasMetadata(out, value);
				if (!exists && key.length > 0) {
					for (existingValue in out) {
						if (metadataKey(existingValue) == key) {
							exists = true;
							break;
						}
					}
				}
				if (!exists)
					out.push(value);
			}
			return out;
		}

		function scannedFnsByName(scanned:HxClassDecl):Map<String, HxFunctionDecl> {
			final out:Map<String, HxFunctionDecl> = new Map();
			for (fn in HxClassDecl.getFunctions(scanned)) {
				final name = HxFunctionDecl.getName(fn);
				if (name != null && name.length > 0 && !out.exists(name))
					out.set(name, fn);
			}
			return out;
		}

		function scannedFieldsByName(scanned:HxClassDecl):Map<String, HxFieldDecl> {
			final out:Map<String, HxFieldDecl> = new Map();
			for (field in HxClassDecl.getFields(scanned)) {
				final name = HxFieldDecl.getName(field);
				if (name != null && name.length > 0 && !out.exists(name))
					out.set(name, field);
			}
			return out;
		}

		var changed = false;
		function overlayScannedDecl(cls:HxClassDecl):HxClassDecl {
			if (cls == null)
				return cls;
			final scanned = scannedOverlayByName.get(HxClassDecl.getName(cls));
			if (scanned == null)
				return cls;

			final scannedFns = scannedFnsByName(scanned);
			final patchedFns = new Array<HxFunctionDecl>();
			final existingFns:Map<String, Bool> = new Map();
			var overlayChanged = false;
			for (fn in HxClassDecl.getFunctions(cls)) {
				final scannedFn = scannedFns.get(HxFunctionDecl.getName(fn));
				if (scannedFn == null) {
					patchedFns.push(fn);
					final name = HxFunctionDecl.getName(fn);
					if (name != null && name.length > 0)
						existingFns.set(name, true);
					continue;
				}
				final isStatic = HxFunctionDecl.getIsStatic(scannedFn);
				final metadata = mergeMetadata(HxFunctionDecl.getMetadata(fn), HxFunctionDecl.getMetadata(scannedFn));
				final returnType = HxFunctionDecl.getReturnTypeHint(fn)
					.length == 0 ? HxFunctionDecl.getReturnTypeHint(scannedFn) : HxFunctionDecl.getReturnTypeHint(fn);
				final hasBody = HxFunctionDecl.getHasBody(scannedFn);
				if (isStatic != HxFunctionDecl.getIsStatic(fn)
					|| metadata.length != HxFunctionDecl.getMetadata(fn).length
					|| returnType != HxFunctionDecl.getReturnTypeHint(fn)
					|| hasBody != HxFunctionDecl.getHasBody(fn))
					overlayChanged = true;
				patchedFns.push(new HxFunctionDecl(HxFunctionDecl.getName(fn), HxFunctionDecl.getVisibility(fn), isStatic, HxFunctionDecl.getArgs(fn),
					returnType, HxFunctionDecl.getBody(fn), HxFunctionDecl.getReturnStringLiteral(fn), metadata, HxFunctionDecl.getPos(fn),
					HxFunctionDecl.getEndPos(fn), HxFunctionDecl.getBodyText(fn), hasBody));
				final name = HxFunctionDecl.getName(fn);
				if (name != null && name.length > 0)
					existingFns.set(name, true);
			}
			for (fn in HxClassDecl.getFunctions(scanned)) {
				final name = HxFunctionDecl.getName(fn);
				if (name != null && name.length > 0 && !existingFns.exists(name)) {
					patchedFns.push(fn);
					existingFns.set(name, true);
					overlayChanged = true;
				}
			}

			final scannedFields = scannedFieldsByName(scanned);
			final patchedFields = new Array<HxFieldDecl>();
			final existingFields:Map<String, Bool> = new Map();
			for (field in HxClassDecl.getFields(cls)) {
				final scannedField = scannedFields.get(HxFieldDecl.getName(field));
				if (scannedField == null) {
					patchedFields.push(field);
					final name = HxFieldDecl.getName(field);
					if (name != null && name.length > 0)
						existingFields.set(name, true);
					continue;
				}
				final isStatic = HxFieldDecl.getIsStatic(scannedField);
				final metadata = mergeMetadata(HxFieldDecl.getMetadata(field), HxFieldDecl.getMetadata(scannedField));
				final typeHint = HxFieldDecl.getTypeHint(field).length == 0 ? HxFieldDecl.getTypeHint(scannedField) : HxFieldDecl.getTypeHint(field);
				if (isStatic != HxFieldDecl.getIsStatic(field)
					|| metadata.length != HxFieldDecl.getMetadata(field).length
					|| typeHint != HxFieldDecl.getTypeHint(field))
					overlayChanged = true;
				patchedFields.push(new HxFieldDecl(HxFieldDecl.getName(field), HxFieldDecl.getVisibility(field), isStatic, typeHint,
					HxFieldDecl.getInit(field), metadata, HxFieldDecl.getPos(field), HxFieldDecl.getEndPos(field), HxFieldDecl.getIsFinal(field),
					HxFieldDecl.getPropertyGet(field), HxFieldDecl.getPropertySet(field), HxFieldDecl.getInitText(field)));
				final name = HxFieldDecl.getName(field);
				if (name != null && name.length > 0)
					existingFields.set(name, true);
			}
			for (field in HxClassDecl.getFields(scanned)) {
				final name = HxFieldDecl.getName(field);
				if (name != null && name.length > 0 && !existingFields.exists(name)) {
					patchedFields.push(field);
					existingFields.set(name, true);
					overlayChanged = true;
				}
			}

			final metadata = mergeMetadata(HxClassDecl.getMetadata(cls), HxClassDecl.getMetadata(scanned));
			if (metadata.length != HxClassDecl.getMetadata(cls).length)
				overlayChanged = true;
			if (overlayChanged)
				changed = true;
			return overlayChanged ? new HxClassDecl(HxClassDecl.getName(cls), HxClassDecl.getHasStaticMain(cls), patchedFns, patchedFields,
				HxClassDecl.getExtendsPath(cls), metadata, HxClassDecl.getIsInterface(cls), HxClassDecl.getImplementsPaths(cls),
				HxClassDecl.getVisibility(cls)) : cls;
		}

		final parsedMain = HxModuleDecl.getMainClass(parsed);
		final parsedMainIsPlaceholder = parsedMain != null
			&& HxClassDecl.getName(parsedMain) == "Unknown"
			&& expectedMainClass != null
			&& expectedMainClass.length > 0
			&& expectedMainClass != "Unknown"
			&& HxClassDecl.getFunctions(parsedMain).length == 0
			&& HxClassDecl.getFields(parsedMain).length == 0;
		var main = parsedMain;
		main = overlayScannedDecl(main);
		var mainName = main == null ? "" : HxClassDecl.getName(main);
		if (expectedMainClass != null && expectedMainClass.length > 0) {
			for (c in enumDecls) {
				final nm = HxClassDecl.getName(c);
				if (nm == expectedMainClass) {
					main = c;
					mainName = nm;
					changed = true;
					break;
				}
			}
			for (c in abstractDecls) {
				final nm = HxClassDecl.getName(c);
				if (nm == expectedMainClass) {
					main = c;
					mainName = nm;
					changed = true;
					break;
				}
			}
		}

		final classes = new Array<HxClassDecl>();
		final seen:Map<String, Bool> = new Map();
		function pushUnique(c:HxClassDecl):Void {
			c = overlayScannedDecl(c);
			if (c == null)
				return;
			final nm = HxClassDecl.getName(c);
			if (nm != null && nm.length > 0 && seen.exists(nm))
				return;
			classes.push(c);
			if (nm != null && nm.length > 0)
				seen.set(nm, true);
		}

		pushUnique(main);
		for (c in HxModuleDecl.getClasses(parsed))
			// The pure parser has to provide a main-class object even for an enum-only
			// module. Once scanning finds the expected real declaration, that exact
			// empty placeholder must not survive as another target-visible class.
			if (!(parsedMainIsPlaceholder && c == parsedMain && main != parsedMain))
				pushUnique(c);
		for (c in enumDecls) {
			final nm = HxClassDecl.getName(c);
			if (nm != null && nm.length > 0 && !seen.exists(nm)) {
				changed = true;
				pushUnique(c);
			}
		}
		for (c in typedefDecls) {
			final nm = HxClassDecl.getName(c);
			if (nm != null && nm.length > 0 && !seen.exists(nm)) {
				changed = true;
				pushUnique(c);
			}
		}
		for (c in abstractDecls) {
			final nm = HxClassDecl.getName(c);
			if (nm != null && nm.length > 0 && !seen.exists(nm)) {
				changed = true;
				pushUnique(c);
			}
		}

		return changed ? new HxModuleDecl(HxModuleDecl.getPackagePath(parsed), HxModuleDecl.getDirectives(parsed), main, classes,
			HxModuleDecl.getHeaderOnly(parsed), HxModuleDecl.getHasToplevelMain(parsed)) : parsed;
	}

	/**
		Return the deterministic identity of the Haxe-authored parser pipeline.

		The value changes when parser behavior or its reusable artifact schema
		changes. It has no request-varying environment component because one
		compiler process now has exactly one parser.
	**/
	public static function cacheConfigurationRevision():String {
		return "hxhx-parser-schema-v2|frontend=haxe";
	}
}
