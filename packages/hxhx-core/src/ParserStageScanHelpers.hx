/**
	Scanner helpers extracted from `ParserStage`.

	Why
	- `ParserStage` is a large compile unit in stage0 memory probes.
	- Keeping scanner logic in a dedicated module allows parity-aware A/B measurement
	  via `hxhx_stage0_no_parser_scan_extract` without behavior changes.

	How
	- Default path: `ParserStage` delegates helper scans to this module.
	- Profiling baseline path: `-D hxhx_stage0_no_parser_scan_extract` compiles and uses
	  the original inline scanner helpers in `ParserStage`.
**/
class ParserStageScanHelpers {
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
	public static function scanModuleLocalHelperClasses(source:String, mainClassName:Null<String>):Array<HxClassDecl> {
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
			if (t.text != "class")
				continue;

			// class <Name> ...
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
		- Correct enum runtime representation (tagging, reflection).
		- Enum abstracts (we treat `enum abstract` values as field/function stubs).
	**/
	public static function scanModuleLocalHelperEnums(source:String, mainTypeName:Null<String>):Array<HxClassDecl> {
		final out = new Array<HxClassDecl>();
		if (source == null || source.length == 0)
			return out;

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
						fields.push(new HxFieldDecl(ctorName, HxVisibility.Public, true, "Dynamic", null));
					} else {
						final args = new Array<HxFunctionArg>();
						for (a in argNames)
							args.push(new HxFunctionArg(a, "", HxDefaultValue.NoDefault, false, false));
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
	public static function scanModuleLocalHelperTypedefs(source:String, mainTypeName:Null<String>):Array<HxClassDecl> {
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
		- Captures fields/functions from the abstract body using the same
		  class-body scanner used for helper classes.

		How
		- Token-scans the source at brace depth 0.
		- Explicitly skips top-level `enum` / `enum abstract` blocks so `enum abstract`
		  declarations are not double-counted as regular abstracts.

		Limitations
		- Parses only the member signature/body subset needed for bring-up stubs.
		- Ignores advanced abstract semantics.
	**/
	public static function scanModuleLocalHelperAbstracts(source:String, mainTypeName:Null<String>):Array<HxClassDecl> {
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

	public static function scanEnumBodyForCtors(source:String, start:Int):{nextPos:Int, ctors:Array<{name:String, args:Array<String>}>} {
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

	public static function scanEnumAbstractBodyForValues(source:String, start:Int):{nextPos:Int, values:Array<String>} {
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

	public static function scanClassBodyForStatics(source:String, start:Int):{nextPos:Int, fields:Array<HxFieldDecl>, functions:Array<HxFunctionDecl>} {
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

					while (true) {
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

						if (depth != 1)
							continue;
						if (!wantName)
							continue;

						final name = ft.text;
						wantName = false;
						if (name == null || name.length == 0)
							continue;
						final initText = scanFieldInitializer(source, ft.nextPos);
						fields.push(new HxFieldDecl(name, fieldVis, wantStatic, "", parseSimpleInitExpr(initText)));
					}

					sawStatic = false;
					sawMacro = false;
					vis = HxVisibility.Public;
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

					final shouldCaptureBody = fnName == "new" || !wantStaticFn;
					final bodyCapture = scanFunctionBody(source, i, shouldCaptureBody);
					final body = shouldCaptureBody ? bodyCapture.body : [];
					final bodyText = shouldCaptureBody ? bodyCapture.bodyText : "";
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
			final exprText = StringTools.trim(source.substring(bodyStart >= 0 ? bodyStart : start, tok.nextPos - 1));
			if (exprText.length == 0)
				return {body: [], bodyText: "", nextPos: tok.nextPos};
			final bodyText = exprText + ";";
			var body = new Array<HxStmt>();
			try {
				body = HxParser.parseFunctionBodyText(bodyText);
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
				body = HxParser.parseFunctionBodyText(block.bodyText);
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

	static function hasUnsupportedStmtList(stmts:Array<HxStmt>):Bool {
		for (stmt in stmts)
			if (hasUnsupportedStmt(stmt))
				return true;
		return false;
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
			case EField(obj, _), ECall(obj, _), EUnop(_, obj), ECast(obj, _), EUntyped(obj):
				hasUnsupportedExpr(obj);
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
			case EArrayComprehension(_, iterable, yieldExpr): hasUnsupportedExpr(iterable) || hasUnsupportedExpr(yieldExpr);
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

	public static function scanNextToken(source:String, start:Int):{isIdent:Bool, text:String, nextPos:Int} {
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
}
