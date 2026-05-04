/**
	Stage 2 parser skeleton.

	What:
	- For now, this does *not* implement the Haxe grammar.
	- It exists to establish the module boundary and the “AST in / AST out” flow.

	How:
	- We return a tiny placeholder ParsedModule so downstream stages can be
	  written and tested without waiting for a full parser.

	Native hook:
	- When `-D hih_native_parser` is enabled, we call into the OCaml “native”
	  lexer/parser stubs (`HxHxNativeLexer` / `HxHxNativeParser`) via externs.
	  This matches the upstream bootstrap strategy: keep the frontend native
	  while we reimplement the rest of the compiler pipeline in Haxe.
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

	static function isIdentCode(code:Int):Bool {
		return (code >= 65 && code <= 90) || (code >= 97 && code <= 122) || (code >= 48 && code <= 57) || code == 95;
	}

	static function startsWithWord(source:String, index:Int, word:String):Bool {
		if (index < 0 || index + word.length > source.length)
			return false;
		if (source.substr(index, word.length) != word)
			return false;
		final beforeOk = index == 0 || !isIdentCode(source.charCodeAt(index - 1));
		final after = index + word.length;
		final afterOk = after >= source.length || !isIdentCode(source.charCodeAt(after));
		return beforeOk && afterOk;
	}

	static function skipSpaces(source:String, index:Int):Int {
		var i = index;
		while (i < source.length) {
			switch (source.charCodeAt(i)) {
				case 9 | 10 | 13 | 32:
					i++;
				case _:
					return i;
			}
		}
		return i;
	}

	static function findMatchingBrace(source:String, openIndex:Int):Int {
		var depth = 1;
		var i = openIndex + 1;
		var stringQuote = 0;
		var escaped = false;
		var lineComment = false;
		var blockComment = false;
		while (i < source.length) {
			final code = source.charCodeAt(i);
			final next = i + 1 < source.length ? source.charCodeAt(i + 1) : -1;
			if (lineComment) {
				if (code == 10 || code == 13)
					lineComment = false;
				i++;
				continue;
			}
			if (blockComment) {
				if (code == 42 && next == 47) {
					blockComment = false;
					i += 2;
				} else {
					i++;
				}
				continue;
			}
			if (stringQuote != 0) {
				if (escaped) {
					escaped = false;
				} else if (code == 92) {
					escaped = true;
				} else if (code == stringQuote) {
					stringQuote = 0;
				}
				i++;
				continue;
			}
			if (code == 47 && next == 47) {
				lineComment = true;
				i += 2;
				continue;
			}
			if (code == 47 && next == 42) {
				blockComment = true;
				i += 2;
				continue;
			}
			if (code == 34 || code == 39) {
				stringQuote = code;
				i++;
				continue;
			}
			if (code == 123) {
				depth++;
			} else if (code == 125) {
				depth--;
				if (depth == 0)
					return i;
			}
			i++;
		}
		return -1;
	}

	static function scanToplevelMainFunction(source:String):Null<HxFunctionDecl> {
		if (source == null || source.length == 0)
			return null;
		var index = 0;
		while (index < source.length) {
			final found = source.indexOf("function", index);
			if (found < 0)
				return null;
			index = found + "function".length;
			if (!startsWithWord(source, found, "function"))
				continue;
			final nameStart = skipSpaces(source, index);
			if (!startsWithWord(source, nameStart, "main"))
				continue;
			final open = source.indexOf("{", nameStart + "main".length);
			if (open < 0)
				return null;
			final close = findMatchingBrace(source, open);
			if (close < 0)
				return null;
			final bodyText = source.substring(open + 1, close);
			var body:Array<HxStmt> = [];
			#if !hxhx_stage0_no_hx_parser
			try {
				body = HxParser.offsetFunctionBodyColumns(HxParser.parseFunctionBodyTextAt(bodyText, source, open + 1), 1);
			} catch (_:HxParseError) {
				body = [];
			} catch (_:String) {
				body = [];
			}
			#end
			return new HxFunctionDecl("main", HxVisibility.Public, true, [], "Void", body, "", null, HxPos.unknown(), HxPos.unknown(), bodyText);
		}
		return null;
	}

	public static function parse(source:String, ?filePath:String):ParsedModule {
		final expectedMainClass = expectedMainClassFromFile(filePath);
		final decl =
			#if (hih_native_parser && !hxhx_stage0_no_native_parser)
			// Bring-up escape hatch: allow forcing the pure-Haxe parser even when the
			// native frontend is compiled in.
			//
			// Why
			// - The native frontend protocol v1 is intentionally "header/return only" and
			//   cannot represent full statement bodies.
			// - Some Stage3 bring-up rungs (e.g. `--hxhx-emit-full-bodies`) need bodies so
			//   we can validate statement lowering end-to-end.
			//
			// How
			// - `HIH_FORCE_HX_PARSER=1` selects the pure-Haxe frontend regardless of the
			//   compiled-in `hih_native_parser` define.
			((() -> {
				function enrichNativeDecl(nativeDecl:HxModuleDecl):HxModuleDecl {
					// Native protocol v1 only returns one "main" class. However, real Haxe modules
					// commonly declare additional helper types in the same file (especially in the
					// upstream unit/runci suites). We add a tiny, best-effort scanner to discover
					// those additional classes and their static members so Stage3 emission can
					// produce stub providers.
					var main = HxModuleDecl.getMainClass(nativeDecl);
					var mainName = HxClassDecl.getName(main);
					var staticPatchApplied = false;

					/**
						Normalize static member flags from a source scan.

						Why
						- Native parser payloads can occasionally degrade `static` metadata for
						  some methods in upstream-shaped std modules.
						- Stage3 emission uses `isStatic` to decide whether to inject a synthetic
						  receiver (`this_`). If the static flag is wrong, generated OCaml calls
						  can become partial applications and fail compilation.

						How
						- Re-scan class headers for explicit `static` declarations.
						- If a native class member is marked non-static but the scanner says it is
						  static, upgrade it to static.
						- Never downgrade native static flags from this scanner.
					**/
					final scannedClassStaticsByName:Map<String, HxClassDecl> = new Map();
					for (scanned in scanHelperClasses(source, null)) {
						final scannedName = scanned == null ? null : HxClassDecl.getName(scanned);
						if (scannedName != null && scannedName.length > 0 && !scannedClassStaticsByName.exists(scannedName))
							scannedClassStaticsByName.set(scannedName, scanned);
					}
					for (scanned in scanHelperAbstracts(source, null)) {
						final scannedName = scanned == null ? null : HxClassDecl.getName(scanned);
						if (scannedName != null && scannedName.length > 0 && !scannedClassStaticsByName.exists(scannedName))
							scannedClassStaticsByName.set(scannedName, scanned);
					}

					function patchClassStaticFlagsFromScan(cls:HxClassDecl):HxClassDecl {
						if (cls == null)
							return cls;
						final className = HxClassDecl.getName(cls);
						if (className == null || className.length == 0)
							return cls;
						final scanned = scannedClassStaticsByName.get(className);
						if (scanned == null)
							return cls;

						final scannedFnStaticByName:Map<String, Bool> = new Map();
						final scannedFnsByName:Map<String, Array<HxFunctionDecl>> = new Map();
						for (fn in HxClassDecl.getFunctions(scanned)) {
							final fnName = HxFunctionDecl.getName(fn);
							if (fnName != null && fnName.length > 0) {
								scannedFnStaticByName.set(fnName, HxFunctionDecl.getIsStatic(fn));
								final bucket = scannedFnsByName.exists(fnName) ? scannedFnsByName.get(fnName) : [];
								bucket.push(fn);
								scannedFnsByName.set(fnName, bucket);
							}
						}

						function hasMetadata(values:Array<String>, marker:String):Bool {
							if (values == null)
								return false;
							for (value in values) {
								if (value == marker)
									return true;
							}
							return false;
						}

						function mergeScannedMetadata(fn:HxFunctionDecl, scannedFn:Null<HxFunctionDecl>):Array<String> {
							final out = HxFunctionDecl.getMetadata(fn).copy();
							if (scannedFn != null) {
								for (value in HxFunctionDecl.getMetadata(scannedFn)) {
									if (!hasMetadata(out, value))
										out.push(value);
								}
							}
							return out;
						}

						function usefulHint(value:String):Bool {
							final s = StringTools.trim(value == null ? "" : value);
							return s.length > 0 && s != "Unknown";
						}

						function argsNeedScan(nativeArgs:Array<HxFunctionArg>, scannedArgs:Array<HxFunctionArg>, allowShapeRepair:Bool):Bool {
							if (nativeArgs == null || scannedArgs == null || nativeArgs.length != scannedArgs.length)
								return false;
							for (i in 0...nativeArgs.length) {
								if (!usefulHint(HxFunctionArg.getTypeHint(nativeArgs[i]))
									&& usefulHint(HxFunctionArg.getTypeHint(scannedArgs[i])))
									return true;
								if (allowShapeRepair
									&& HxFunctionArg.getIsOptional(nativeArgs[i]) != HxFunctionArg.getIsOptional(scannedArgs[i]))
									return true;
								if (allowShapeRepair && HxFunctionArg.getIsRest(nativeArgs[i]) != HxFunctionArg.getIsRest(scannedArgs[i]))
									return true;
								switch (HxFunctionArg.getDefaultValue(nativeArgs[i])) {
									case NoDefault:
										switch (HxFunctionArg.getDefaultValue(scannedArgs[i])) {
											case Default(_):
												return true;
											case NoDefault:
										}
									case Default(_):
								}
							}
							return false;
						}

						function nextScannedFn(name:String, used:Map<String, Int>):Null<HxFunctionDecl> {
							if (name == null || name.length == 0)
								return null;
							final bucket = scannedFnsByName.get(name);
							if (bucket == null || bucket.length == 0)
								return null;
							final index = used.exists(name) ? used.get(name) : 0;
							used.set(name, index + 1);
							return index < bucket.length ? bucket[index] : bucket[bucket.length - 1];
						}

						function sameMetadata(left:Array<String>, right:Array<String>):Bool {
							if (left == null || right == null)
								return left == right;
							if (left.length != right.length)
								return false;
							for (i in 0...left.length) {
								if (left[i] != right[i])
									return false;
							}
							return true;
						}

						function hasOnlyUnsupportedBody(body:Array<HxStmt>):Bool {
							if (body == null || body.length != 1)
								return false;
							return switch (body[0]) {
								case SExpr(EUnsupported(_), _) | SReturn(EUnsupported(_), _):
									true;
								case _:
									false;
							}
						}

						function scanBodyHasUnsupported(body:Array<HxStmt>):Bool {
							#if hxhx_stage0_no_parser_scan_extract
							return hasUnsupportedStmtList(body);
							#else
							return ParserStageScanHelpers.hasUnsupportedStmtList(body);
							#end
						}

						var changed = false;
						final scannedExtendsPath = HxClassDecl.getExtendsPath(scanned);
						final extendsPath = scannedExtendsPath != null
							&& scannedExtendsPath.length > 0 ? scannedExtendsPath : HxClassDecl.getExtendsPath(cls);
						if (extendsPath != HxClassDecl.getExtendsPath(cls))
							changed = true;
						final patchedFns = new Array<HxFunctionDecl>();
						final existingFnNames:Map<String, Bool> = new Map();
						final scannedFnUseByName:Map<String, Int> = new Map();
						for (fn in HxClassDecl.getFunctions(cls)) {
							final fnName = HxFunctionDecl.getName(fn);
							final scannedStatic = fnName == null ? null : scannedFnStaticByName.get(fnName);
							final isStatic = scannedStatic == null ? HxFunctionDecl.getIsStatic(fn) : scannedStatic;
							final scannedFn = nextScannedFn(fnName, scannedFnUseByName);
							final metadata = mergeScannedMetadata(fn, scannedFn);
							final metadataChanged = !sameMetadata(metadata, HxFunctionDecl.getMetadata(fn));
							final allowArgShapeRepair = scannedFn != null
								&& hasMetadata(HxFunctionDecl.getMetadata(scannedFn), "overload");
							final args = scannedFn != null
								&& argsNeedScan(HxFunctionDecl.getArgs(fn), HxFunctionDecl.getArgs(scannedFn),
									allowArgShapeRepair) ? HxFunctionDecl.getArgs(scannedFn) : HxFunctionDecl.getArgs(fn);
							final argsChanged = args != HxFunctionDecl.getArgs(fn);
							final returnType = scannedFn != null
								&& !usefulHint(HxFunctionDecl.getReturnTypeHint(fn))
								&& usefulHint(HxFunctionDecl.getReturnTypeHint(scannedFn)) ? HxFunctionDecl.getReturnTypeHint(scannedFn) : HxFunctionDecl.getReturnTypeHint(fn);
							final returnChanged = returnType != HxFunctionDecl.getReturnTypeHint(fn);
							final pos = scannedFn != null
								&& HxFunctionDecl.getPos(fn).getLine() <= 0 ? HxFunctionDecl.getPos(scannedFn) : HxFunctionDecl.getPos(fn);
							final endPos = scannedFn != null
								&& HxFunctionDecl.getEndPos(fn).getLine() <= 0 ? HxFunctionDecl.getEndPos(scannedFn) : HxFunctionDecl.getEndPos(fn);
							final posChanged = pos != HxFunctionDecl.getPos(fn) || endPos != HxFunctionDecl.getEndPos(fn);
							final scannedBody = scannedFn == null ? [] : HxFunctionDecl.getBody(scannedFn);
							final nativeBody = HxFunctionDecl.getBody(fn);
							final scannedHasUnsupported = scanBodyHasUnsupported(scannedBody);
							final bodyChanged = scannedBody.length > 0 && !scannedHasUnsupported;
							final body = bodyChanged ? scannedBody : HxFunctionDecl.getBody(fn);
							final bodyText = bodyChanged ? HxFunctionDecl.getBodyText(scannedFn) : HxFunctionDecl.getBodyText(fn);
							if (isStatic != HxFunctionDecl.getIsStatic(fn))
								changed = true;
							if (metadataChanged)
								changed = true;
							if (argsChanged)
								changed = true;
							if (returnChanged)
								changed = true;
							if (posChanged)
								changed = true;
							if (bodyChanged)
								changed = true;
							if (fnName != null && fnName.length > 0)
								existingFnNames.set(fnName, true);
							patchedFns.push(isStatic == HxFunctionDecl.getIsStatic(fn)
								&& !metadataChanged
								&& !argsChanged
								&& !returnChanged
								&& !posChanged
								&& !bodyChanged ? fn : new HxFunctionDecl(HxFunctionDecl.getName(fn), HxFunctionDecl.getVisibility(fn), isStatic, args,
									returnType, body, HxFunctionDecl.getReturnStringLiteral(fn), metadata, pos, endPos, bodyText));
						}
						for (fn in HxClassDecl.getFunctions(scanned)) {
							final fnName = HxFunctionDecl.getName(fn);
							if (fnName == null || fnName.length == 0 || existingFnNames.exists(fnName))
								continue;
							patchedFns.push(fn);
							existingFnNames.set(fnName, true);
							changed = true;
						}

						final patchedFields = new Array<HxFieldDecl>();
						final existingFieldNames:Map<String, Bool> = new Map();
						for (f in HxClassDecl.getFields(cls)) {
							patchedFields.push(f);
							final fieldName = HxFieldDecl.getName(f);
							if (fieldName != null && fieldName.length > 0)
								existingFieldNames.set(fieldName, true);
						}
						for (f in HxClassDecl.getFields(scanned)) {
							final fieldName = HxFieldDecl.getName(f);
							if (fieldName == null || fieldName.length == 0 || existingFieldNames.exists(fieldName))
								continue;
							patchedFields.push(f);
							existingFieldNames.set(fieldName, true);
							changed = true;
						}

						if (!changed)
							return cls;
						staticPatchApplied = true;
						return new HxClassDecl(HxClassDecl.getName(cls), HxClassDecl.getHasStaticMain(cls), patchedFns, patchedFields, extendsPath);
					}

					// Some upstream modules have a non-class main type (notably enums).
					//
					// If the native protocol returns `Unknown`, scan for a matching top-level enum
					// and treat it as the module's main provider so emission doesn't drop the unit.
					final enumDeclsAll = scanHelperEnums(source, null);
					final typedefDeclsAll = scanHelperTypedefs(source, null);
					final abstractDeclsAll = scanHelperAbstracts(source, null);
					var scannedMainEnum:Null<HxClassDecl> = null;
					if (expectedMainClass != null && expectedMainClass.length > 0) {
						for (c in enumDeclsAll) {
							final nm = HxClassDecl.getName(c);
							if (nm != null && nm == expectedMainClass) {
								scannedMainEnum = c;
								break;
							}
						}
					}
					if (scannedMainEnum != null) {
						main = scannedMainEnum;
						mainName = HxClassDecl.getName(scannedMainEnum);
						staticPatchApplied = true;
					} else if ((mainName == null || mainName.length == 0 || mainName == "Unknown") && expectedMainClass != null) {
						function tryPickMainFrom(candidates:Array<HxClassDecl>):Bool {
							if (candidates == null)
								return false;
							for (c in candidates) {
								final nm = HxClassDecl.getName(c);
								if (nm != null && nm == expectedMainClass) {
									main = c;
									mainName = nm;
									return true;
								}
							}
							return false;
						}

						if (!tryPickMainFrom(enumDeclsAll)) {
							if (!tryPickMainFrom(typedefDeclsAll))
								tryPickMainFrom(abstractDeclsAll);
						}
					}

					final topMain = expectedMainClass != null && expectedMainClass.length > 0 ? scanToplevelMainFunction(source) : null;
					if (topMain != null) {
						var mainHasMain = false;
						for (fn in HxClassDecl.getFunctions(main)) {
							if (HxFunctionDecl.getName(fn) == "main") {
								mainHasMain = true;
								break;
							}
						}
						if (mainName == null || mainName.length == 0 || mainName == "Unknown" || mainName != expectedMainClass) {
							main = new HxClassDecl(expectedMainClass, true, [topMain], []);
							mainName = expectedMainClass;
						} else if (!mainHasMain) {
							final functions = HxClassDecl.getFunctions(main).copy();
							functions.push(topMain);
							main = new HxClassDecl(HxClassDecl.getName(main), true, functions, HxClassDecl.getFields(main), HxClassDecl.getExtendsPath(main));
						}
					}

					final scannedModuleFields = ParserStageScanHelpers.scanModuleStaticFields(source);
					if (scannedModuleFields.length > 0) {
						if (mainName == null || mainName.length == 0 || mainName == "Unknown") {
							final fallbackName = expectedMainClass != null && expectedMainClass.length > 0 ? expectedMainClass : "Unknown";
							main = new HxClassDecl(fallbackName, HxClassDecl.getHasStaticMain(main), HxClassDecl.getFunctions(main),
								HxClassDecl.getFields(main), HxClassDecl.getExtendsPath(main));
							mainName = fallbackName;
						}
						final existingFieldNames:Map<String, Bool> = new Map();
						for (f in HxClassDecl.getFields(main)) {
							final fieldName = HxFieldDecl.getName(f);
							if (fieldName != null && fieldName.length > 0)
								existingFieldNames.set(fieldName, true);
						}
						final mergedFields = new Array<HxFieldDecl>();
						var addedModuleField = false;
						for (f in scannedModuleFields) {
							final fieldName = HxFieldDecl.getName(f);
							if (fieldName == null || fieldName.length == 0 || existingFieldNames.exists(fieldName))
								continue;
							mergedFields.push(f);
							existingFieldNames.set(fieldName, true);
							addedModuleField = true;
						}
						if (addedModuleField) {
							for (f in HxClassDecl.getFields(main))
								mergedFields.push(f);
							main = new HxClassDecl(HxClassDecl.getName(main), HxClassDecl.getHasStaticMain(main), HxClassDecl.getFunctions(main),
								mergedFields, HxClassDecl.getExtendsPath(main));
							staticPatchApplied = true;
						}
					}

					main = patchClassStaticFlagsFromScan(main);
					final existingClasses = new Array<HxClassDecl>();
					for (c in HxModuleDecl.getClasses(nativeDecl))
						existingClasses.push(patchClassStaticFlagsFromScan(c));
					final existingNames:Map<String, Bool> = new Map();
					for (c in existingClasses) {
						final nm = c == null ? null : HxClassDecl.getName(c);
						if (nm != null && nm.length > 0)
							existingNames.set(nm, true);
					}

					function isMissingAndNotMain(c:HxClassDecl):Bool {
						final nm = c == null ? null : HxClassDecl.getName(c);
						return nm != null && nm.length > 0 && nm != mainName && !existingNames.exists(nm);
					}

					final extras = new Array<HxClassDecl>();
					for (c in scanHelperClasses(source, mainName))
						if (isMissingAndNotMain(c))
							extras.push(c);
					final enumDecls = new Array<HxClassDecl>();
					for (c in enumDeclsAll)
						if (isMissingAndNotMain(c))
							enumDecls.push(c);
					final typedefDecls = new Array<HxClassDecl>();
					for (c in typedefDeclsAll)
						if (isMissingAndNotMain(c))
							typedefDecls.push(c);
					final abstractDecls = new Array<HxClassDecl>();
					for (c in abstractDeclsAll)
						if (isMissingAndNotMain(c))
							abstractDecls.push(c);

					if (extras.length == 0
						&& enumDecls.length == 0
						&& typedefDecls.length == 0
						&& abstractDecls.length == 0
						&& !staticPatchApplied
						&& main == HxModuleDecl.getMainClass(nativeDecl)) {
						return nativeDecl;
					}

					final classes = new Array<HxClassDecl>();
					final seen:Map<String, Bool> = new Map();
					function pushUnique(c:HxClassDecl):Void {
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
					for (c in existingClasses)
						pushUnique(c);
					for (c in extras)
						pushUnique(c);
					for (c in enumDecls)
						pushUnique(c);
					for (c in typedefDecls)
						pushUnique(c);
					for (c in abstractDecls)
						pushUnique(c);

					return new HxModuleDecl(HxModuleDecl.getPackagePath(nativeDecl), HxModuleDecl.getImports(nativeDecl), main, classes,
						HxModuleDecl.getHeaderOnly(nativeDecl), HxModuleDecl.getHasToplevelMain(nativeDecl));
				}

				#if hxhx_stage0_no_hx_parser
				return enrichNativeDecl(parseViaNativeHooks(source, expectedMainClass));
				#else
				final v = Sys.getEnv("HIH_FORCE_HX_PARSER");
				if (v == "1" || v == "true" || v == "yes")
					return enrichNativeDecl(new HxParser(source).parseModule(expectedMainClass));
				function fallbackAfterNativeFailure(nativeError:String):HxModuleDecl {
					final strict = Sys.getEnv("HIH_NATIVE_PARSER_STRICT");
					if (strict == "1" || strict == "true" || strict == "yes")
						throw nativeError;

					// Fallback: the pure-Haxe frontend is slower, but it can unblock bring-up when the
					// native lexer/parser cannot yet handle an upstream-shaped input.
					//
					// This is especially useful when widening the module graph for upstream suites
					// (e.g. enabling heuristic same-package type resolution).
					try {
						return enrichNativeDecl(new HxParser(source).parseModule(expectedMainClass));
					} catch (_:HxParseError) {
						// Prefer the native error (it is usually more specific about the failure mode).
						throw nativeError;
					} catch (_:String) {
						// Prefer the native error (it is usually more specific about the failure mode).
						throw nativeError;
					}
				}
				try {
					return enrichNativeDecl(parseViaNativeHooks(source, expectedMainClass));
				} catch (eNative:String) {
					return fallbackAfterNativeFailure(eNative);
				}
				#end
			})());
			#else
			enrichPureParserDecl(source, expectedMainClass, new HxParser(source).parseModule(expectedMainClass));
			#end
		final path = filePath == null || filePath.length == 0 ? "<memory>" : filePath;
		return new ParsedModule(source, decl, path);
	}

	static function enrichPureParserDecl(source:String, expectedMainClass:Null<String>, parsed:HxModuleDecl):HxModuleDecl {
		final enumDecls = #if hxhx_stage0_no_parser_scan_extract scanModuleLocalHelperEnums(source,
			null) #else ParserStageScanHelpers.scanModuleLocalHelperEnums(source, null) #end;
		if (enumDecls == null || enumDecls.length == 0)
			return parsed;

		var main = HxModuleDecl.getMainClass(parsed);
		var mainName = main == null ? "" : HxClassDecl.getName(main);
		var changed = false;
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
		}

		final classes = new Array<HxClassDecl>();
		final seen:Map<String, Bool> = new Map();
		function pushUnique(c:HxClassDecl):Void {
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
			pushUnique(c);
		for (c in enumDecls) {
			final nm = HxClassDecl.getName(c);
			if (nm != null && nm.length > 0 && !seen.exists(nm)) {
				changed = true;
				pushUnique(c);
			}
		}

		return changed ? new HxModuleDecl(HxModuleDecl.getPackagePath(parsed), HxModuleDecl.getImports(parsed), main, classes,
			HxModuleDecl.getHeaderOnly(parsed), HxModuleDecl.getHasToplevelMain(parsed)) : parsed;
	}

	#if (hih_native_parser && !hxhx_stage0_no_native_parser)
	static function parseViaNativeHooks(source:String, expectedMainClass:Null<String>):HxModuleDecl {
		final encoded = expectedMainClass != null
			&& expectedMainClass.length > 0 ? native.NativeParser.parseModuleDeclWithExpected(source,
				expectedMainClass) : native.NativeParser.parseModuleDecl(source);
		#if hxhx_stage0_no_native_decode_extract
		return decodeNativeProtocol(encoded, source);
		#else
		return ParserStageNativeDecode.decodeNativeProtocol(encoded, source);
		#end
	}

	static inline function scanHelperClasses(source:String, mainClassName:Null<String>):Array<HxClassDecl> {
		#if hxhx_stage0_no_parser_scan_extract
		return scanModuleLocalHelperClasses(source, mainClassName);
		#else
		return ParserStageScanHelpers.scanModuleLocalHelperClasses(source, mainClassName);
		#end
	}

	static inline function scanHelperEnums(source:String, mainTypeName:Null<String>):Array<HxClassDecl> {
		#if hxhx_stage0_no_parser_scan_extract
		return scanModuleLocalHelperEnums(source, mainTypeName);
		#else
		return ParserStageScanHelpers.scanModuleLocalHelperEnums(source, mainTypeName);
		#end
	}

	static inline function scanHelperTypedefs(source:String, mainTypeName:Null<String>):Array<HxClassDecl> {
		#if hxhx_stage0_no_parser_scan_extract
		return scanModuleLocalHelperTypedefs(source, mainTypeName);
		#else
		return ParserStageScanHelpers.scanModuleLocalHelperTypedefs(source, mainTypeName);
		#end
	}

	static inline function scanHelperAbstracts(source:String, mainTypeName:Null<String>):Array<HxClassDecl> {
		#if hxhx_stage0_no_parser_scan_extract
		return scanModuleLocalHelperAbstracts(source, mainTypeName);
		#else
		return ParserStageScanHelpers.scanModuleLocalHelperAbstracts(source, mainTypeName);
		#end
	}

	#if hxhx_stage0_no_parser_scan_extract
	/**
		Best-effort scanner for module-local helper classes.

		Why
		- The native frontend protocol v1 intentionally returns only a single class. This keeps
		  the OCaml seam tiny, but it means we miss helper types declared in the same `.hx` file.
		- Upstream Haxe code (especially `tests/unit` and `tests/runci`) frequently uses:
		  `private class Helper { static var x = ...; static function f(...) ... }`
		- Without providers for these helpers, Stage3 OCaml emission fails with errors like:
		  `Error: Unbound module Helper`.

		What
		- Scan the (already `#if`-filtered) source text for additional top-level `class` declarations.
		- For each helper class, discover:
		  - static `var` / `final` field names (initializer ignored in bring-up)
		  - static `function` names and a best-effort parameter list (arity matters for OCaml)

		How
		- This is not a real parser. It is a small lexer-like token scanner that skips:
		  - whitespace
		  - comments (`//`, `/* ... * /` i.e. "slash-star ... star-slash")
		  - string literals (`"..."`, `'...'`)
		  - regex literals (`~/.../`)
		- It only models enough structure to:
		  - find top-level `class` blocks,
		  - then find class-level `static var/final/function` declarations at brace depth 1.

		Limitations
		- This scanner only discovers module-local `class` declarations.
		- `typedef` / `abstract` declarations are handled by dedicated scanners.
		- Ignores field initializers (emitter stubs use `Obj.magic` placeholders).
	**/
	static function scanModuleLocalHelperClasses(source:String, mainClassName:Null<String>):Array<HxClassDecl> {
		final out = new Array<HxClassDecl>();
		if (source == null || source.length == 0)
			return out;

		final seen:Map<String, Bool> = new Map();
		if (mainClassName != null && mainClassName.length > 0)
			seen.set(mainClassName, true);

		var braceDepth = 0;
		var i = 0;
		while (true) {
			final t = scanNextToken(source, i);
			i = t.nextPos;
			if (t.text.length == 0)
				break;

			if (!t.isIdent) {
				if (t.text == "{")
					braceDepth += 1;
				else if (t.text == "}")
					braceDepth = braceDepth > 0 ? (braceDepth - 1) : 0;
				continue;
			}

			if (braceDepth != 0)
				continue;
			if (t.text != "class" && t.text != "interface")
				continue;

			// class/interface <Name> ...
			var nameTok = scanNextToken(source, i);
			// Skip stray symbols/metadata between `class` and the identifier.
			while (nameTok.text.length > 0 && !nameTok.isIdent)
				nameTok = scanNextToken(source, nameTok.nextPos);
			if (!nameTok.isIdent || nameTok.text.length == 0)
				continue;

			final className = nameTok.text;
			i = nameTok.nextPos;
			final isMain = mainClassName != null && className == mainClassName;
			final alreadySeen = seen.exists(className);
			final shouldRecord = !isMain && !alreadySeen;
			if (!alreadySeen)
				seen.set(className, true);

			final header = scanClassHeader(source, i);
			if (header.bodyStart < 0)
				continue;

			final scanned = scanClassBodyForStatics(source, header.bodyStart);
			i = scanned.nextPos;

			if (shouldRecord)
				out.push(new HxClassDecl(className, false, scanned.functions, scanned.fields, header.extendsPath));
		}

		return out;
	}

	static function scanClassHeader(source:String, start:Int):{bodyStart:Int, nextPos:Int, extendsPath:String} {
		var extendsPath = "";
		var readingExtends = false;
		var genericDepth = 0;
		final extendsParts = new Array<String>();

		var tok = scanNextToken(source, start);
		while (tok.text.length > 0 && tok.text != "{") {
			if (tok.isIdent) {
				if (readingExtends) {
					if (tok.text == "implements") {
						readingExtends = false;
					} else if (genericDepth == 0) {
						extendsParts.push(tok.text);
					}
				} else if (tok.text == "extends") {
					readingExtends = true;
				}
			} else if (readingExtends) {
				switch (tok.text) {
					case ".":
					case "<":
						genericDepth += 1;
					case ">":
						if (genericDepth > 0)
							genericDepth -= 1;
					case ",":
						if (genericDepth == 0)
							readingExtends = false;
					case _:
						if (genericDepth == 0)
							readingExtends = false;
				}
			}
			tok = scanNextToken(source, tok.nextPos);
		}

		if (extendsParts.length > 0)
			extendsPath = extendsParts.join(".");
		return {
			bodyStart: tok.text == "{" ? tok.nextPos : -1,
			nextPos: tok.nextPos,
			extendsPath: extendsPath
		};
	}

	/**
		Best-effort scanner for top-level `enum` declarations.

		Why
		- The native frontend protocol v1 returns only a single `class` surface.
		- Upstream Haxe uses real enums heavily (e.g. `unit.MyEnum` in the unit suite).
		- If an `.hx` file's *main type* is an enum, the native protocol would otherwise
		  decode as `class Unknown`, and Stage3 emission would drop the module entirely,
		  leading to OCaml failures like:
			`Error: Unbound module MyEnum`.

		What
		- Scan the source text for top-level `enum <Name> { ... }` declarations.
		- For each enum constructor:
		  - constructors with 0 args become static fields (`MyEnum.A` -> `MyEnum.a`)
		  - constructors with args become static functions (`MyEnum.C(1,"x")` -> `MyEnum.c 1 "x"`)

		How
		- This is intentionally not a real parser. It reuses the same token scanner as
		  `scanModuleLocalHelperClasses` and only models enough structure to:
		  - find `enum` blocks at brace depth 0,
		  - then count constructor arity at brace depth 1.

		Non-goals (bring-up)
		- Full enum reflection metadata beyond the enum type marker needed by runtime type checks.
		- Enum abstracts (we treat `enum abstract` values as field/function stubs).
	**/
	static function scanModuleLocalHelperEnums(source:String, mainTypeName:Null<String>):Array<HxClassDecl> {
		final out = new Array<HxClassDecl>();
		if (source == null || source.length == 0)
			return out;

		function enumRuntimeValue(enumName:String, ctorName:String, argExprs:Array<HxExpr>):HxExpr {
			return EAnon(["__hx_enum", "__hx_ctor", "__hx_index", "__hx_params"], [EString(enumName), EString(ctorName), EInt(0), EArrayDecl(argExprs)]);
		}

		inline function isUpperStart(name:String):Bool {
			if (name == null || name.length == 0)
				return false;
			final c = name.charCodeAt(0);
			return c >= "A".code && c <= "Z".code;
		}

		final seen:Map<String, Bool> = new Map();
		if (mainTypeName != null && mainTypeName.length > 0)
			seen.set(mainTypeName, true);

		var braceDepth = 0;
		var i = 0;

		while (true) {
			final t = scanNextToken(source, i);
			i = t.nextPos;
			if (t.text.length == 0)
				break;

			if (!t.isIdent) {
				if (t.text == "{")
					braceDepth += 1;
				else if (t.text == "}")
					braceDepth = braceDepth > 0 ? (braceDepth - 1) : 0;
				continue;
			}

			if (braceDepth != 0)
				continue;
			if (t.text != "enum")
				continue;

			// enum [abstract] <Name> ...
			var isEnumAbstract = false;
			var nameTok = scanNextToken(source, i);
			while (nameTok.text.length > 0 && !nameTok.isIdent)
				nameTok = scanNextToken(source, nameTok.nextPos);
			if (!nameTok.isIdent || nameTok.text.length == 0)
				continue;

			if (nameTok.text == "abstract") {
				isEnumAbstract = true;
				nameTok = scanNextToken(source, nameTok.nextPos);
				while (nameTok.text.length > 0 && !nameTok.isIdent)
					nameTok = scanNextToken(source, nameTok.nextPos);
				if (!nameTok.isIdent || nameTok.text.length == 0)
					continue;
			}

			final enumName = nameTok.text;
			i = nameTok.nextPos;

			if (enumName == null || enumName.length == 0)
				continue;
			if (seen.exists(enumName)) {
				// Still need to consume the body so the outer loop doesn't get confused.
				var headerTok = scanNextToken(source, i);
				while (headerTok.text.length > 0 && headerTok.text != "{")
					headerTok = scanNextToken(source, headerTok.nextPos);
				if (headerTok.text != "{")
					continue;
				if (isEnumAbstract) {
					final scanned = scanEnumAbstractBodyForValues(source, headerTok.nextPos);
					i = scanned.nextPos;
				} else {
					final scanned = scanEnumBodyForCtors(source, headerTok.nextPos);
					i = scanned.nextPos;
				}
				continue;
			}
			seen.set(enumName, true);

			// Seek opening `{`.
			var headerTok = scanNextToken(source, i);
			while (headerTok.text.length > 0 && headerTok.text != "{")
				headerTok = scanNextToken(source, headerTok.nextPos);
			if (headerTok.text != "{")
				continue;

			final fields = [new HxFieldDecl("__hx_is_enum", HxVisibility.Public, true, "Bool", EBool(true))];
			final functions = new Array<HxFunctionDecl>();
			if (isEnumAbstract) {
				final scanned = scanEnumAbstractBodyForValues(source, headerTok.nextPos);
				i = scanned.nextPos;
				// `enum abstract` values are declared as `var Name = <expr>;` inside the body.
				//
				// Bring-up: record only the value names, emit them as static fields with a placeholder
				// initializer. This keeps Stage3 emission linking without committing to full semantics.
				for (v in scanned.values) {
					if (v == null || v.length == 0 || !isUpperStart(v))
						continue;
					fields.push(new HxFieldDecl(v, HxVisibility.Public, true, "Dynamic", EInt(0)));
				}
			} else {
				final scanned = scanEnumBodyForCtors(source, headerTok.nextPos);
				i = scanned.nextPos;
				for (ctor in scanned.ctors) {
					if (ctor == null)
						continue;
					final ctorName = ctor.name;
					if (ctorName == null || ctorName.length == 0 || !isUpperStart(ctorName))
						continue;
					final argNames = ctor.args == null ? [] : ctor.args;
					if (argNames.length == 0) {
						fields.push(new HxFieldDecl(ctorName, HxVisibility.Public, true, "Dynamic", enumRuntimeValue(enumName, ctorName, [])));
					} else {
						final args = new Array<HxFunctionArg>();
						final values = new Array<HxExpr>();
						for (a in argNames)
							args.push(new HxFunctionArg(a, "", HxDefaultValue.NoDefault, false, false));
						for (a in argNames)
							values.push(EIdent(a));
						// Constructors conceptually return an enum value; during bring-up we keep the
						// type wide to avoid OCaml type errors in heavily-`Obj.magic` codegen.
						functions.push(new HxFunctionDecl(ctorName, HxVisibility.Public, true, args, "Dynamic",
							[SReturn(enumRuntimeValue(enumName, ctorName, values), HxPos.unknown())], ""));
					}
				}
			}

			out.push(new HxClassDecl(enumName, false, functions, fields));
		}

		return out;
	}

	/**
		Best-effort scanner for top-level `typedef` declarations.

		Why
		- Upstream code often references module-local typedefs via `Module.TypeAlias`.
		- The native frontend protocol v1 only returns one top-level class declaration, so
		  these aliases would otherwise be invisible to Stage3 emission and type indexing.

		What
		- Scans for top-level `typedef <Name> = ...;` declarations.
		- Emits a placeholder type provider (`HxClassDecl`) with no fields/functions.

		How
		- Uses the same lightweight token scanner as other module-local helpers.
		- Tracks brace depth and only records declarations at depth 0.

		Limitations
		- Does not model typedef structure; only the alias name is retained.
	**/
	static function scanModuleLocalHelperTypedefs(source:String, mainTypeName:Null<String>):Array<HxClassDecl> {
		final out = new Array<HxClassDecl>();
		if (source == null || source.length == 0)
			return out;

		final seen:Map<String, Bool> = new Map();
		if (mainTypeName != null && mainTypeName.length > 0)
			seen.set(mainTypeName, true);

		var braceDepth = 0;
		var i = 0;
		while (true) {
			final t = scanNextToken(source, i);
			i = t.nextPos;
			if (t.text.length == 0)
				break;

			if (!t.isIdent) {
				if (t.text == "{")
					braceDepth += 1;
				else if (t.text == "}")
					braceDepth = braceDepth > 0 ? (braceDepth - 1) : 0;
				continue;
			}

			if (braceDepth != 0)
				continue;
			if (t.text != "typedef")
				continue;

			var nameTok = scanNextToken(source, i);
			while (nameTok.text.length > 0 && !nameTok.isIdent)
				nameTok = scanNextToken(source, nameTok.nextPos);
			if (!nameTok.isIdent || nameTok.text.length == 0)
				continue;

			final typeName = nameTok.text;
			i = nameTok.nextPos;
			if (typeName == null || typeName.length == 0)
				continue;
			if (seen.exists(typeName))
				continue;
			seen.set(typeName, true);

			out.push(new HxClassDecl(typeName, false, [], []));
		}

		return out;
	}

	/**
		Best-effort scanner for top-level non-enum `abstract` declarations.

		Why
		- Module-local abstracts are common in upstream-shaped code and can expose static
		  helper functions that must exist as OCaml providers during Stage3 linking.
		- The native frontend protocol v1 does not surface these declarations.

		What
		- Scans for top-level `abstract <Name>(...) { ... }` declarations.
		- Captures static fields/functions from the abstract body using the same
		  class-body scanner used for helper classes.

		How
		- Token-scans the source at brace depth 0.
		- Explicitly skips top-level `enum` / `enum abstract` blocks so `enum abstract`
		  declarations are not double-counted as regular abstracts.

		Limitations
		- Parses only static member signatures needed for bring-up stubs.
		- Ignores non-static members and advanced abstract semantics.
	**/
	static function scanModuleLocalHelperAbstracts(source:String, mainTypeName:Null<String>):Array<HxClassDecl> {
		final out = new Array<HxClassDecl>();
		if (source == null || source.length == 0)
			return out;

		final seen:Map<String, Bool> = new Map();
		if (mainTypeName != null && mainTypeName.length > 0)
			seen.set(mainTypeName, true);

		var braceDepth = 0;
		var i = 0;
		while (true) {
			final t = scanNextToken(source, i);
			i = t.nextPos;
			if (t.text.length == 0)
				break;

			if (!t.isIdent) {
				if (t.text == "{")
					braceDepth += 1;
				else if (t.text == "}")
					braceDepth = braceDepth > 0 ? (braceDepth - 1) : 0;
				continue;
			}

			if (braceDepth != 0)
				continue;
			if (t.text == "enum") {
				// Skip full top-level enum blocks so `enum abstract` isn't treated as a regular abstract.
				var enumNameTok = scanNextToken(source, i);
				while (enumNameTok.text.length > 0 && !enumNameTok.isIdent)
					enumNameTok = scanNextToken(source, enumNameTok.nextPos);
				if (!enumNameTok.isIdent || enumNameTok.text.length == 0)
					continue;

				var isEnumAbstract = false;
				if (enumNameTok.text == "abstract") {
					isEnumAbstract = true;
					enumNameTok = scanNextToken(source, enumNameTok.nextPos);
					while (enumNameTok.text.length > 0 && !enumNameTok.isIdent)
						enumNameTok = scanNextToken(source, enumNameTok.nextPos);
					if (!enumNameTok.isIdent || enumNameTok.text.length == 0)
						continue;
				}
				i = enumNameTok.nextPos;

				var enumHeaderTok = scanNextToken(source, i);
				while (enumHeaderTok.text.length > 0 && enumHeaderTok.text != "{" && enumHeaderTok.text != ";") {
					enumHeaderTok = scanNextToken(source, enumHeaderTok.nextPos);
				}
				if (enumHeaderTok.text == "{") {
					if (isEnumAbstract) {
						final scanned = scanEnumAbstractBodyForValues(source, enumHeaderTok.nextPos);
						i = scanned.nextPos;
					} else {
						final scanned = scanEnumBodyForCtors(source, enumHeaderTok.nextPos);
						i = scanned.nextPos;
					}
				} else if (enumHeaderTok.text.length > 0) {
					i = enumHeaderTok.nextPos;
				}
				continue;
			}
			if (t.text != "abstract")
				continue;

			var nameTok = scanNextToken(source, i);
			while (nameTok.text.length > 0 && !nameTok.isIdent)
				nameTok = scanNextToken(source, nameTok.nextPos);
			if (!nameTok.isIdent || nameTok.text.length == 0)
				continue;

			final abstractName = nameTok.text;
			i = nameTok.nextPos;

			final isMain = mainTypeName != null && abstractName == mainTypeName;
			final alreadySeen = seen.exists(abstractName);
			final shouldRecord = !isMain && !alreadySeen;
			if (!alreadySeen)
				seen.set(abstractName, true);

			var fields = new Array<HxFieldDecl>();
			var functions = new Array<HxFunctionDecl>();

			var headerTok = scanNextToken(source, i);
			while (headerTok.text.length > 0 && headerTok.text != "{" && headerTok.text != ";") {
				headerTok = scanNextToken(source, headerTok.nextPos);
			}
			if (headerTok.text == "{") {
				final scanned = scanClassBodyForStatics(source, headerTok.nextPos);
				i = scanned.nextPos;
				fields = scanned.fields;
				functions = scanned.functions;
			} else if (headerTok.text.length > 0) {
				i = headerTok.nextPos;
			}

			if (shouldRecord)
				out.push(new HxClassDecl(abstractName, false, functions, fields));
		}

		return out;
	}

	static function scanEnumBodyForCtors(source:String, start:Int):{nextPos:Int, ctors:Array<{name:String, args:Array<String>}>} {
		final ctors = new Array<{name:String, args:Array<String>}>();

		var depth = 1; // we start just after `{`
		var i = start;

		inline function isUpperStart(name:String):Bool {
			if (name == null || name.length == 0)
				return false;
			final c = name.charCodeAt(0);
			return c >= "A".code && c <= "Z".code;
		}

		while (true) {
			final t = scanNextToken(source, i);
			i = t.nextPos;
			if (t.text.length == 0)
				break;

			if (!t.isIdent) {
				switch (t.text) {
					case "{":
						depth += 1;
					case "}":
						depth -= 1;
						if (depth <= 0)
							break;
					case _:
				}
				continue;
			}

			if (depth != 1)
				continue;
			if (!isUpperStart(t.text))
				continue;

			final ctorName = t.text;
			final ctorArgs = new Array<String>();

			// Optional `(a:T, b:U)` parameter list.
			final nt = scanNextToken(source, i);
			if (nt.text == "(") {
				i = nt.nextPos;
				var parenDepth = 1;
				var bracketDepth = 0;
				var braceDepthInArgs = 0;
				var angleDepth = 0;

				var expectArg = true;
				var pendingOptional = false;
				var pendingRest = false;
				var argIndex = 0;

				while (true) {
					final at = scanNextToken(source, i);
					i = at.nextPos;
					if (at.text.length == 0)
						break;

					if (!at.isIdent) {
						switch (at.text) {
							case "(":
								parenDepth += 1;
							case ")":
								parenDepth -= 1;
								if (parenDepth <= 0)
									break;
							case "[":
								bracketDepth += 1;
							case "]":
								if (bracketDepth > 0)
									bracketDepth -= 1;
							case "{":
								braceDepthInArgs += 1;
								depth += 1;
							case "}":
								if (braceDepthInArgs > 0)
									braceDepthInArgs -= 1;
								depth -= 1;
								if (depth <= 0)
									break;
							case "<":
								angleDepth += 1;
							case ">":
								if (angleDepth > 0)
									angleDepth -= 1;
							case ",":
								if (parenDepth == 1 && bracketDepth == 0 && braceDepthInArgs == 0 && angleDepth == 0) {
									expectArg = true;
									pendingOptional = false;
									pendingRest = false;
								}
							case "?":
								if (expectArg && parenDepth == 1 && bracketDepth == 0 && braceDepthInArgs == 0 && angleDepth == 0)
									pendingOptional = true;
							case "...":
								if (expectArg && parenDepth == 1 && bracketDepth == 0 && braceDepthInArgs == 0 && angleDepth == 0)
									pendingRest = true;
							case _:
						}
						continue;
					}

					if (!expectArg)
						continue;
					if (parenDepth != 1 || bracketDepth != 0 || braceDepthInArgs != 0 || angleDepth != 0)
						continue;

					final nm = at.text;
					final argName = (nm == null || nm.length == 0) ? ("arg" + argIndex) : nm;
					ctorArgs.push(argName);
					argIndex += 1;
					expectArg = false;
					pendingOptional = false;
					pendingRest = false;
				}
			}

			ctors.push({name: ctorName, args: ctorArgs});

			// Consume tokens until the terminating `;` so we don't interpret type names
			// as additional constructors.
			while (true) {
				final tt = scanNextToken(source, i);
				i = tt.nextPos;
				if (tt.text.length == 0)
					break;
				if (!tt.isIdent) {
					if (tt.text == "{")
						depth += 1;
					else if (tt.text == "}") {
						depth -= 1;
						if (depth <= 0)
							break;
					} else if (depth == 1 && (tt.text == ";" || tt.text == ",")) {
						break;
					}
				}
			}
		}

		return {nextPos: i, ctors: ctors};
	}

	static function scanEnumAbstractBodyForValues(source:String, start:Int):{nextPos:Int, values:Array<String>} {
		final values = new Array<String>();

		var depth = 1; // we start just after `{`
		var i = start;

		inline function isUpperStart(name:String):Bool {
			if (name == null || name.length == 0)
				return false;
			final c = name.charCodeAt(0);
			return c >= "A".code && c <= "Z".code;
		}

		while (true) {
			final t = scanNextToken(source, i);
			i = t.nextPos;
			if (t.text.length == 0)
				break;

			if (!t.isIdent) {
				switch (t.text) {
					case "{":
						depth += 1;
					case "}":
						depth -= 1;
						if (depth <= 0)
							break;
					case _:
				}
				continue;
			}

			if (depth != 1)
				continue;
			if (t.text != "var")
				continue;

			// var <Name> ...
			var nameTok = scanNextToken(source, i);
			while (nameTok.text.length > 0 && !nameTok.isIdent)
				nameTok = scanNextToken(source, nameTok.nextPos);
			if (!nameTok.isIdent || nameTok.text.length == 0)
				continue;
			final name = nameTok.text;
			i = nameTok.nextPos;
			if (isUpperStart(name))
				values.push(name);
		}

		return {nextPos: i, values: values};
	}

	static function scanClassBodyForStatics(source:String, start:Int):{nextPos:Int, fields:Array<HxFieldDecl>, functions:Array<HxFunctionDecl>} {
		final fields = new Array<HxFieldDecl>();
		final functions = new Array<HxFunctionDecl>();

		var depth = 1; // we start just after `{`
		var i = start;

		var sawStatic = false;
		var sawMacro = false;
		var vis:HxVisibility = HxVisibility.Public;

		while (true) {
			final t = scanNextToken(source, i);
			i = t.nextPos;
			if (t.text.length == 0)
				break;

			if (!t.isIdent) {
				switch (t.text) {
					case "{":
						depth += 1;
					case "}":
						depth -= 1;
						if (depth <= 0)
							break;
					case ";":
						if (depth == 1) {
							// Declarations are terminated; reset modifiers.
							sawStatic = false;
							sawMacro = false;
							vis = HxVisibility.Public;
						}
					case _:
				}
				continue;
			}

			if (depth != 1)
				continue;

			switch (t.text) {
				case "public":
					vis = HxVisibility.Public;
				case "private":
					vis = HxVisibility.Private;
				case "static":
					sawStatic = true;
				case "macro":
					sawMacro = true;
				case "inline" | "extern" | "override":
					// Keep scanning; these can appear between `static` and the declaration keyword.
				case "var" | "final":
					// `final` can introduce either:
					// - a field declaration (`final X = ...;` / `static final X = ...;`), or
					// - a function modifier (`final function f() ...` / `final static function f() ...`).
					//
					// Disambiguate with a small lookahead so we don't accidentally treat
					// `final static function` as a field named `static`.
					if (t.text == "final") {
						var isFieldDecl = false;
						var j = i;
						while (true) {
							final nt = scanNextToken(source, j);
							if (nt.text.length == 0) {
								isFieldDecl = false;
								break;
							}
							j = nt.nextPos;
							if (!nt.isIdent)
								continue;
							switch (nt.text) {
								case "public" | "private" | "static" | "inline" | "macro" | "extern" | "override" | "final":
									continue;
								case "function" | "var":
									isFieldDecl = false;
								case _:
									isFieldDecl = true;
							}
							break;
						}
						if (!isFieldDecl)
							continue;
					}
					// Best-effort: collect static vars/constants by name, ignore initializer and type hint.
					//
					// We still need to consume tokens until the terminating `;` so the outer loop doesn't
					// interpret type/initializer identifiers as class-level declarations.
					final wantStatic = sawStatic;
					final fieldVis = vis;
					var wantName = true;
					var parenDepth = 0;
					var bracketDepth = 0;
					var angleDepth = 0;
					var fieldDone = false;

					while (!fieldDone) {
						final ft = scanNextToken(source, i);
						i = ft.nextPos;
						if (ft.text.length == 0)
							break;

						if (!ft.isIdent) {
							switch (ft.text) {
								case "{":
									depth += 1;
								case "}":
									depth -= 1;
									if (depth <= 0) fieldDone = true;
								case "(":
									if (depth == 1) parenDepth += 1;
								case ")":
									if (depth == 1 && parenDepth > 0) parenDepth -= 1;
								case "[":
									if (depth == 1) bracketDepth += 1;
								case "]":
									if (depth == 1 && bracketDepth > 0) bracketDepth -= 1;
								case "<":
									if (depth == 1) angleDepth += 1;
								case ">":
									if (depth == 1 && angleDepth > 0) angleDepth -= 1;
								case ",":
									if (depth == 1 && parenDepth == 0 && bracketDepth == 0 && angleDepth == 0) wantName = true;
								case ";":
									if (depth == 1 && parenDepth == 0 && bracketDepth == 0 && angleDepth == 0) fieldDone = true;
								case _:
							}
							continue;
						}

						if (depth != 1)
							continue;
						if (!wantName)
							continue;

						final name = ft.text;
						wantName = false;
						if (name == null || name.length == 0)
							continue;
						final typeHint = scanFieldTypeHint(source, ft.nextPos);
						final initText = scanFieldInitializer(source, ft.nextPos);
						fields.push(new HxFieldDecl(name, fieldVis, wantStatic, typeHint, parseSimpleInitExpr(initText), null, null, null, t.text == "final",
							"", "", initText));
					}

					sawStatic = false;
					sawMacro = false;
					vis = HxVisibility.Public;
					if (depth <= 0)
						break;
				case "function":
					// Best-effort: collect function name + arity + static flag from the scanned class body.
					//
					// Why include non-static functions:
					// - Native parser bring-up can mislabel some method static flags in std modules.
					// - `enrichNativeDecl` uses this scanned surface to reconcile static metadata.
					// - Capturing only static functions hides useful "this is non-static" evidence and
					//   can leave call-site receiver injection broken (partial applications at OCaml link-time).
					final wantStaticFn = sawStatic;
					final fnVis = vis;

					var nameTok = scanNextToken(source, i);
					while (nameTok.text.length > 0 && !nameTok.isIdent)
						nameTok = scanNextToken(source, nameTok.nextPos);
					final fnName = (nameTok.isIdent && nameTok.text.length > 0) ? nameTok.text : "";
					i = nameTok.nextPos;

					// Seek `(` for the parameter list (skip generics / return types).
					var sigTok = scanNextToken(source, i);
					while (sigTok.text.length > 0 && sigTok.text != "(" && sigTok.text != "{" && sigTok.text != ";" && sigTok.text != "=") {
						i = sigTok.nextPos;
						sigTok = scanNextToken(source, i);
					}

					var args = new Array<HxFunctionArg>();
					if (sigTok.text == "(") {
						i = sigTok.nextPos;
						var parenDepth = 1;
						var bracketDepth = 0;
						var braceDepthInArgs = 0;
						var angleDepth = 0;

						var expectArg = true;
						var pendingOptional = false;
						var pendingRest = false;
						var argIndex = 0;

						while (true) {
							final at = scanNextToken(source, i);
							i = at.nextPos;
							if (at.text.length == 0)
								break;

							if (!at.isIdent) {
								switch (at.text) {
									case "(":
										parenDepth += 1;
									case ")":
										parenDepth -= 1;
										if (parenDepth <= 0) break;
									case "[":
										bracketDepth += 1;
									case "]":
										if (bracketDepth > 0) bracketDepth -= 1;
									case "{":
										braceDepthInArgs += 1;
										depth += 1;
									case "}":
										if (braceDepthInArgs > 0)
											braceDepthInArgs -= 1;
										depth -= 1;
										if (depth <= 0) break;
									case "<":
										angleDepth += 1;
									case ">":
										if (angleDepth > 0) angleDepth -= 1;
									case ",":
										if (parenDepth == 1 && bracketDepth == 0 && braceDepthInArgs == 0 && angleDepth == 0) {
											expectArg = true;
											pendingOptional = false;
											pendingRest = false;
										}
									case "?":
										if (expectArg && parenDepth == 1 && bracketDepth == 0 && braceDepthInArgs == 0 && angleDepth == 0)
											pendingOptional = true;
									case "...":
										if (expectArg && parenDepth == 1 && bracketDepth == 0 && braceDepthInArgs == 0 && angleDepth == 0) pendingRest = true;
									case _:
								}
								continue;
							}

							if (!expectArg)
								continue;
							if (parenDepth != 1 || bracketDepth != 0 || braceDepthInArgs != 0 || angleDepth != 0)
								continue;

							final nm = at.text;
							final argName = (nm == null || nm.length == 0) ? ("arg" + argIndex) : nm;
							args.push(new HxFunctionArg(argName, "", HxDefaultValue.NoDefault, pendingOptional, pendingRest));
							argIndex += 1;
							expectArg = false;
							pendingOptional = false;
							pendingRest = false;
						}
					}

					final bodyCapture = scanFunctionBody(source, i, true);
					final keepBody = fnName == "new" || !wantStaticFn || scannedStaticBodyIsSafe(fnName, bodyCapture.body);
					final body = keepBody ? bodyCapture.body : [];
					final bodyText = keepBody ? bodyCapture.bodyText : "";
					if (bodyCapture.nextPos > i)
						i = bodyCapture.nextPos;

					if (fnName.length > 0) {
						final metadata = sawMacro ? ["macro"] : null;
						functions.push(new HxFunctionDecl(fnName, fnVis, wantStaticFn, args, "", body, "", metadata, null, null, bodyText));
					}

					sawStatic = false;
					sawMacro = false;
					vis = HxVisibility.Public;
				case _:
			}
		}

		return {nextPos: i, fields: fields, functions: functions};
	}

	static function scanFieldTypeHint(source:String, start:Int):String {
		var i = start;
		var colonAt = -1;
		var parenDepth = 0;
		var bracketDepth = 0;
		var angleDepth = 0;
		while (i < source.length) {
			final c = source.charCodeAt(i);
			if (c == "\"".code || c == "'".code) {
				i = skipQuotedSource(source, i);
				continue;
			}
			switch (c) {
				case ":".code:
					if (parenDepth == 0 && bracketDepth == 0 && angleDepth == 0 && colonAt < 0)
						colonAt = i;
				case "(".code:
					parenDepth += 1;
				case ")".code:
					if (parenDepth > 0)
						parenDepth -= 1;
				case "[".code:
					bracketDepth += 1;
				case "]".code:
					if (bracketDepth > 0)
						bracketDepth -= 1;
				case "<".code:
					angleDepth += 1;
				case ">".code:
					if (angleDepth > 0)
						angleDepth -= 1;
				case "=".code | ",".code | ";".code | "}".code:
					if (parenDepth == 0 && bracketDepth == 0 && angleDepth == 0)
						return colonAt < 0 ? "" : StringTools.trim(source.substring(colonAt + 1, i));
				case _:
			}
			i += 1;
		}
		return "";
	}

	static function scanFieldInitializer(source:String, start:Int):String {
		var i = start;
		var parenDepth = 0;
		var bracketDepth = 0;
		var braceDepth = 0;
		var equalsAt = -1;
		while (i < source.length) {
			final c = source.charCodeAt(i);
			if (c == "\"".code || c == "'".code) {
				i = skipQuotedSource(source, i);
				continue;
			}
			switch (c) {
				case "(".code:
					parenDepth += 1;
				case ")".code:
					if (parenDepth > 0)
						parenDepth -= 1;
				case "[".code:
					bracketDepth += 1;
				case "]".code:
					if (bracketDepth > 0)
						bracketDepth -= 1;
				case "{".code:
					braceDepth += 1;
				case "}".code:
					if (braceDepth == 0)
						return "";
					braceDepth -= 1;
				case "=".code:
					if (parenDepth == 0 && bracketDepth == 0 && braceDepth == 0 && equalsAt < 0)
						equalsAt = i;
				case ",".code | ";".code:
					if (parenDepth == 0 && bracketDepth == 0 && braceDepth == 0) {
						return equalsAt < 0 ? "" : StringTools.trim(source.substring(equalsAt + 1, i));
					}
				case _:
			}
			i += 1;
		}
		return "";
	}

	static function skipQuotedSource(source:String, start:Int):Int {
		final quote = source.charCodeAt(start);
		var i = start + 1;
		while (i < source.length) {
			final c = source.charCodeAt(i);
			i += 1;
			if (c == "\\".code) {
				if (i < source.length)
					i += 1;
				continue;
			}
			if (c == quote)
				break;
		}
		return i;
	}

	static function parseSimpleInitExpr(raw:String):Null<HxExpr> {
		final text = raw == null ? "" : StringTools.trim(raw);
		if (text.length == 0)
			return null;
		if (StringTools.startsWith(text, "untyped ") || StringTools.startsWith(text, "if "))
			return null;
		if (text == "null")
			return ENull;
		if (text == "true")
			return EBool(true);
		if (text == "false")
			return EBool(false);
		if (text.length >= 2 && StringTools.startsWith(text, "\"") && StringTools.endsWith(text, "\""))
			return EString(text.substr(1, text.length - 2));
		final intRe = ~/^-?[0-9]+$/;
		if (intRe.match(text))
			return EInt(Std.parseInt(text));
		try {
			final parsed = HxParser.parseExprText(text);
			return hasUnsupportedExpr(parsed) ? null : parsed;
		} catch (_:HxParseError) {} catch (_:String) {}
		return null;
	}

	static function scanFunctionBody(source:String, start:Int, capture:Bool = true):{body:Array<HxStmt>, bodyText:String, nextPos:Int} {
		var i = start;
		var bodyStart = -1;
		var tok = scanNextToken(source, i);
		while (tok.text.length > 0 && tok.text != "{" && tok.text != ";") {
			if (tok.isIdent && tok.text == "return" && bodyStart < 0) {
				bodyStart = tok.nextPos - tok.text.length;
			}
			i = tok.nextPos;
			tok = scanNextToken(source, i);
		}
		if (tok.text == ";") {
			if (!capture)
				return {body: [], bodyText: "", nextPos: tok.nextPos};
			final rawStart = bodyStart >= 0 ? bodyStart : start;
			final rawExpr = source.substring(rawStart, tok.nextPos - 1);
			final leading = leadingWhitespaceLength(rawExpr);
			final exprText = StringTools.trim(rawExpr);
			if (exprText.length == 0)
				return {body: [], bodyText: "", nextPos: tok.nextPos};
			final bodyText = exprText + ";";
			var body = new Array<HxStmt>();
			try {
				body = HxParser.parseFunctionBodyTextAt(bodyText, source, rawStart + leading);
				if (hasUnsupportedStmtList(body))
					body = [];
			} catch (_:HxParseError) {
				body = [];
			} catch (_:String) {
				body = [];
			}
			return {body: body, bodyText: body.length == 0 ? "" : bodyText, nextPos: tok.nextPos};
		}
		if (tok.text != "{")
			return {body: [], bodyText: "", nextPos: tok.nextPos};

		final block = scanBalancedBlock(source, tok.nextPos);
		if (block.nextPos <= tok.nextPos)
			return {body: [], bodyText: "", nextPos: tok.nextPos};
		if (!capture)
			return {body: [], bodyText: "", nextPos: block.nextPos};

		var body = new Array<HxStmt>();
		if (block.bodyText.length > 0) {
			try {
				body = HxParser.parseFunctionBodyTextAt(block.bodyText, source, tok.nextPos);
				if (hasUnsupportedStmtList(body))
					body = [];
			} catch (_:HxParseError) {
				body = [];
			} catch (_:String) {
				body = [];
			}
		}
		return {body: body, bodyText: body.length == 0 ? "" : block.bodyText, nextPos: block.nextPos};
	}

	static function leadingWhitespaceLength(text:String):Int {
		if (text == null || text.length == 0)
			return 0;
		var i = 0;
		while (i < text.length) {
			final c = text.charCodeAt(i);
			if (c != " ".code && c != "\t".code && c != "\n".code && c != "\r".code)
				break;
			i += 1;
		}
		return i;
	}

	public static function hasUnsupportedStmtList(stmts:Array<HxStmt>):Bool {
		for (stmt in stmts)
			if (hasUnsupportedStmt(stmt))
				return true;
		return false;
	}

	static function scannedStaticBodyIsSafe(fnName:String, stmts:Array<HxStmt>):Bool {
		if (stmts == null || stmts.length == 0)
			return false;
		if (StringTools.startsWith(fnName, "get_") && stmts.length == 1) {
			return switch (stmts[0]) {
				case SReturn(expr, _):
					!hasUnsupportedExpr(expr);
				case _:
					false;
			};
		}
		if (StringTools.startsWith(fnName, "set_") && stmts.length == 2) {
			return switch [stmts[0], stmts[1]] {
				case [SExpr(EBinop("=", EIdent(_), rhs), _), SReturn(ret, _)]: !hasUnsupportedExpr(rhs) && !hasUnsupportedExpr(ret);
				case _:
					false;
			};
		}
		return switch (stmts[0]) {
			case SReturn(ECall(EField(EIdent(_), _), callArgs), _): callArgs != null && callArgs.length <= 2;
			case SReturn(ENew(_, _), _):
				true;
			case _:
				false;
		};
	}

	static function hasUnsupportedStmt(stmt:HxStmt):Bool {
		return switch (stmt) {
			case SBlock(stmts, _):
				hasUnsupportedStmtList(stmts);
			case SVar(_, _, init, _):
				hasUnsupportedExpr(init);
			case SIf(cond, thenBranch, elseBranch, _): hasUnsupportedExpr(cond) || hasUnsupportedStmt(thenBranch) || (elseBranch != null
					&& hasUnsupportedStmt(elseBranch));
			case SWhile(cond, body, _) | SDoWhile(body, cond, _): hasUnsupportedExpr(cond) || hasUnsupportedStmt(body);
			case SForIn(_, iterable, body, _) | SForKeyValue(_, _, iterable, body, _): hasUnsupportedExpr(iterable) || hasUnsupportedStmt(body);
			case STry(tryBody, catches, _):
				if (hasUnsupportedStmt(tryBody)) true; else {
					var found = false;
					for (c in catches)
						if (hasUnsupportedStmt(c.body))
							found = true;
					found;
				}
			case SSwitch(scrutinee, _, bodies, _):
				if (hasUnsupportedExpr(scrutinee)) true; else {
					var found = false;
					for (body in bodies)
						if (hasUnsupportedStmt(body))
							found = true;
					found;
				}
			case SReturn(expr, _) | SThrow(expr, _) | SExpr(expr, _):
				hasUnsupportedExpr(expr);
			case SReturnVoid(_) | SBreak(_) | SContinue(_):
				false;
		}
	}

	static function hasUnsupportedExpr(expr:Null<HxExpr>):Bool {
		if (expr == null)
			return false;
		return switch (expr) {
			case EUnsupported(_):
				true;
			case EField(obj, _), EUnop(_, obj), ECast(obj, _), EUntyped(obj):
				hasUnsupportedExpr(obj);
			case ECall(obj, args):
				if (hasUnsupportedExpr(obj)) true; else {
					var found = false;
					for (arg in args)
						if (hasUnsupportedExpr(arg))
							found = true;
					found;
				}
			case EBinop(_, left, right), EArrayAccess(left, right), ERange(left, right): hasUnsupportedExpr(left) || hasUnsupportedExpr(right);
			case ETernary(cond, thenExpr, elseExpr): hasUnsupportedExpr(cond) || hasUnsupportedExpr(thenExpr) || hasUnsupportedExpr(elseExpr);
			case EAnon(_, values) | EArrayDecl(values):
				for (value in values)
					if (hasUnsupportedExpr(value))
						return true;
				false;
			case ELambda(_, body):
				hasUnsupportedExpr(body);
			case EMacroExpr(inner, _):
				hasUnsupportedExpr(inner);
			case ESwitch(scrutinee, _, exprs):
				if (hasUnsupportedExpr(scrutinee)) true; else {
					var found = false;
					for (value in exprs)
						if (hasUnsupportedExpr(value))
							found = true;
					found;
				}
			case ENew(_, args):
				for (arg in args)
					if (hasUnsupportedExpr(arg))
						return true;
				false;
			case EArrayComprehension(_, iterable, guardExpr, yieldExpr): hasUnsupportedExpr(iterable) || (guardExpr != null && hasUnsupportedExpr(guardExpr)) || hasUnsupportedExpr(yieldExpr);
			case ESwitchRaw(_) | ETryCatchRaw(_):
				true;
			case _:
				false;
		}
	}

	static function scanBalancedBlock(source:String, start:Int):{bodyText:String, nextPos:Int} {
		final bodyStart = start;
		var depth = 1;
		var i = start;
		while (true) {
			final tok = scanNextToken(source, i);
			if (tok.text.length == 0)
				return {bodyText: "", nextPos: i};
			i = tok.nextPos;
			if (tok.text == "{") {
				depth += 1;
			} else if (tok.text == "}") {
				depth -= 1;
				if (depth <= 0)
					return {bodyText: source.substring(bodyStart, tok.nextPos - 1), nextPos: tok.nextPos};
			}
		}
		return {bodyText: "", nextPos: i};
	}

	static function scanNextToken(source:String, start:Int):{isIdent:Bool, text:String, nextPos:Int} {
		final len = source.length;
		var i = start;

		inline function isWs(c:Int):Bool
			return c == 9 || c == 10 || c == 13 || c == 32;
		inline function isIdentStart(c:Int):Bool
			return (c >= "A".code && c <= "Z".code) || (c >= "a".code && c <= "z".code) || c == "_".code;
		inline function isIdentPart(c:Int):Bool
			return isIdentStart(c) || (c >= "0".code && c <= "9".code);

		while (i < len) {
			final c = source.charCodeAt(i);
			if (isWs(c)) {
				i += 1;
				continue;
			}

			// Line comment
			if (c == "/".code && i + 1 < len && source.charCodeAt(i + 1) == "/".code) {
				i += 2;
				while (i < len) {
					final cc = source.charCodeAt(i);
					i += 1;
					if (cc == "\n".code)
						break;
				}
				continue;
			}

			// Block comment
			if (c == "/".code && i + 1 < len && source.charCodeAt(i + 1) == "*".code) {
				i += 2;
				while (i + 1 < len) {
					if (source.charCodeAt(i) == "*".code && source.charCodeAt(i + 1) == "/".code) {
						i += 2;
						break;
					}
					i += 1;
				}
				continue;
			}

			// String literal ("..." or '...')
			if (c == "\"".code || c == "'".code) {
				final quote = c;
				i += 1;
				while (i < len) {
					final cc = source.charCodeAt(i);
					i += 1;
					if (cc == "\\".code) {
						// skip escaped char
						if (i < len)
							i += 1;
						continue;
					}
					if (cc == quote)
						break;
				}
				continue;
			}

			// Regex literal: ~/.../
			if (c == "~".code && i + 1 < len && source.charCodeAt(i + 1) == "/".code) {
				i += 2;
				while (i < len) {
					final cc = source.charCodeAt(i);
					i += 1;
					if (cc == "\\".code) {
						if (i < len)
							i += 1;
						continue;
					}
					if (cc == "/".code)
						break;
				}
				// flags
				while (i < len && isIdentPart(source.charCodeAt(i)))
					i += 1;
				continue;
			}

			if (isIdentStart(c)) {
				final startIdent = i;
				i += 1;
				while (i < len && isIdentPart(source.charCodeAt(i)))
					i += 1;
				return {isIdent: true, text: source.substr(startIdent, i - startIdent), nextPos: i};
			}

			// Ellipsis
			if (c == ".".code && i + 2 < len && source.charCodeAt(i + 1) == ".".code && source.charCodeAt(i + 2) == ".".code) {
				return {isIdent: false, text: "...", nextPos: i + 3};
			}

			// Single-char symbol
			return {isIdent: false, text: String.fromCharCode(c), nextPos: i + 1};
		}

		return {isIdent: false, text: "", nextPos: len};
	}
	#end

	#if hxhx_stage0_no_native_decode_extract
	/**
		Decode the native frontend protocol emitted by the OCaml lexer/parser stubs.

		Why:
		- This is our “bootstrap seam” for Haxe-in-Haxe: we want to keep the
		  frontend native initially, but keep the rest of the compiler in Haxe.

		What:
		- Produces a `HxModuleDecl` for Stage 2 from the protocol output.

		How:
		- The protocol is intentionally simple and line-based so it can be produced
		  from OCaml without dependencies and decoded from Haxe without a JSON
		  runtime.
		- See `docs/02-user-guide/HXHX_NATIVE_FRONTEND_PROTOCOL.md:1` for the exact
		  wire format and versioning rules.
	**/
	static function decodeNativeProtocol(encoded:String, ?source:String):HxModuleDecl {
		final lines = encoded.split("\n").filter(l -> l.length > 0);
		if (lines.length == 0) {
			throw "Native frontend: missing/invalid protocol header";
		}
		final header = lines[0];
		if (header != "hxhx_frontend_v=1" && header != "hxhx_frontend_v=2") {
			throw "Native frontend: missing/invalid protocol header";
		}

		var packagePath = "";
		final imports = new Array<String>();
		var className = "Unknown";
		var headerOnly = false;
		var hasToplevelMain = false;
		var hasStaticMain = false;
		final methodPayloads = new Array<String>();
		final fieldPayloads = new Array<String>();
		final staticFinalPayloads = new Array<String>();
		final methodBodies:Map<String, String> = [];
		final methodBodyStarts:Map<String, Int> = [];
		final functions = new Array<HxFunctionDecl>();
		final fields = new Array<HxFieldDecl>();
		var sawOk = false;

		for (i in 1...lines.length) {
			final line = lines[i];
			if (line == "ok") {
				sawOk = true;
				continue;
			}

			if (StringTools.startsWith(line, "err ")) {
				throwFromErrLine(line);
				return null;
			}

			if (StringTools.startsWith(line, "ast ")) {
				if (StringTools.startsWith(line, "ast static_main ")) {
					hasStaticMain = line.substr("ast static_main ".length) == "1";
					continue;
				}

				final rest = line.substr("ast ".length);
				final firstSpace = rest.indexOf(" ");
				if (firstSpace <= 0)
					continue;
				final key = rest.substr(0, firstSpace);
				final payload = decodeLenPayload(rest.substr(firstSpace + 1));
				switch (key) {
					case "package":
						packagePath = payload;
					case "imports":
						if (payload.length > 0) {
							for (p in payload.split("|"))
								if (p.length > 0)
									imports.push(p);
						}
					case "class":
						className = payload;
					case "header_only":
						headerOnly = payload == "1";
					case "toplevel_main":
						hasToplevelMain = payload == "1";
					case "method":
						methodPayloads.push(payload);
					case "field":
						fieldPayloads.push(payload);
					case "static_final":
						staticFinalPayloads.push(payload);
					case "method_body":
						// Payload format: "<methodName>\n<bodySource>"
						final nl = payload.indexOf("\n");
						if (nl > 0) {
							final name = payload.substr(0, nl);
							if (!methodBodies.exists(name)) {
								final bodySource = payload.substr(nl + 1);
								methodBodies.set(name, bodySource);
								if (source != null && source.length > 0 && bodySource.length > 0) {
									final fallbackStart = findFunctionBodyStart(source, name);
									final bodyStart = source.indexOf(bodySource);
									if (fallbackStart >= 0)
										methodBodyStarts.set(name, fallbackStart);
									else if (bodyStart >= 0)
										methodBodyStarts.set(name, bodyStart);
								}
							}
						}
					case _:
				}
				continue;
			}
		}

		if (!sawOk) {
			throw "Native frontend: missing terminal 'ok'";
		}

		for (mp in methodPayloads) {
			final name = {
				final parts = mp.split("|");
				parts.length == 0 ? "" : parts[0];
			};
			functions.push(decodeMethodPayload(mp, methodBodies.exists(name) ? methodBodies.get(name) : null,
				methodBodyStarts.exists(name) ? methodBodyStarts.get(name) : -1, source));
		}

		final seenFields:Map<String, Bool> = [];
		inline function pushFieldMaybe(f:Null<HxFieldDecl>) {
			if (f == null)
				return;
			final key = HxFieldDecl.getName(f) + "|" + (HxFieldDecl.getIsStatic(f) ? "1" : "0");
			if (seenFields.exists(key))
				return;
			seenFields.set(key, true);
			fields.push(f);
		}

		for (fp in staticFinalPayloads) {
			pushFieldMaybe(decodeStaticFinalPayload(fp));
		}

		for (fp in fieldPayloads) {
			pushFieldMaybe(decodeFieldPayload(fp));
		}

		final cls = new HxClassDecl(className, hasStaticMain, functions, fields);
		return new HxModuleDecl(packagePath, imports, cls, [cls], headerOnly, hasToplevelMain);
	}

	static function findMatchingParen(source:String, open:Int):Int {
		var depth = 0;
		var inString = false;
		var quote = "";
		var i = open;
		while (i < source.length) {
			final ch = source.charAt(i);
			if (inString) {
				if (ch == "\\") {
					i += 2;
					continue;
				}
				if (ch == quote)
					inString = false;
				i += 1;
				continue;
			}
			if (ch == "\"" || ch == "'") {
				inString = true;
				quote = ch;
				i += 1;
				continue;
			}
			if (ch == "(")
				depth += 1;
			else if (ch == ")") {
				depth -= 1;
				if (depth == 0)
					return i;
			}
			i += 1;
		}
		return -1;
	}

	static function splitTopLevelComma(text:String):Array<String> {
		final out = new Array<String>();
		var start = 0;
		var parenDepth = 0;
		var bracketDepth = 0;
		var braceDepth = 0;
		var angleDepth = 0;
		var inString = false;
		var quote = "";
		var i = 0;
		while (i < text.length) {
			final ch = text.charAt(i);
			if (inString) {
				if (ch == "\\") {
					i += 2;
					continue;
				}
				if (ch == quote)
					inString = false;
				i += 1;
				continue;
			}
			if (ch == "\"" || ch == "'") {
				inString = true;
				quote = ch;
			} else {
				switch (ch) {
					case "(":
						parenDepth += 1;
					case ")":
						if (parenDepth > 0)
							parenDepth -= 1;
					case "[":
						bracketDepth += 1;
					case "]":
						if (bracketDepth > 0)
							bracketDepth -= 1;
					case "{":
						braceDepth += 1;
					case "}":
						if (braceDepth > 0)
							braceDepth -= 1;
					case "<":
						angleDepth += 1;
					case ">":
						if (angleDepth > 0)
							angleDepth -= 1;
					case ",":
						if (parenDepth == 0 && bracketDepth == 0 && braceDepth == 0 && angleDepth == 0) {
							out.push(text.substr(start, i - start));
							start = i + 1;
						}
					case _:
				}
			}
			i += 1;
		}
		out.push(text.substr(start));
		return out;
	}

	static function findTopLevelEquals(text:String):Int {
		var parenDepth = 0;
		var bracketDepth = 0;
		var braceDepth = 0;
		var angleDepth = 0;
		var inString = false;
		var quote = "";
		var i = 0;
		while (i < text.length) {
			final ch = text.charAt(i);
			if (inString) {
				if (ch == "\\") {
					i += 2;
					continue;
				}
				if (ch == quote)
					inString = false;
				i += 1;
				continue;
			}
			if (ch == "\"" || ch == "'") {
				inString = true;
				quote = ch;
			} else {
				switch (ch) {
					case "(":
						parenDepth += 1;
					case ")":
						if (parenDepth > 0)
							parenDepth -= 1;
					case "[":
						bracketDepth += 1;
					case "]":
						if (bracketDepth > 0)
							bracketDepth -= 1;
					case "{":
						braceDepth += 1;
					case "}":
						if (braceDepth > 0)
							braceDepth -= 1;
					case "<":
						angleDepth += 1;
					case ">":
						if (angleDepth > 0)
							angleDepth -= 1;
					case "=":
						if (parenDepth == 0 && bracketDepth == 0 && braceDepth == 0 && angleDepth == 0)
							return i;
					case _:
				}
			}
			i += 1;
		}
		return -1;
	}

	static function sourceSignatureArgHints(name:String, ?source:String, methodBodyStart:Int = -1, ?argNames:Array<String>):Array<{
		name:String,
		isOptional:Bool,
		typeHint:String,
		defaultText:String
	}> {
		if (source == null || source.length == 0 || name == null || name.length == 0)
			return [];
		final needle = "function " + name;
		function hintsAt(fnIndex:Int):Array<{
			name:String,
			isOptional:Bool,
			typeHint:String,
			defaultText:String
		}> {
			if (fnIndex < 0)
				return [];
			final open = source.indexOf("(", fnIndex);
			if (open < 0)
				return [];
			final close = findMatchingParen(source, open);
			if (close < 0)
				return [];
			return parseSourceSignatureArgs(source.substr(open + 1, close - open - 1));
		}
		final anchoredIndex = methodBodyStart > 0 ? source.lastIndexOf(needle, methodBodyStart) : -1;
		final anchoredHints = hintsAt(anchoredIndex);
		if (anchoredHints.length > 0 && sourceArgHintsMatchNames(anchoredHints, argNames))
			return anchoredHints;
		var first = new Array<{
			name:String,
			isOptional:Bool,
			typeHint:String,
			defaultText:String
		}>();
		var searchFrom = 0;
		while (searchFrom < source.length) {
			final fnIndex = source.indexOf(needle, searchFrom);
			if (fnIndex < 0)
				break;
			final hints = hintsAt(fnIndex);
			if (first.length == 0)
				first = hints;
			if (hints.length > 0 && sourceArgHintsMatchNames(hints, argNames))
				return hints;
			searchFrom = fnIndex + needle.length;
		}
		return first;
	}

	static function sourceArgHintsMatchNames(hints:Array<{
		name:String,
		isOptional:Bool,
		typeHint:String,
		defaultText:String
	}>, ?argNames:Array<String>):Bool {
		if (argNames == null || argNames.length == 0)
			return true;
		if (hints.length != argNames.length)
			return false;
		for (i in 0...argNames.length)
			if (hints[i].name != argNames[i])
				return false;
		return true;
	}

	static function protocolArgNames(argsPayload:String):Array<String> {
		final out = new Array<String>();
		if (argsPayload == null || argsPayload.length == 0)
			return out;
		for (arg in argsPayload.split(",")) {
			var name = StringTools.trim(arg);
			if (name.length == 0)
				continue;
			if (StringTools.startsWith(name, "..."))
				name = name.substr(3);
			if (StringTools.startsWith(name, "?"))
				name = name.substr(1);
			out.push(name);
		}
		return out;
	}

	static function parseSourceSignatureArgs(text:String):Array<{
		name:String,
		isOptional:Bool,
		typeHint:String,
		defaultText:String
	}> {
		final out = new Array<{
			name:String,
			isOptional:Bool,
			typeHint:String,
			defaultText:String
		}>();
		for (segment in splitTopLevelComma(text)) {
			var working = StringTools.trim(segment);
			if (working.length == 0)
				continue;
			if (StringTools.startsWith(working, "..."))
				working = StringTools.trim(working.substr(3));
			var isOptional = false;
			if (StringTools.startsWith(working, "?")) {
				isOptional = true;
				working = StringTools.trim(working.substr(1));
			}
			final nameMatch = ~/^([A-Za-z_][A-Za-z0-9_]*)/;
			if (!nameMatch.match(working))
				continue;
			final argName = nameMatch.matched(1);
			final afterName = StringTools.trim(working.substr(nameMatch.matchedPos().pos + nameMatch.matchedPos().len));
			final eqIndex = findTopLevelEquals(afterName);
			final typeSource = eqIndex >= 0 ? StringTools.trim(afterName.substr(0, eqIndex)) : afterName;
			final typeHint = StringTools.startsWith(typeSource, ":") ? StringTools.trim(typeSource.substr(1)) : "";
			final defaultText = eqIndex >= 0 ? StringTools.trim(afterName.substr(eqIndex + 1)) : "";
			out.push({
				name: argName,
				isOptional: isOptional || defaultText.length > 0,
				typeHint: typeHint,
				defaultText: defaultText
			});
		}
		return out;
	}

	static function sourceArgHintByName(hints:Array<{
		name:String,
		isOptional:Bool,
		typeHint:String,
		defaultText:String
	}>, name:String):Null<{
		name:String,
		isOptional:Bool,
		typeHint:String,
		defaultText:String
	}> {
		for (hint in hints)
			if (hint.name == name)
				return hint;
		return null;
	}

	static function compactTypeHint(typeHint:String):String {
		var compact = StringTools.trim(typeHint == null ? "" : typeHint);
		compact = StringTools.replace(compact, " ", "");
		compact = StringTools.replace(compact, "\t", "");
		compact = StringTools.replace(compact, "\r", "");
		compact = StringTools.replace(compact, "\n", "");
		return compact;
	}

	static function sourceTypeHintIsMoreSpecific(nativeTypeHint:String, sourceTypeHint:String):Bool {
		final source = compactTypeHint(sourceTypeHint);
		if (source.length == 0)
			return false;
		final native = compactTypeHint(nativeTypeHint);
		if (native.length == 0)
			return true;
		return (native == "Null" || native == "StdTypes.Null")
			&& (StringTools.startsWith(source, "Null<") || StringTools.startsWith(source, "StdTypes.Null<"));
	}

	static function defaultValueFromText(text:String):HxDefaultValue {
		final trimmed = StringTools.trim(text == null ? "" : text);
		if (trimmed.length == 0)
			return HxDefaultValue.NoDefault;
		if (trimmed == "null")
			return HxDefaultValue.Default(HxExpr.ENull);
		if (trimmed == "true")
			return HxDefaultValue.Default(HxExpr.EBool(true));
		if (trimmed == "false")
			return HxDefaultValue.Default(HxExpr.EBool(false));
		final first = trimmed.charAt(0);
		final last = trimmed.charAt(trimmed.length - 1);
		if ((first == "\"" && last == "\"") || (first == "'" && last == "'"))
			return HxDefaultValue.Default(HxExpr.EString(trimmed.substr(1, trimmed.length - 2)));
		final intValue = Std.parseInt(trimmed);
		if (intValue != null && Std.string(intValue) == trimmed)
			return HxDefaultValue.Default(HxExpr.EInt(intValue));
		return HxDefaultValue.Default(HxExpr.ENull);
	}

	static function decodeMethodPayload(payload:String, methodBodySrc:Null<String>, methodBodyStart:Int = -1, ?source:String):HxFunctionDecl {
		// Bootstrap note: payload is a `|` separated list (unescaped for '|').
		//
		// v=1:
		//   name|vis|static|args|ret|retstr
		//
		// v=1 (backward-compatible extensions; optional fields):
		//   name|vis|static|args|ret|retstr|retid|argtypes|retexpr
		//
		// Where:
		// - args: comma-separated argument names
		// - retid: first detected `return <ident>` (if any)
		// - argtypes: comma-separated `name:type` pairs (no '|' characters)
		final parts = payload.split("|");
		while (parts.length < 9)
			parts.push("");

		final name = parts[0];
		final vis = parts[1] == "private" ? HxVisibility.Private : HxVisibility.Public;
		final isStatic = parts[2] == "1";

		final argTypes:Map<String, String> = [];
		final optionalArgsByName:Map<String, Bool> = [];
		// Some protocol emitters may preserve the rest marker (`...name`) only in the
		// `argtypes` payload (and not in the raw `args` name list). Track rest names
		// separately so we can still mark `HxFunctionArg.isRest=true` reliably.
		final restArgsByName:Map<String, Bool> = [];
		final argTypesPayload = parts[7];
		if (argTypesPayload.length > 0) {
			for (entry in argTypesPayload.split(",")) {
				if (entry.length == 0)
					continue;
				final idx = entry.indexOf(":");
				if (idx <= 0)
					continue;
				var argName = entry.substr(0, idx);
				// Native parser encodes rest params as `...name`. Normalize for lookup, but also
				// retain the rest marker for later signature building (rest-only functions are
				// common in upstream harness code).
				if (StringTools.startsWith(argName, "...")) {
					argName = argName.substr(3);
					restArgsByName.set(argName, true);
				}
				if (StringTools.startsWith(argName, "?")) {
					argName = argName.substr(1);
					optionalArgsByName.set(argName, true);
				}
				final ty = entry.substr(idx + 1);
				argTypes.set(argName, ty);
			}
		}

		final argsPayload = parts[3];
		final args = new Array<HxFunctionArg>();
		final sourceHints = sourceSignatureArgHints(name, source, methodBodyStart, protocolArgNames(argsPayload));
		if (argsPayload.length > 0) {
			for (a in argsPayload.split(",")) {
				if (a.length == 0)
					continue;
				var rawName = a;
				var isRest = false;
				if (StringTools.startsWith(rawName, "...")) {
					isRest = true;
					rawName = rawName.substr(3);
				}
				var isOptional = false;
				if (StringTools.startsWith(rawName, "?")) {
					isOptional = true;
					rawName = rawName.substr(1);
				}
				if (!isRest && restArgsByName.exists(rawName))
					isRest = true;
				var ty = argTypes.exists(rawName) ? argTypes.get(rawName) : "";
				if (!isOptional && optionalArgsByName.exists(rawName))
					isOptional = true;
				final sourceHint = sourceArgHintByName(sourceHints, rawName);
				var defaultValue = HxDefaultValue.NoDefault;
				var defaultValueText = "";
				if (sourceHint != null) {
					if (sourceHint.isOptional)
						isOptional = true;
					if (sourceTypeHintIsMoreSpecific(ty, sourceHint.typeHint))
						ty = sourceHint.typeHint;
					defaultValueText = sourceHint.defaultText;
					defaultValue = defaultValueFromText(defaultValueText);
				}

				if (isRest) {
					// Stage3 bring-up: lower rest args to a single `Array<T>` parameter.
					final inner = (ty == null || StringTools.trim(ty).length == 0) ? "Dynamic" : ty;
					ty = "Array<" + inner + ">";
					isOptional = true;
				}

				args.push(new HxFunctionArg(rawName, ty, defaultValue, isOptional, isRest, defaultValueText));
			}
		}

		final returnTypeHint = parts[4];
		final retStr = parts[5];
		final retId = parts[6];
		final retExpr = parts[8];
		final body = new Array<HxStmt>();
		final pos = HxPos.unknown();
		// Prefer the richer `retexpr` field when present (it can represent `Util.ping()`),
		// but keep legacy fields for older protocol emitters.
		if (retExpr.length > 0) {
			body.push(SReturn(parseReturnExprText(retExpr), pos));
		} else if (retStr.length > 0) {
			body.push(SReturn(EString(retStr), pos));
		} else if (retId.length > 0) {
			body.push(SReturn(EIdent(retId), pos));
		}

		var outBody = body;
		#if !hxhx_stage0_no_hx_parser
		if (methodBodySrc != null && methodBodySrc.length > 0) {
			if (Sys.getEnv("HXHX_TRACE_BODY_PARSE_HAVE") == "1") {
				try {
					Sys.println("body_parse_have=" + name + " len=" + methodBodySrc.length);
				} catch (_:haxe.io.Error) {} catch (_:String) {}
			}
			if (Sys.getEnv("HXHX_TRACE_BODY_PARSE_SRC") == "1") {
				try {
					final oneLine = methodBodySrc.split("\n").join("\\n");
					final max = 300;
					final shown = oneLine.length > max ? (oneLine.substr(0, max) + "...") : oneLine;
					Sys.println("body_parse_src=" + name + " " + shown);
				} catch (_:haxe.io.Error) {} catch (_:String) {}
			}
			// Best-effort: recover a structured statement list from the raw source slice.
			//
			// Why
			// - The native frontend protocol v1+ transmits method bodies as raw source
			//   (via `ast method_body`) rather than an OCaml-side statement AST.
			// - Stage3 bring-up wants bodies so it can validate full-body lowering.
			// Debug aid: allow logging parse holes with the method name.
			HxParser.debugBodyLabel = name;
			try {
				outBody = HxParser.parseFunctionBodyTextAt(methodBodySrc, source, methodBodyStart);
			} catch (e:HxParseError) {
				if (Sys.getEnv("HXHX_TRACE_BODY_PARSE_FAIL") == "1") {
					try {
						Sys.println("body_parse_fail=" + name + " err=" + e.message);
					} catch (_:haxe.io.Error) {} catch (_:String) {}
				}
				// Fall back to the summary-only body.
				outBody = body;
			} catch (e:String) {
				if (Sys.getEnv("HXHX_TRACE_BODY_PARSE_FAIL") == "1") {
					try {
						Sys.println("body_parse_fail=" + name + " err=" + e);
					} catch (_:haxe.io.Error) {} catch (_:String) {}
				}
				// Fall back to the summary-only body.
				outBody = body;
			}
			HxParser.debugBodyLabel = "";
		}
		#end

		return new HxFunctionDecl(name, vis, isStatic, args, returnTypeHint, outBody, retStr);
	}

	static function findFunctionBodyStart(source:String, name:String):Int {
		if (source == null || name == null || name.length == 0)
			return -1;
		final needle = "function " + name;
		var index = source.indexOf(needle);
		while (index >= 0) {
			final afterName = index + needle.length;
			final open = source.indexOf("{", afterName);
			if (open < 0)
				return -1;
			final semi = source.indexOf(";", afterName);
			if (semi < 0 || open < semi)
				return open + 1;
			index = source.indexOf(needle, index + 1);
		}
		return -1;
	}

	static function decodeFieldPayload(payload:String, isFinal:Bool = false):Null<HxFieldDecl> {
		// v=2 field payload (also accepted from v1 `ast static_final`):
		//   name\nvis\nstatic\ntypehint\ninitexpr
		if (payload == null || payload.length == 0)
			return null;
		final lines = payload.split("\n");
		final name = lines.length > 0 ? lines[0] : "";
		if (name.length == 0)
			return null;
		final visLine = lines.length > 1 ? lines[1] : "public";
		final vis = visLine == "private" ? HxVisibility.Private : HxVisibility.Public;
		final isStatic = (lines.length > 2 ? lines[2] : "1") == "1";
		final typeHint = lines.length > 3 ? lines[3] : "";
		final initRaw = lines.length > 4 ? trimCapturedFieldInitializer(lines.slice(4).join("\n")) : "";
		var init:Null<HxExpr> = null;
		if (initRaw.length > 0)
			init = true ? parseReturnExprText(initRaw) : null;
		return new HxFieldDecl(name, vis, isStatic, typeHint, init, null, null, null, isFinal, "", "", initRaw);
	}

	static function decodeStaticFinalPayload(payload:String):Null<HxFieldDecl> {
		return decodeFieldPayload(payload, true);
	}

	static function trimCapturedFieldInitializer(raw:String):String {
		final text = StringTools.trim(raw == null ? "" : raw);
		if (!StringTools.startsWith(text, "switch"))
			return text;
		final end = balancedSwitchEnd(text);
		return end > 0 ? StringTools.trim(text.substr(0, end)) : text;
	}

	static function balancedSwitchEnd(text:String):Int {
		var braceStart = -1;
		for (i in 0...text.length) {
			if (text.charCodeAt(i) == "{".code) {
				braceStart = i;
				break;
			}
		}
		if (braceStart < 0)
			return -1;
		var depth = 0;
		for (i in braceStart...text.length) {
			final c = text.charCodeAt(i);
			if (c == "{".code) {
				depth += 1;
			} else if (c == "}".code) {
				depth -= 1;
				if (depth == 0)
					return i + 1;
			}
		}
		return -1;
	}

	static function parseReturnExprText(raw:String):HxExpr {
		// Bring-up: the native frontend transmits some expression text without fully parsing it.
		//
		// A common upstream pattern is `new Array<T>()` or `new Map<K,V>()`. In plain expression
		// parsing, the `<...>` type-parameter group can be misinterpreted as `<`/`>` operators,
		// producing a structurally valid but semantically nonsense AST (and then invalid OCaml).
		//
		// For Stage3 emission, we do not need to preserve the type parameters, only the allocation
		// shape, so we strip the `<...>` group when it appears immediately after a `new Type`.
		function stripNewTypeParams(s:String):String {
			final t = s == null ? "" : StringTools.trim(s);
			// The native protocol's expression capture concatenates tokens without spaces, so
			// `new Array<T>()` can arrive as `newArray<T>()`. Normalize that first.
			if (!StringTools.startsWith(t, "new"))
				return s;
			var norm = t;
			if (norm.length > 3) {
				final c3 = norm.charCodeAt(3);
				final isWs = c3 == " ".code || c3 == "\t".code || c3 == "\n".code || c3 == "\r".code;
				if (!isWs)
					norm = "new " + norm.substr(3);
			}
			if (!StringTools.startsWith(norm, "new "))
				return norm;
			final lt = norm.indexOf("<");
			final lp = norm.indexOf("(");
			if (lt < 0 || lp < 0 || lt > lp)
				return s;
			var depth = 0;
			var i = lt;
			while (i < norm.length) {
				final c = norm.charCodeAt(i);
				if (c == "<".code)
					depth++;
				else if (c == ">".code) {
					depth--;
					if (depth == 0) {
						return norm.substr(0, lt) + norm.substr(i + 1);
					}
				}
				i++;
			}
			return norm;
		}

		var s = StringTools.trim(raw);
		s = stripNewTypeParams(s);
		if (s.length == 0)
			return EUnsupported("<empty-return-expr>");

		final regexLiteral = parseRegexLiteral(s);
		if (regexLiteral != null)
			return ENew("EReg", [EString(regexLiteral.pattern), EString(regexLiteral.flags)]);

		if (s == "null")
			return ENull;
		if (s == "true")
			return EBool(true);
		if (s == "false")
			return EBool(false);

		if (s.length >= 2 && StringTools.startsWith(s, "\"") && StringTools.endsWith(s, "\"")) {
			return EString(s.substr(1, s.length - 2));
		}

		// Integers: [-]?[0-9]+ (manual parse to avoid Null<Int> pitfalls in bootstrap output).
		{
			var i = 0;
			var sign = 1;
			if (s.length > 0 && s.charCodeAt(0) == "-".code) {
				sign = -1;
				i = 1;
			}

			var value = 0;
			var saw = false;
			while (i < s.length) {
				final c = s.charCodeAt(i);
				if (c < "0".code || c > "9".code) {
					saw = false;
					break;
				}
				saw = true;
				value = value * 10 + (c - "0".code);
				i++;
			}

			if (saw && i == s.length)
				return EInt(sign * value);
		}

		// Floats: best-effort via parseFloat if it contains '.'.
		if (s.indexOf(".") != -1) {
			final f = Std.parseFloat(s);
			if (!Math.isNaN(f))
				return EFloat(f);
		}

		#if hxhx_stage0_no_hx_parser
		// Stage0 profiling lane: avoid pulling the pure-Haxe parser fallback surface.
		return EUnsupported(s);
		#else
		// Fallback: try to parse a small field/call chain (e.g. `Util.ping()`).
		return try {
			HxParser.parseExprText(s);
		} catch (_:HxParseError) {
			// Last resort: treat as unsupported so emitters don't attempt to print raw Haxe text as OCaml.
			EUnsupported(s);
		} catch (_:String) {
			// Last resort: treat as unsupported so emitters don't attempt to print raw Haxe text as OCaml.
			EUnsupported(s);
		}
		#end
	}

	static function parseRegexLiteral(source:String):Null<{pattern:String, flags:String}> {
		if (!StringTools.startsWith(source, "~/"))
			return null;
		var index = 2;
		var escaped = false;
		while (index < source.length) {
			final code = source.charCodeAt(index);
			if (escaped) {
				escaped = false;
				index++;
				continue;
			}
			if (code == "\\".code) {
				escaped = true;
				index++;
				continue;
			}
			if (code == "/".code) {
				final pattern = source.substr(2, index - 2);
				final flags = source.substr(index + 1);
				var flagIndex = 0;
				while (flagIndex < flags.length) {
					final flagCode = flags.charCodeAt(flagIndex);
					final isLower = flagCode >= "a".code && flagCode <= "z".code;
					final isUpper = flagCode >= "A".code && flagCode <= "Z".code;
					if (!isLower && !isUpper)
						return null;
					flagIndex++;
				}
				return {pattern: pattern, flags: flags};
			}
			index++;
		}
		return null;
	}

	static function throwFromErrLine(line:String):Void {
		// err <index> <line> <col> <len>:<message>
		final parts = splitN(line, 4); // ["err", idx, line, col, tail]
		final idx = parts.length > 1 ? parseDecInt(parts[1]) : -1;
		final ln = parts.length > 2 ? parseDecInt(parts[2]) : -1;
		final col = parts.length > 3 ? parseDecInt(parts[3]) : -1;
		final tail = parts.length > 4 ? parts[4] : "";
		final msg = decodeLenPayload(tail);
		final idx0 = idx < 0 ? 0 : idx;
		final ln0 = ln < 0 ? 0 : ln;
		final col0 = col < 0 ? 0 : col;
		throw "Native frontend: " + msg + " (" + idx0 + ":" + ln0 + ":" + col0 + ")";
	}

	static function decodeLenPayload(s:String):String {
		final colon = s.indexOf(":");
		if (colon <= 0)
			return "";
		final len = parseDecInt(s.substr(0, colon));
		if (len < 0)
			return "";
		final payload = s.substr(colon + 1);
		final raw = payload.substr(0, len);
		return unescapePayload(raw);
	}

	static function parseDecInt(s:String):Int {
		if (s == null)
			return -1;
		var i = 0;
		// Trim leading spaces (defensive).
		while (i < s.length && s.charCodeAt(i) == " ".code)
			i++;
		if (i >= s.length)
			return -1;
		var value = 0;
		var saw = false;
		while (i < s.length) {
			final c = s.charCodeAt(i);
			if (c < "0".code || c > "9".code)
				break;
			saw = true;
			value = value * 10 + (c - "0".code);
			i++;
		}
		return saw ? value : -1;
	}

	static function unescapePayload(s:String):String {
		final out = new StringBuf();
		var i = 0;
		while (i < s.length) {
			final c = s.charCodeAt(i);
			if (c == "\\".code && i + 1 < s.length) {
				final n = s.charCodeAt(i + 1);
				switch (n) {
					case "n".code:
						out.addChar("\n".code);
					case "r".code:
						out.addChar("\r".code);
					case "t".code:
						out.addChar("\t".code);
					case "\\".code:
						out.addChar("\\".code);
					case _:
						out.addChar(n);
				}
				i += 2;
				continue;
			}
			out.addChar(c);
			i++;
		}
		return out.toString();
	}

	static function splitN(s:String, n:Int):Array<String> {
		// Split into exactly `n` space-separated fields, plus a final "tail" field (may contain spaces).
		final head = new Array<String>();
		var i = 0;
		var start = 0;
		while (head.length < n && i <= s.length) {
			if (i == s.length || s.charCodeAt(i) == " ".code) {
				if (i > start)
					head.push(s.substr(start, i - start));
				while (i < s.length && s.charCodeAt(i) == " ".code)
					i++;
				start = i;
				continue;
			}
			i++;
		}
		while (head.length < n)
			head.push("");
		final tail = start <= s.length ? s.substr(start) : "";
		head.push(tail);
		return head;
	}
	#end
	#end
}
