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
			if (filePath == null || filePath.length == 0) return null;
			final name = haxe.io.Path.withoutDirectory(filePath);
			final dot = name.lastIndexOf(".");
			return dot <= 0 ? name : name.substr(0, dot);
		}

		public static function parse(source:String, ?filePath:String):ParsedModule {
			final expectedMainClass = expectedMainClassFromFile(filePath);
			final decl = #if hih_native_parser
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

								// Some upstream modules have a non-class main type (notably enums).
								//
								// If the native protocol returns `Unknown`, scan for a matching top-level enum
								// and treat it as the module's main provider so emission doesn't drop the unit.
								final enumDeclsAll = scanModuleLocalHelperEnums(source, null);
								final typedefDeclsAll = scanModuleLocalHelperTypedefs(source, null);
								final abstractDeclsAll = scanModuleLocalHelperAbstracts(source, null);
								if ((mainName == null || mainName.length == 0 || mainName == "Unknown") && expectedMainClass != null) {
									function tryPickMainFrom(candidates:Array<HxClassDecl>):Bool {
										if (candidates == null) return false;
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
										if (!tryPickMainFrom(typedefDeclsAll)) tryPickMainFrom(abstractDeclsAll);
									}
								}

								final existingClasses = HxModuleDecl.getClasses(nativeDecl);
								final existingNames:Map<String, Bool> = new Map();
								for (c in existingClasses) {
									final nm = c == null ? null : HxClassDecl.getName(c);
									if (nm != null && nm.length > 0) existingNames.set(nm, true);
								}

								function isMissingAndNotMain(c:HxClassDecl):Bool {
									final nm = c == null ? null : HxClassDecl.getName(c);
									return nm != null && nm.length > 0 && nm != mainName && !existingNames.exists(nm);
								}

								final extras = new Array<HxClassDecl>();
								for (c in scanModuleLocalHelperClasses(source, mainName)) if (isMissingAndNotMain(c)) extras.push(c);
								final enumDecls = new Array<HxClassDecl>();
								for (c in enumDeclsAll) if (isMissingAndNotMain(c)) enumDecls.push(c);
								final typedefDecls = new Array<HxClassDecl>();
								for (c in typedefDeclsAll) if (isMissingAndNotMain(c)) typedefDecls.push(c);
								final abstractDecls = new Array<HxClassDecl>();
								for (c in abstractDeclsAll) if (isMissingAndNotMain(c)) abstractDecls.push(c);

								if (extras.length == 0
									&& enumDecls.length == 0
									&& typedefDecls.length == 0
									&& abstractDecls.length == 0
									&& main == HxModuleDecl.getMainClass(nativeDecl)) {
									return nativeDecl;
								}

								final classes = new Array<HxClassDecl>();
								final seen:Map<String, Bool> = new Map();
								function pushUnique(c:HxClassDecl):Void {
									if (c == null) return;
									final nm = HxClassDecl.getName(c);
									if (nm != null && nm.length > 0 && seen.exists(nm)) return;
									classes.push(c);
									if (nm != null && nm.length > 0) seen.set(nm, true);
								}

								pushUnique(main);
								for (c in existingClasses) pushUnique(c);
								for (c in extras) pushUnique(c);
								for (c in enumDecls) pushUnique(c);
								for (c in typedefDecls) pushUnique(c);
								for (c in abstractDecls) pushUnique(c);

								return new HxModuleDecl(
									HxModuleDecl.getPackagePath(nativeDecl),
									HxModuleDecl.getImports(nativeDecl),
									main,
									classes,
									HxModuleDecl.getHeaderOnly(nativeDecl),
									HxModuleDecl.getHasToplevelMain(nativeDecl)
								);
							}

						final v = Sys.getEnv("HIH_FORCE_HX_PARSER");
						if (v == "1" || v == "true" || v == "yes") return enrichNativeDecl(new HxParser(source).parseModule(expectedMainClass));
						try {
							return enrichNativeDecl(parseViaNativeHooks(source, expectedMainClass));
						} catch (eNative:Dynamic) {
						final strict = Sys.getEnv("HIH_NATIVE_PARSER_STRICT");
						if (strict == "1" || strict == "true" || strict == "yes") throw eNative;

					// Fallback: the pure-Haxe frontend is slower, but it can unblock bring-up when the
					// native lexer/parser cannot yet handle an upstream-shaped input.
					//
						// This is especially useful when widening the module graph for upstream suites
						// (e.g. enabling heuristic same-package type resolution).
						try {
							return enrichNativeDecl(new HxParser(source).parseModule(expectedMainClass));
						} catch (_:Dynamic) {
							// Prefer the native error (it is usually more specific about the failure mode).
							throw eNative;
						}
				}
				})());
			#else
				new HxParser(source).parseModule(expectedMainClass);
			#end
			final path = filePath == null || filePath.length == 0 ? "<memory>" : filePath;
			return new ParsedModule(source, decl, path);
		}

	#if hih_native_parser
	static function parseViaNativeHooks(source:String, expectedMainClass:Null<String>):HxModuleDecl {
		final encoded =
			expectedMainClass != null && expectedMainClass.length > 0
				? native.NativeParser.parseModuleDeclWithExpected(source, expectedMainClass)
				: native.NativeParser.parseModuleDecl(source);
		return decodeNativeProtocol(encoded);
	}

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
		if (source == null || source.length == 0) return out;

		final seen:Map<String, Bool> = new Map();
		if (mainClassName != null && mainClassName.length > 0) seen.set(mainClassName, true);

		var braceDepth = 0;
		var i = 0;
		while (true) {
			final t = scanNextToken(source, i);
			i = t.nextPos;
			if (t.text.length == 0) break;

			if (!t.isIdent) {
				if (t.text == "{") braceDepth += 1;
				else if (t.text == "}") braceDepth = braceDepth > 0 ? (braceDepth - 1) : 0;
				continue;
			}

			if (braceDepth != 0) continue;
			if (t.text != "class") continue;

			// class <Name> ...
			var nameTok = scanNextToken(source, i);
			// Skip stray symbols/metadata between `class` and the identifier.
			while (nameTok.text.length > 0 && !nameTok.isIdent) nameTok = scanNextToken(source, nameTok.nextPos);
			if (!nameTok.isIdent || nameTok.text.length == 0) continue;

			final className = nameTok.text;
			i = nameTok.nextPos;
			final isMain = mainClassName != null && className == mainClassName;
			final alreadySeen = seen.exists(className);
			final shouldRecord = !isMain && !alreadySeen;
			if (!alreadySeen) seen.set(className, true);

			// Seek the opening `{` for this class header.
			var headerTok = scanNextToken(source, i);
			while (headerTok.text.length > 0 && headerTok.text != "{") headerTok = scanNextToken(source, headerTok.nextPos);
			if (headerTok.text != "{") continue;

			final bodyStart = headerTok.nextPos;
			final scanned = scanClassBodyForStatics(source, bodyStart);
			i = scanned.nextPos;

			if (shouldRecord) out.push(new HxClassDecl(className, false, scanned.functions, scanned.fields));
		}

		return out;
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
		- Correct enum runtime representation (tagging, reflection).
		- Enum abstracts (we treat `enum abstract` values as field/function stubs).
	**/
	static function scanModuleLocalHelperEnums(source:String, mainTypeName:Null<String>):Array<HxClassDecl> {
		final out = new Array<HxClassDecl>();
		if (source == null || source.length == 0) return out;

		inline function isUpperStart(name:String):Bool {
			if (name == null || name.length == 0) return false;
			final c = name.charCodeAt(0);
			return c >= "A".code && c <= "Z".code;
		}

		final seen:Map<String, Bool> = new Map();
		if (mainTypeName != null && mainTypeName.length > 0) seen.set(mainTypeName, true);

		var braceDepth = 0;
		var i = 0;

		while (true) {
			final t = scanNextToken(source, i);
			i = t.nextPos;
			if (t.text.length == 0) break;

			if (!t.isIdent) {
				if (t.text == "{") braceDepth += 1;
				else if (t.text == "}") braceDepth = braceDepth > 0 ? (braceDepth - 1) : 0;
				continue;
			}

			if (braceDepth != 0) continue;
			if (t.text != "enum") continue;

			// enum [abstract] <Name> ...
			var isEnumAbstract = false;
			var nameTok = scanNextToken(source, i);
			while (nameTok.text.length > 0 && !nameTok.isIdent) nameTok = scanNextToken(source, nameTok.nextPos);
			if (!nameTok.isIdent || nameTok.text.length == 0) continue;

			if (nameTok.text == "abstract") {
				isEnumAbstract = true;
				nameTok = scanNextToken(source, nameTok.nextPos);
				while (nameTok.text.length > 0 && !nameTok.isIdent) nameTok = scanNextToken(source, nameTok.nextPos);
				if (!nameTok.isIdent || nameTok.text.length == 0) continue;
			}

			final enumName = nameTok.text;
			i = nameTok.nextPos;

			if (enumName == null || enumName.length == 0) continue;
			if (seen.exists(enumName)) {
				// Still need to consume the body so the outer loop doesn't get confused.
				var headerTok = scanNextToken(source, i);
				while (headerTok.text.length > 0 && headerTok.text != "{") headerTok = scanNextToken(source, headerTok.nextPos);
				if (headerTok.text != "{") continue;
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
			while (headerTok.text.length > 0 && headerTok.text != "{") headerTok = scanNextToken(source, headerTok.nextPos);
			if (headerTok.text != "{") continue;

			final fields = new Array<HxFieldDecl>();
			final functions = new Array<HxFunctionDecl>();
			if (isEnumAbstract) {
				final scanned = scanEnumAbstractBodyForValues(source, headerTok.nextPos);
				i = scanned.nextPos;
				// `enum abstract` values are declared as `var Name = <expr>;` inside the body.
				//
				// Bring-up: record only the value names, emit them as static fields with a placeholder
				// initializer. This keeps Stage3 emission linking without committing to full semantics.
				for (v in scanned.values) {
					if (v == null || v.length == 0 || !isUpperStart(v)) continue;
					fields.push(new HxFieldDecl(v, HxVisibility.Public, true, "Dynamic", EInt(0)));
				}
			} else {
				final scanned = scanEnumBodyForCtors(source, headerTok.nextPos);
				i = scanned.nextPos;
				for (ctor in scanned.ctors) {
					if (ctor == null) continue;
					final ctorName = ctor.name;
					if (ctorName == null || ctorName.length == 0 || !isUpperStart(ctorName)) continue;
					final argNames = ctor.args == null ? [] : ctor.args;
					if (argNames.length == 0) {
						fields.push(new HxFieldDecl(ctorName, HxVisibility.Public, true, "Dynamic", null));
					} else {
						final args = new Array<HxFunctionArg>();
						for (a in argNames) args.push(new HxFunctionArg(a, "", HxDefaultValue.NoDefault, false, false));
						// Constructors conceptually return an enum value; during bring-up we keep the
						// type wide to avoid OCaml type errors in heavily-`Obj.magic` codegen.
						functions.push(new HxFunctionDecl(ctorName, HxVisibility.Public, true, args, "Dynamic", [], ""));
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
		if (source == null || source.length == 0) return out;

		final seen:Map<String, Bool> = new Map();
		if (mainTypeName != null && mainTypeName.length > 0) seen.set(mainTypeName, true);

		var braceDepth = 0;
		var i = 0;
		while (true) {
			final t = scanNextToken(source, i);
			i = t.nextPos;
			if (t.text.length == 0) break;

			if (!t.isIdent) {
				if (t.text == "{") braceDepth += 1;
				else if (t.text == "}") braceDepth = braceDepth > 0 ? (braceDepth - 1) : 0;
				continue;
			}

			if (braceDepth != 0) continue;
			if (t.text != "typedef") continue;

			var nameTok = scanNextToken(source, i);
			while (nameTok.text.length > 0 && !nameTok.isIdent) nameTok = scanNextToken(source, nameTok.nextPos);
			if (!nameTok.isIdent || nameTok.text.length == 0) continue;

			final typeName = nameTok.text;
			i = nameTok.nextPos;
			if (typeName == null || typeName.length == 0) continue;
			if (seen.exists(typeName)) continue;
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
		if (source == null || source.length == 0) return out;

		final seen:Map<String, Bool> = new Map();
		if (mainTypeName != null && mainTypeName.length > 0) seen.set(mainTypeName, true);

		var braceDepth = 0;
		var i = 0;
		while (true) {
			final t = scanNextToken(source, i);
			i = t.nextPos;
			if (t.text.length == 0) break;

			if (!t.isIdent) {
				if (t.text == "{") braceDepth += 1;
				else if (t.text == "}") braceDepth = braceDepth > 0 ? (braceDepth - 1) : 0;
				continue;
			}

			if (braceDepth != 0) continue;
			if (t.text == "enum") {
				// Skip full top-level enum blocks so `enum abstract` isn't treated as a regular abstract.
				var enumNameTok = scanNextToken(source, i);
				while (enumNameTok.text.length > 0 && !enumNameTok.isIdent) enumNameTok = scanNextToken(source, enumNameTok.nextPos);
				if (!enumNameTok.isIdent || enumNameTok.text.length == 0) continue;

				var isEnumAbstract = false;
				if (enumNameTok.text == "abstract") {
					isEnumAbstract = true;
					enumNameTok = scanNextToken(source, enumNameTok.nextPos);
					while (enumNameTok.text.length > 0 && !enumNameTok.isIdent) enumNameTok = scanNextToken(source, enumNameTok.nextPos);
					if (!enumNameTok.isIdent || enumNameTok.text.length == 0) continue;
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
			if (t.text != "abstract") continue;

			var nameTok = scanNextToken(source, i);
			while (nameTok.text.length > 0 && !nameTok.isIdent) nameTok = scanNextToken(source, nameTok.nextPos);
			if (!nameTok.isIdent || nameTok.text.length == 0) continue;

			final abstractName = nameTok.text;
			i = nameTok.nextPos;

			final isMain = mainTypeName != null && abstractName == mainTypeName;
			final alreadySeen = seen.exists(abstractName);
			final shouldRecord = !isMain && !alreadySeen;
			if (!alreadySeen) seen.set(abstractName, true);

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

			if (shouldRecord) out.push(new HxClassDecl(abstractName, false, functions, fields));
		}

		return out;
	}

	static function scanEnumBodyForCtors(source:String, start:Int):{nextPos:Int, ctors:Array<{name:String, args:Array<String>}>} {
		final ctors = new Array<{name:String, args:Array<String>}>();

		var depth = 1; // we start just after `{`
		var i = start;

		inline function isUpperStart(name:String):Bool {
			if (name == null || name.length == 0) return false;
			final c = name.charCodeAt(0);
			return c >= "A".code && c <= "Z".code;
		}

		while (true) {
			final t = scanNextToken(source, i);
			i = t.nextPos;
			if (t.text.length == 0) break;

			if (!t.isIdent) {
				switch (t.text) {
					case "{":
						depth += 1;
					case "}":
						depth -= 1;
						if (depth <= 0) break;
					case _:
				}
				continue;
			}

			if (depth != 1) continue;
			if (!isUpperStart(t.text)) continue;

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
					if (at.text.length == 0) break;

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
								if (braceDepthInArgs > 0) braceDepthInArgs -= 1;
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
								if (expectArg && parenDepth == 1 && bracketDepth == 0 && braceDepthInArgs == 0 && angleDepth == 0) pendingOptional = true;
							case "...":
								if (expectArg && parenDepth == 1 && bracketDepth == 0 && braceDepthInArgs == 0 && angleDepth == 0) pendingRest = true;
							case _:
						}
						continue;
					}

					if (!expectArg) continue;
					if (parenDepth != 1 || bracketDepth != 0 || braceDepthInArgs != 0 || angleDepth != 0) continue;

					final nm = at.text;
					final argName = (nm == null || nm.length == 0) ? ("arg" + argIndex) : nm;
					ctorArgs.push(argName);
					argIndex += 1;
					expectArg = false;
					pendingOptional = false;
					pendingRest = false;
				}
			}

			ctors.push({ name: ctorName, args: ctorArgs });

			// Consume tokens until the terminating `;` so we don't interpret type names
			// as additional constructors.
			while (true) {
				final tt = scanNextToken(source, i);
				i = tt.nextPos;
				if (tt.text.length == 0) break;
				if (!tt.isIdent) {
					if (tt.text == "{") depth += 1;
					else if (tt.text == "}") {
						depth -= 1;
						if (depth <= 0) break;
					} else if (depth == 1 && (tt.text == ";" || tt.text == ",")) {
						break;
					}
				}
			}
		}

		return { nextPos: i, ctors: ctors };
	}

	static function scanEnumAbstractBodyForValues(source:String, start:Int):{nextPos:Int, values:Array<String>} {
		final values = new Array<String>();

		var depth = 1; // we start just after `{`
		var i = start;

		inline function isUpperStart(name:String):Bool {
			if (name == null || name.length == 0) return false;
			final c = name.charCodeAt(0);
			return c >= "A".code && c <= "Z".code;
		}

		while (true) {
			final t = scanNextToken(source, i);
			i = t.nextPos;
			if (t.text.length == 0) break;

			if (!t.isIdent) {
				switch (t.text) {
					case "{":
						depth += 1;
					case "}":
						depth -= 1;
						if (depth <= 0) break;
					case _:
				}
				continue;
			}

			if (depth != 1) continue;
			if (t.text != "var") continue;

			// var <Name> ...
			var nameTok = scanNextToken(source, i);
			while (nameTok.text.length > 0 && !nameTok.isIdent) nameTok = scanNextToken(source, nameTok.nextPos);
			if (!nameTok.isIdent || nameTok.text.length == 0) continue;
			final name = nameTok.text;
			i = nameTok.nextPos;
			if (isUpperStart(name)) values.push(name);
		}

		return { nextPos: i, values: values };
	}

	static function scanClassBodyForStatics(source:String, start:Int):{nextPos:Int, fields:Array<HxFieldDecl>, functions:Array<HxFunctionDecl>} {
		final fields = new Array<HxFieldDecl>();
		final functions = new Array<HxFunctionDecl>();

		var depth = 1; // we start just after `{`
		var i = start;

		var sawStatic = false;
		var vis:HxVisibility = HxVisibility.Public;

		while (true) {
			final t = scanNextToken(source, i);
			i = t.nextPos;
			if (t.text.length == 0) break;

			if (!t.isIdent) {
				switch (t.text) {
					case "{":
						depth += 1;
					case "}":
						depth -= 1;
						if (depth <= 0) break;
					case ";":
						if (depth == 1) {
							// Declarations are terminated; reset modifiers.
							sawStatic = false;
							vis = HxVisibility.Public;
						}
					case _:
				}
				continue;
			}

			if (depth != 1) continue;

			switch (t.text) {
				case "public":
					vis = HxVisibility.Public;
				case "private":
					vis = HxVisibility.Private;
				case "static":
					sawStatic = true;
				case "inline" | "macro" | "extern" | "override":
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
								if (!nt.isIdent) continue;
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
						if (!isFieldDecl) continue;
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

					while (true) {
						final ft = scanNextToken(source, i);
						i = ft.nextPos;
						if (ft.text.length == 0) break;

						if (!ft.isIdent) {
							switch (ft.text) {
								case "{":
									depth += 1;
								case "}":
									depth -= 1;
									if (depth <= 0) break;
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
									if (depth == 1 && parenDepth == 0 && bracketDepth == 0 && angleDepth == 0) break;
								case _:
							}
							continue;
						}

						if (depth != 1) continue;
						if (!wantName) continue;

						final name = ft.text;
						wantName = false;
						if (!wantStatic) continue;
						if (name == null || name.length == 0) continue;
						fields.push(new HxFieldDecl(name, fieldVis, true, "", null));
					}

					sawStatic = false;
					vis = HxVisibility.Public;
				case "function":
					// Best-effort: collect static function name + arity so stub modules can be emitted.
					final wantStaticFn = sawStatic;
					final fnVis = vis;

					var nameTok = scanNextToken(source, i);
					while (nameTok.text.length > 0 && !nameTok.isIdent) nameTok = scanNextToken(source, nameTok.nextPos);
					final fnName = (nameTok.isIdent && nameTok.text.length > 0) ? nameTok.text : "";
					i = nameTok.nextPos;

					// Seek `(` for the parameter list (skip generics / return types).
					var sigTok = scanNextToken(source, i);
					while (sigTok.text.length > 0 && sigTok.text != "(" && sigTok.text != "{"
						&& sigTok.text != ";" && sigTok.text != "=") {
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
							if (at.text.length == 0) break;

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
										if (braceDepthInArgs > 0) braceDepthInArgs -= 1;
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
										if (expectArg && parenDepth == 1 && bracketDepth == 0 && braceDepthInArgs == 0 && angleDepth == 0) pendingOptional = true;
									case "...":
										if (expectArg && parenDepth == 1 && bracketDepth == 0 && braceDepthInArgs == 0 && angleDepth == 0) pendingRest = true;
									case _:
								}
								continue;
							}

							if (!expectArg) continue;
							if (parenDepth != 1 || bracketDepth != 0 || braceDepthInArgs != 0 || angleDepth != 0) continue;

							final nm = at.text;
							final argName = (nm == null || nm.length == 0) ? ("arg" + argIndex) : nm;
							args.push(new HxFunctionArg(argName, "", HxDefaultValue.NoDefault, pendingOptional, pendingRest));
							argIndex += 1;
							expectArg = false;
							pendingOptional = false;
							pendingRest = false;
						}
					}

					if (wantStaticFn && fnName.length > 0 && fnName != "new") {
						functions.push(new HxFunctionDecl(fnName, fnVis, true, args, "", [], ""));
					}

					sawStatic = false;
					vis = HxVisibility.Public;
				case _:
			}
		}

		return { nextPos: i, fields: fields, functions: functions };
	}

	static function scanNextToken(source:String, start:Int):{isIdent:Bool, text:String, nextPos:Int} {
		final len = source.length;
		var i = start;

		inline function isWs(c:Int):Bool return c == 9 || c == 10 || c == 13 || c == 32;
		inline function isIdentStart(c:Int):Bool return (c >= "A".code && c <= "Z".code) || (c >= "a".code && c <= "z".code) || c == "_".code;
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
					if (cc == "\n".code) break;
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
						if (i < len) i += 1;
						continue;
					}
					if (cc == quote) break;
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
						if (i < len) i += 1;
						continue;
					}
					if (cc == "/".code) break;
				}
				// flags
				while (i < len && isIdentPart(source.charCodeAt(i))) i += 1;
				continue;
			}

			if (isIdentStart(c)) {
				final startIdent = i;
				i += 1;
				while (i < len && isIdentPart(source.charCodeAt(i))) i += 1;
				return { isIdent: true, text: source.substr(startIdent, i - startIdent), nextPos: i };
			}

			// Ellipsis
			if (c == ".".code && i + 2 < len && source.charCodeAt(i + 1) == ".".code && source.charCodeAt(i + 2) == ".".code) {
				return { isIdent: false, text: "...", nextPos: i + 3 };
			}

			// Single-char symbol
			return { isIdent: false, text: String.fromCharCode(c), nextPos: i + 1 };
		}

		return { isIdent: false, text: "", nextPos: len };
	}

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
			static function decodeNativeProtocol(encoded:String):HxModuleDecl {
				final lines = encoded.split("\n").filter(l -> l.length > 0);
				if (lines.length == 0 || lines[0] != "hxhx_frontend_v=1") {
					throw "Native frontend: missing/invalid protocol header";
				}

				var packagePath = "";
				final imports = new Array<String>();
				var className = "Unknown";
				var headerOnly = false;
				var hasToplevelMain = false;
				var hasStaticMain = false;
				final methodPayloads = new Array<String>();
				final staticFinalPayloads = new Array<String>();
				final methodBodies:Map<String, String> = [];
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
				if (firstSpace <= 0) continue;
				final key = rest.substr(0, firstSpace);
						final payload = decodeLenPayload(rest.substr(firstSpace + 1));
						switch (key) {
							case "package":
								packagePath = payload;
							case "imports":
								if (payload.length > 0) {
									for (p in payload.split("|")) if (p.length > 0) imports.push(p);
								}
							case "class":
								className = payload;
							case "header_only":
								headerOnly = payload == "1";
							case "toplevel_main":
								hasToplevelMain = payload == "1";
							case "method":
								methodPayloads.push(payload);
							case "static_final":
								staticFinalPayloads.push(payload);
							case "method_body":
								// Payload format: "<methodName>\n<bodySource>"
								final nl = payload.indexOf("\n");
								if (nl > 0) {
									final name = payload.substr(0, nl);
									if (!methodBodies.exists(name)) {
										methodBodies.set(name, payload.substr(nl + 1));
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
					functions.push(decodeMethodPayload(mp, methodBodies.exists(name) ? methodBodies.get(name) : null));
				}

				for (fp in staticFinalPayloads) {
					final f = decodeStaticFinalPayload(fp);
					if (f != null) fields.push(f);
				}

				final cls = new HxClassDecl(className, hasStaticMain, functions, fields);
				return new HxModuleDecl(packagePath, imports, cls, [cls], headerOnly, hasToplevelMain);
			}

		static function decodeMethodPayload(payload:String, methodBodySrc:Null<String>):HxFunctionDecl {
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
		while (parts.length < 9) parts.push("");

		final name = parts[0];
		final vis = parts[1] == "private" ? HxVisibility.Private : HxVisibility.Public;
		final isStatic = parts[2] == "1";

		final argTypes:Map<String, String> = [];
		// Some protocol emitters may preserve the rest marker (`...name`) only in the
		// `argtypes` payload (and not in the raw `args` name list). Track rest names
		// separately so we can still mark `HxFunctionArg.isRest=true` reliably.
		final restArgsByName:Map<String, Bool> = [];
		final argTypesPayload = parts[7];
		if (argTypesPayload.length > 0) {
			for (entry in argTypesPayload.split(",")) {
				if (entry.length == 0) continue;
				final idx = entry.indexOf(":");
				if (idx <= 0) continue;
				var argName = entry.substr(0, idx);
				// Native parser encodes rest params as `...name`. Normalize for lookup, but also
				// retain the rest marker for later signature building (rest-only functions are
				// common in upstream harness code).
				if (StringTools.startsWith(argName, "...")) {
					argName = argName.substr(3);
					restArgsByName.set(argName, true);
				}
				final ty = entry.substr(idx + 1);
				argTypes.set(argName, ty);
			}
		}

		final args = new Array<HxFunctionArg>();
		final argsPayload = parts[3];
		if (argsPayload.length > 0) {
			for (a in argsPayload.split(",")) {
				if (a.length == 0) continue;
				var rawName = a;
				var isRest = false;
				if (StringTools.startsWith(rawName, "...")) {
					isRest = true;
					rawName = rawName.substr(3);
				}
				if (!isRest && restArgsByName.exists(rawName)) isRest = true;
				var ty = argTypes.exists(rawName) ? argTypes.get(rawName) : "";
				var isOptional = false;

				if (isRest) {
					// Stage3 bring-up: lower rest args to a single `Array<T>` parameter.
					final inner = (ty == null || StringTools.trim(ty).length == 0) ? "Dynamic" : ty;
					ty = "Array<" + inner + ">";
					isOptional = true;
				}

				args.push(new HxFunctionArg(rawName, ty, HxDefaultValue.NoDefault, isOptional, isRest));
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
				if (methodBodySrc != null && methodBodySrc.length > 0) {
					if (Sys.getEnv("HXHX_TRACE_BODY_PARSE_HAVE") == "1") {
						try {
							Sys.println("body_parse_have=" + name + " len=" + methodBodySrc.length);
						} catch (_:Dynamic) {}
					}
					if (Sys.getEnv("HXHX_TRACE_BODY_PARSE_SRC") == "1") {
						try {
							final oneLine = methodBodySrc.split("\n").join("\\n");
							final max = 300;
							final shown = oneLine.length > max ? (oneLine.substr(0, max) + "...") : oneLine;
							Sys.println("body_parse_src=" + name + " " + shown);
						} catch (_:Dynamic) {}
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
					outBody = HxParser.parseFunctionBodyText(methodBodySrc);
				} catch (e:Dynamic) {
					if (Sys.getEnv("HXHX_TRACE_BODY_PARSE_FAIL") == "1") {
						try {
							Sys.println("body_parse_fail=" + name + " err=" + Std.string(e));
						} catch (_:Dynamic) {}
					}
					// Fall back to the summary-only body.
					outBody = body;
				}
				HxParser.debugBodyLabel = "";
			}

			return new HxFunctionDecl(name, vis, isStatic, args, returnTypeHint, outBody, retStr);
		}

		static function decodeStaticFinalPayload(payload:String):Null<HxFieldDecl> {
			// v=1 extension:
			// Payload format (after unescaping):
			//   name\nvis\nstatic\ntypehint\ninitexpr
			if (payload == null || payload.length == 0) return null;
			final lines = payload.split("\n");
			final name = lines.length > 0 ? lines[0] : "";
			if (name.length == 0) return null;
			final visLine = lines.length > 1 ? lines[1] : "public";
			final vis = visLine == "private" ? HxVisibility.Private : HxVisibility.Public;
			final isStatic = (lines.length > 2 ? lines[2] : "1") == "1";
			final typeHint = lines.length > 3 ? lines[3] : "";
			final initRaw = lines.length > 4 ? lines.slice(4).join("\n") : "";
			final init = initRaw.length > 0 ? parseReturnExprText(initRaw) : null;
			return new HxFieldDecl(name, vis, isStatic, typeHint, init);
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
			if (!StringTools.startsWith(t, "new")) return s;
			var norm = t;
			if (norm.length > 3) {
				final c3 = norm.charCodeAt(3);
				final isWs = c3 == " ".code || c3 == "\t".code || c3 == "\n".code || c3 == "\r".code;
				if (!isWs) norm = "new " + norm.substr(3);
			}
			if (!StringTools.startsWith(norm, "new ")) return norm;
			final lt = norm.indexOf("<");
			final lp = norm.indexOf("(");
			if (lt < 0 || lp < 0 || lt > lp) return s;
			var depth = 0;
			var i = lt;
			while (i < norm.length) {
				final c = norm.charCodeAt(i);
				if (c == "<".code) depth++;
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
		if (s.length == 0) return EUnsupported("<empty-return-expr>");

		// Regex literals: `~/.../flags` (Stage3 bring-up).
		//
		// Why
		// - Upstream std/macro code uses regex literals for pattern matching.
		// - Our bootstrap expression parser does not model regex syntax; attempting to parse it as
		//   a normal operator chain can produce structurally valid but nonsensical ASTs (and then
		//   invalid OCaml like arithmetic on strings).
		//
		// Bring-up rule
		// - Treat regex literals as unsupported expressions so downstream stages collapse them to
		//   `(Obj.magic 0)` and we can progress to the next missing semantic.
		if (StringTools.startsWith(s, "~/")) return EUnsupported("<regex-literal>");

		if (s == "null") return ENull;
		if (s == "true") return EBool(true);
		if (s == "false") return EBool(false);

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

			if (saw && i == s.length) return EInt(sign * value);
		}

		// Floats: best-effort via parseFloat if it contains '.'.
		if (s.indexOf(".") != -1) {
			final f = Std.parseFloat(s);
			if (!Math.isNaN(f)) return EFloat(f);
		}

		// Fallback: try to parse a small field/call chain (e.g. `Util.ping()`).
		return try {
			HxParser.parseExprText(s);
		} catch (_:Dynamic) {
			// Last resort: treat as unsupported so emitters don't attempt to print raw Haxe text as OCaml.
			EUnsupported(s);
		}
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
		if (colon <= 0) return "";
		final len = parseDecInt(s.substr(0, colon));
		if (len < 0) return "";
		final payload = s.substr(colon + 1);
		final raw = payload.substr(0, len);
		return unescapePayload(raw);
	}

	static function parseDecInt(s:String):Int {
		if (s == null) return -1;
		var i = 0;
		// Trim leading spaces (defensive).
		while (i < s.length && s.charCodeAt(i) == " ".code) i++;
		if (i >= s.length) return -1;
		var value = 0;
		var saw = false;
		while (i < s.length) {
			final c = s.charCodeAt(i);
			if (c < "0".code || c > "9".code) break;
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
					case "n".code: out.addChar("\n".code);
					case "r".code: out.addChar("\r".code);
					case "t".code: out.addChar("\t".code);
					case "\\".code: out.addChar("\\".code);
					case _: out.addChar(n);
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
				if (i > start) head.push(s.substr(start, i - start));
				while (i < s.length && s.charCodeAt(i) == " ".code) i++;
				start = i;
				continue;
			}
			i++;
		}
		while (head.length < n) head.push("");
		final tail = start <= s.length ? s.substr(start) : "";
		head.push(tail);
		return head;
	}
	#end
}
