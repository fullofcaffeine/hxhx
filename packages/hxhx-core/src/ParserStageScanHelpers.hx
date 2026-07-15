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
		- This scanner only discovers module-local `class` / `interface` declarations.
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
		var pendingTypeMetadata = new Array<String>();
		function scanTopLevelMetadataText(startPos:Int):{text:String, nextPos:Int} {
			var j = startPos;
			final colon = scanNextToken(source, j);
			if (colon.text == ":")
				j = colon.nextPos;
			final head = scanNextToken(source, j);
			if (!head.isIdent || head.text.length == 0)
				return {text: "", nextPos: startPos};
			final parts = [head.text];
			j = head.nextPos;
			while (true) {
				final dot = scanNextToken(source, j);
				if (dot.text != ".")
					break;
				final segment = scanNextToken(source, dot.nextPos);
				if (!segment.isIdent || segment.text.length == 0)
					break;
				parts.push(".");
				parts.push(segment.text);
				j = segment.nextPos;
			}
			final next = scanNextToken(source, j);
			if (next.text != "(")
				return {text: parts.join(""), nextPos: j};
			parts.push("(");
			j = next.nextPos;
			var depth = 1;
			while (depth > 0) {
				final tok = scanNextToken(source, j);
				if (tok.text.length == 0)
					return {text: parts.join(""), nextPos: j};
				j = tok.nextPos;
				parts.push(tok.text);
				if (tok.text == "(") {
					depth += 1;
				} else if (tok.text == ")") {
					depth -= 1;
				}
			}
			return {text: parts.join(""), nextPos: j};
		}
		while (true) {
			final t = scanNextToken(source, i);
			i = t.nextPos;
			if (t.text.length == 0)
				break;

			if (!t.isIdent) {
				if (braceDepth == 0 && t.text == "@") {
					final meta = scanTopLevelMetadataText(i);
					if (meta.text.length > 0)
						pendingTypeMetadata.push(meta.text);
					i = meta.nextPos;
				} else if (t.text == "{")
					braceDepth += 1;
				else if (t.text == "}")
					braceDepth = braceDepth > 0 ? (braceDepth - 1) : 0;
				continue;
			}

			if (braceDepth != 0)
				continue;
			if (t.text != "class" && t.text != "interface") {
				if (t.text == "private" || t.text == "extern" || t.text == "final")
					continue;
				pendingTypeMetadata = [];
				continue;
			}
			final classMetadata = pendingTypeMetadata.copy();
			pendingTypeMetadata = [];

			// class/interface <Name> ...
			var nameTok = scanNextToken(source, i);
			// Skip stray symbols/metadata between `class` and the identifier.
			while (nameTok.text.length > 0 && !nameTok.isIdent)
				nameTok = scanNextToken(source, nameTok.nextPos);
			if (!nameTok.isIdent || nameTok.text.length == 0)
				continue;

			final className = nameTok.text;
			final isInterface = t.text == "interface";
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

			final metadata = classMetadata.concat(typeParamsMetadata(header.typeParams));
			if (shouldRecord)
				out.push(new HxClassDecl(className, false, scanned.functions, scanned.fields, header.extendsPath, metadata, isInterface,
					header.implementsPaths));
		}

		return out;
	}

	public static function scanModuleStaticFields(source:String):Array<HxFieldDecl> {
		final out = new Array<HxFieldDecl>();
		if (source == null || source.length == 0)
			return out;

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
			if (t.text != "final" && t.text != "var")
				continue;

			var nameTok = scanNextToken(source, i);
			while (nameTok.text.length > 0 && !nameTok.isIdent)
				nameTok = scanNextToken(source, nameTok.nextPos);
			if (!nameTok.isIdent || nameTok.text.length == 0)
				continue;

			final name = nameTok.text;
			final initText = scanFieldInitializer(source, nameTok.nextPos);
			out.push(new HxFieldDecl(name, HxVisibility.Public, true, "", parseModuleStaticInitExpr(initText), [], null, null, t.text == "final", "", "",
				initText));
			i = scanFieldDeclarationEnd(source, nameTok.nextPos);
		}

		return out;
	}

	static function scanClassHeader(source:String, start:Int):{
		bodyStart:Int,
		nextPos:Int,
		extendsPath:String,
		implementsPaths:Array<String>,
		typeParams:Array<String>
	} {
		var extendsPath = "";
		var mode = "";
		var genericDepth = 0;
		var path = "";
		final implementsPaths = new Array<String>();
		final typeParams = scanTypeParameterNames(source, start);
		function flushPath():Void {
			if (path.length == 0 || mode.length == 0)
				return;
			if (mode == "extends")
				extendsPath = path;
			else if (mode == "implements")
				implementsPaths.push(path);
			path = "";
		}

		var tok = scanNextToken(source, typeParams.nextPos);
		while (tok.text.length > 0 && tok.text != "{") {
			if (tok.isIdent) {
				if (genericDepth == 0 && (tok.text == "extends" || tok.text == "implements")) {
					flushPath();
					mode = tok.text;
				} else if (mode.length > 0) {
					path += tok.text;
				}
			} else if (mode.length > 0) {
				switch (tok.text) {
					case ".":
						path += ".";
					case "<":
						path += "<";
						genericDepth += 1;
					case ">":
						if (genericDepth > 0) {
							path += ">";
							genericDepth -= 1;
						}
					case ",":
						if (genericDepth == 0) {
							flushPath();
							if (mode == "extends")
								mode = "";
						} else {
							path += ",";
						}
					case _:
						if (genericDepth == 0) {
							flushPath();
							mode = "";
						} else {
							path += tok.text;
						}
				}
			}
			tok = scanNextToken(source, tok.nextPos);
		}

		flushPath();
		return {
			bodyStart: tok.text == "{" ? tok.nextPos : -1,
			nextPos: tok.nextPos,
			extendsPath: extendsPath,
			implementsPaths: implementsPaths,
			typeParams: typeParams.params
		};
	}

	static function typeParamsMetadata(params:Array<String>):Array<String> {
		return params == null || params.length == 0 ? [] : ["__hxhx_type_params=" + params.join(",")];
	}

	static function functionTypeParamsMetadata(source:String, start:Int, end:Int):Array<String> {
		return end <= start ? [] : HxFunctionTypeParamMetadata.fromGenericText(source.substring(start, end));
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
	public static function scanModuleLocalHelperEnums(source:String, mainTypeName:Null<String>):Array<HxClassDecl> {
		final out = new Array<HxClassDecl>();
		if (source == null || source.length == 0)
			return out;

		function enumRuntimeValue(enumName:String, ctorName:String, ctorIndex:Int, argExprs:Array<HxExpr>):HxExpr {
			return EAnon(["__hx_enum", "__hx_ctor", "__hx_index", "__hx_params"],
				[EString(enumName), EString(ctorName), EInt(ctorIndex), EArrayDecl(argExprs)]);
		}

		inline function isUpperStart(name:String):Bool {
			if (name == null || name.length == 0)
				return false;
			final c = name.charCodeAt(0);
			return c >= "A".code && c <= "Z".code;
		}

		function scanTopLevelMetadataText(startPos:Int):{text:String, nextPos:Int} {
			var j = startPos;
			final colon = scanNextToken(source, j);
			if (colon.text == ":")
				j = colon.nextPos;
			final head = scanNextToken(source, j);
			if (!head.isIdent || head.text.length == 0)
				return {text: "", nextPos: startPos};
			final parts = [head.text];
			j = head.nextPos;
			while (true) {
				final dot = scanNextToken(source, j);
				if (dot.text != ".")
					break;
				final segment = scanNextToken(source, dot.nextPos);
				if (!segment.isIdent || segment.text.length == 0)
					break;
				parts.push(".");
				parts.push(segment.text);
				j = segment.nextPos;
			}
			final next = scanNextToken(source, j);
			if (next.text != "(")
				return {text: parts.join(""), nextPos: j};
			parts.push("(");
			j = next.nextPos;
			var depth = 1;
			while (depth > 0) {
				final tok = scanNextToken(source, j);
				if (tok.text.length == 0)
					return {text: parts.join(""), nextPos: j};
				j = tok.nextPos;
				parts.push(tok.text);
				if (tok.text == "(") {
					depth += 1;
				} else if (tok.text == ")") {
					depth -= 1;
				}
			}
			return {text: parts.join(""), nextPos: j};
		}

		final seen:Map<String, Bool> = new Map();
		if (mainTypeName != null && mainTypeName.length > 0)
			seen.set(mainTypeName, true);

		var braceDepth = 0;
		var i = 0;
		var pendingTypeMetadata = new Array<String>();

		while (true) {
			final t = scanNextToken(source, i);
			i = t.nextPos;
			if (t.text.length == 0)
				break;

			if (!t.isIdent) {
				if (braceDepth == 0 && t.text == "@") {
					final meta = scanTopLevelMetadataText(i);
					if (meta.text.length > 0)
						pendingTypeMetadata.push(meta.text);
					i = meta.nextPos;
				} else if (t.text == "{")
					braceDepth += 1;
				else if (t.text == "}")
					braceDepth = braceDepth > 0 ? (braceDepth - 1) : 0;
				continue;
			}

			if (braceDepth != 0)
				continue;
			if (t.text != "enum") {
				if (t.text == "private" || t.text == "extern")
					continue;
				pendingTypeMetadata = [];
				continue;
			}
			final enumMetadata = pendingTypeMetadata.copy();
			pendingTypeMetadata = [];

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

			final fields = isEnumAbstract ? [] : [new HxFieldDecl("__hx_is_enum", HxVisibility.Public, true, "Bool", EBool(true))];
			final functions = new Array<HxFunctionDecl>();
			if (isEnumAbstract) {
				final scanned = scanEnumAbstractBodyForValues(source, headerTok.nextPos);
				i = scanned.nextPos;
				for (field in scanned.fields)
					fields.push(field);
			} else {
				final scanned = scanEnumBodyForCtors(source, headerTok.nextPos);
				i = scanned.nextPos;
				fields.push(new HxFieldDecl("__hx_enum_ctors", HxVisibility.Public, true, "Dynamic",
					EArrayDecl([for (ctor in scanned.ctors) EString(ctor.name)])));
				for (ctorIndex in 0...scanned.ctors.length) {
					final ctor = scanned.ctors[ctorIndex];
					if (ctor == null)
						continue;
					final ctorName = ctor.name;
					if (ctorName == null || ctorName.length == 0)
						continue;
					final ctorArgs = ctor.args == null ? [] : ctor.args;
					if (ctorArgs.length == 0) {
						fields.push(new HxFieldDecl(ctorName, HxVisibility.Public, true, "Dynamic", enumRuntimeValue(enumName, ctorName, ctorIndex, []),
							ctor.metadata));
					} else {
						final args = new Array<HxFunctionArg>();
						final values = new Array<HxExpr>();
						for (a in ctorArgs)
							args.push(new HxFunctionArg(a.name, a.typeHint, HxDefaultValue.NoDefault, a.isOptional, false));
						for (a in ctorArgs)
							values.push(EIdent(a.name));
						// Constructors conceptually return an enum value; during bring-up we keep the
						// type wide to avoid OCaml type errors in heavily-`Obj.magic` codegen.
						functions.push(new HxFunctionDecl(ctorName, HxVisibility.Public, true, args, "Dynamic", [
							SReturn(enumRuntimeValue(enumName, ctorName, ctorIndex, values), HxPos.unknown())
						], "", ctor.metadata));
					}
				}
			}

			final classMetadata = isEnumAbstract ? enumMetadata.concat(["__hxhx_abstract"]) : enumMetadata;
			out.push(new HxClassDecl(enumName, false, functions, fields, "", classMetadata));
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
		- Emits a type provider (`HxClassDecl`) for the alias name.
		- For simple anonymous-object typedefs, preserves field names and type hints so
		  target backends can emit the structural surface instead of an empty nominal
		  placeholder.

			How
			- Uses the same lightweight token scanner as other module-local helpers.
			- Tracks brace depth and only records declarations at depth 0.

		Limitations
		- Models only top-level anonymous-object typedef fields.
		- Does not model typedef expressions, generics, method fields, or complex
		  structural constraints.
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
			final typeParams = scanTypeParameterNames(source, i);
			i = typeParams.nextPos;

			final scanned = scanTypedefShape(source, i);
			i = scanned.nextPos;
			final metadata = typeParams.params.length == 0 ? ["__hxhx_typedef"] : ["__hxhx_typedef", "__hxhx_type_params=" + typeParams.params.join(",")];
			out.push(new HxClassDecl(typeName, false, [], scanned.fields, "", metadata));
		}

		return out;
	}

	static function scanTypeParameterNames(source:String, start:Int):{nextPos:Int, params:Array<String>} {
		final params = new Array<String>();
		final first = scanNextToken(source, start);
		if (first.text != "<")
			return {nextPos: start, params: params};
		var i = first.nextPos;
		var depth = 1;
		var expectingName = true;
		while (true) {
			final tok = scanNextToken(source, i);
			i = tok.nextPos;
			if (tok.text.length == 0)
				return {nextPos: i, params: params};
			switch (tok.text) {
				case "<":
					depth += 1;
				case "-":
					final next = scanNextToken(source, i);
					if (next.text == ">")
						i = next.nextPos;
				case ">":
					depth -= 1;
					if (depth <= 0)
						return {nextPos: i, params: params};
				case "," if (depth == 1):
					expectingName = true;
				case ":" if (depth == 1):
					expectingName = false;
				case _:
					if (depth == 1 && expectingName && tok.isIdent) {
						params.push(tok.text);
						expectingName = false;
					}
			}
		}
	}

	static function scanTypedefShape(source:String, start:Int):{nextPos:Int, fields:Array<HxFieldDecl>} {
		var i = start;
		while (true) {
			final tok = scanNextToken(source, i);
			i = tok.nextPos;
			if (tok.text.length == 0)
				return {nextPos: i, fields: []};
			if (tok.text == ";")
				return {nextPos: i, fields: []};
			if (tok.text != "=")
				continue;

			return scanTypedefRhsShape(source, i);
		}
	}

	static function scanTypedefRhsShape(source:String, start:Int):{nextPos:Int, fields:Array<HxFieldDecl>} {
		var i = start;
		var parenDepth = 0;
		var angleDepth = 0;
		while (true) {
			final tok = scanNextToken(source, i);
			i = tok.nextPos;
			if (tok.text.length == 0 || (tok.text == ";" && parenDepth == 0 && angleDepth == 0))
				return {nextPos: i, fields: []};
			switch (tok.text) {
				case "{" if (parenDepth == 0 && angleDepth == 0):
					return scanAnonymousTypedefFields(source, tok.nextPos);
				case "(" | "[":
					parenDepth += 1;
				case ")" | "]":
					if (parenDepth > 0)
						parenDepth -= 1;
				case "<":
					angleDepth += 1;
				case ">":
					if (angleDepth > 0)
						angleDepth -= 1;
				case _:
			}
		}
	}

	static function skipTypedefDeclaration(source:String, start:Int):{nextPos:Int, fields:Array<HxFieldDecl>} {
		var i = start;
		var depth = 0;
		while (true) {
			final tok = scanNextToken(source, i);
			i = tok.nextPos;
			if (tok.text.length == 0 || (tok.text == ";" && depth == 0))
				return {nextPos: i, fields: []};
			switch (tok.text) {
				case "(" | "[" | "{":
					depth += 1;
				case ")" | "]" | "}":
					if (depth > 0)
						depth -= 1;
				case "<":
					depth += 1;
				case ">":
					if (depth > 0)
						depth -= 1;
				case _:
			}
		}
	}

	static function scanAnonymousTypedefFields(source:String, start:Int):{nextPos:Int, fields:Array<HxFieldDecl>} {
		final fields = new Array<HxFieldDecl>();
		var i = start;
		var depth = 1;
		while (true) {
			var tok = scanNextToken(source, i);
			i = tok.nextPos;
			if (tok.text.length == 0)
				return {nextPos: i, fields: fields};
			if (!tok.isIdent) {
				switch (tok.text) {
					case "@" if (depth == 1):
						i = skipMetadataPayload(source, i);
					case "{":
						depth += 1;
					case "}":
						depth -= 1;
						if (depth <= 0)
							return {nextPos: i, fields: fields};
					case _:
				}
				continue;
			}
			if (depth != 1)
				continue;
			while (isTypedefFieldModifier(tok.text)) {
				tok = scanNextToken(source, i);
				i = tok.nextPos;
			}
			if (tok.text == "var" || tok.text == "final") {
				tok = scanNextFieldNameToken(source, i);
				i = tok.nextPos;
			}
			if (tok.text == "function") {
				final end = skipTypedefField(source, i);
				i = end.nextPos;
				if (end.closed)
					return {nextPos: i, fields: fields};
				continue;
			}
			if (!tok.isIdent || tok.text.length == 0)
				continue;
			final typeHint = scanFieldTypeHint(source, tok.nextPos);
			fields.push(new HxFieldDecl(tok.text, HxVisibility.Public, false, typeHint, null));
			final end = skipTypedefField(source, tok.nextPos);
			i = end.nextPos;
			if (end.closed)
				return {nextPos: i, fields: fields};
		}
	}

	static function skipMetadataPayload(source:String, start:Int):Int {
		var i = start;
		final colon = scanNextToken(source, i);
		if (colon.text == ":")
			i = colon.nextPos;
		var tok = scanNextToken(source, i);
		if (!tok.isIdent || tok.text.length == 0)
			return start;
		i = tok.nextPos;
		while (true) {
			final dot = scanNextToken(source, i);
			if (dot.text != ".")
				break;
			final segment = scanNextToken(source, dot.nextPos);
			if (!segment.isIdent || segment.text.length == 0)
				break;
			i = segment.nextPos;
		}
		tok = scanNextToken(source, i);
		if (tok.text != "(")
			return i;
		i = tok.nextPos;
		var depth = 1;
		while (depth > 0) {
			tok = scanNextToken(source, i);
			if (tok.text.length == 0)
				return i;
			i = tok.nextPos;
			switch (tok.text) {
				case "(":
					depth += 1;
				case ")":
					depth -= 1;
				case _:
			}
		}
		return i;
	}

	static function scanNextFieldNameToken(source:String, start:Int):{
		text:String,
		startPos:Int,
		nextPos:Int,
		isIdent:Bool
	} {
		var i = start;
		while (true) {
			final tok = scanNextToken(source, i);
			i = tok.nextPos;
			if (tok.text == "?")
				continue;
			return tok;
		}
	}

	static function isTypedefFieldModifier(text:String):Bool {
		return text == "public" || text == "private" || text == "static" || text == "inline" || text == "dynamic" || text == "overload" || text == "extern";
	}

	static function skipTypedefField(source:String, start:Int):{nextPos:Int, closed:Bool} {
		var i = start;
		var depth = 0;
		while (true) {
			final tok = scanNextToken(source, i);
			i = tok.nextPos;
			if (tok.text.length == 0)
				return {nextPos: i, closed: false};
			switch (tok.text) {
				case "(" | "[" | "{":
					depth += 1;
				case ")" | "]":
					if (depth > 0)
						depth -= 1;
				case "}":
					if (depth == 0)
						return {nextPos: i, closed: true};
					depth -= 1;
				case "<":
					depth += 1;
				case ">":
					if (depth > 0)
						depth -= 1;
				case "," | ";":
					if (depth == 0)
						return {nextPos: i, closed: false};
				case _:
			}
		}
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
			final abstractUnderlying = scanAbstractUnderlyingType(source, i);

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

			if (shouldRecord) {
				final metadata = ["__hxhx_abstract"];
				if (abstractUnderlying.length > 0)
					metadata.push("__hxhx_abstract_underlying=" + abstractUnderlying);
				out.push(new HxClassDecl(abstractName, false, functions, fields, "", metadata));
			}
		}

		return out;
	}

	static function scanAbstractUnderlyingType(source:String, start:Int):String {
		var open = scanNextToken(source, start);
		if (open.text == "<") {
			var depth = 1;
			var i = open.nextPos;
			while (depth > 0) {
				final tok = scanNextToken(source, i);
				if (tok.text.length == 0)
					return "";
				i = tok.nextPos;
				if (tok.text == "<")
					depth += 1;
				else if (tok.text == ">")
					depth -= 1;
			}
			open = scanNextToken(source, i);
		}
		if (open.text != "(")
			return "";
		final parts = new Array<String>();
		var depth = 1;
		var i = open.nextPos;
		while (depth > 0) {
			final tok = scanNextToken(source, i);
			if (tok.text.length == 0)
				return "";
			i = tok.nextPos;
			if (tok.text == "(") {
				depth += 1;
			} else if (tok.text == ")") {
				depth -= 1;
				if (depth <= 0)
					break;
			}
			parts.push(tok.text);
		}
		return StringTools.trim(parts.join(""));
	}

	public static function scanEnumBodyForCtors(source:String,
			start:Int):{nextPos:Int, ctors:Array<{name:String, args:Array<{name:String, typeHint:String, isOptional:Bool}>, metadata:Array<String>}>} {
		final ctors = new Array<{name:String, args:Array<{name:String, typeHint:String, isOptional:Bool}>, metadata:Array<String>}>();

		var depth = 1; // we start just after `{`
		var i = start;
		var pendingMetadata = new Array<String>();

		function scanMetadataText(startPos:Int):{text:String, nextPos:Int} {
			var j = startPos;
			final colon = scanNextToken(source, j);
			if (colon.text == ":")
				j = colon.nextPos;
			final head = scanNextToken(source, j);
			if (!head.isIdent || head.text.length == 0)
				return {text: "", nextPos: startPos};
			final parts = [head.text];
			j = head.nextPos;
			final next = scanNextToken(source, j);
			if (next.text != "(")
				return {text: parts.join(""), nextPos: j};
			parts.push("(");
			j = next.nextPos;
			var parenDepth = 1;
			while (parenDepth > 0) {
				final tok = scanNextToken(source, j);
				if (tok.text.length == 0)
					return {text: parts.join(""), nextPos: j};
				j = tok.nextPos;
				parts.push(tok.text);
				if (tok.text == "(") {
					parenDepth += 1;
				} else if (tok.text == ")") {
					parenDepth -= 1;
				}
			}
			return {text: parts.join(""), nextPos: j};
		}

		function scanFunctionParamListOpen(startPos:Int):{text:String, nextPos:Int, tokenPos:Int} {
			var j = startPos;
			var parenDepth = 0;
			var bracketDepth = 0;
			var braceDepth = 0;
			var angleDepth = 0;
			while (true) {
				final tokenPos = j;
				final tok = scanNextToken(source, j);
				if (tok.text.length == 0)
					return {text: tok.text, nextPos: tok.nextPos, tokenPos: tokenPos};
				final atTop = parenDepth == 0 && bracketDepth == 0 && braceDepth == 0 && angleDepth == 0;
				if (atTop && tok.text == "(")
					return {text: tok.text, nextPos: tok.nextPos, tokenPos: tokenPos};
				if (atTop && (tok.text == "{" || tok.text == ";" || tok.text == "="))
					return {text: tok.text, nextPos: tok.nextPos, tokenPos: tokenPos};
				j = tok.nextPos;
				switch (tok.text) {
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
					case _:
				}
			}
		}

		function scanParamTypeHint(startPos:Int):{hint:String, nextPos:Int} {
			final colon = scanNextToken(source, startPos);
			if (colon.text != ":")
				return {hint: "", nextPos: startPos};
			final parts = new Array<String>();
			var j = colon.nextPos;
			var parenDepth = 0;
			var bracketDepth = 0;
			var braceDepth = 0;
			var angleDepth = 0;
			while (true) {
				final tok = scanNextToken(source, j);
				if (tok.text.length == 0)
					return {hint: parts.join(""), nextPos: j};
				final atTop = parenDepth == 0 && bracketDepth == 0 && braceDepth == 0 && angleDepth == 0;
				if (atTop && (tok.text == "," || tok.text == ")" || tok.text == "="))
					return {hint: parts.join(""), nextPos: j};
				parts.push(tok.text);
				j = tok.nextPos;
				switch (tok.text) {
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
					case _:
				}
			}
		}

		while (true) {
			final t = scanNextToken(source, i);
			i = t.nextPos;
			if (t.text.length == 0)
				break;

			if (!t.isIdent) {
				switch (t.text) {
					case "@":
						if (depth == 1) {
							final meta = scanMetadataText(i);
							if (meta.text.length > 0)
								pendingMetadata.push(meta.text);
							i = meta.nextPos;
						}
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
			final ctorName = t.text;
			final ctorArgs = new Array<{name:String, typeHint:String, isOptional:Bool}>();
			final ctorMetadata = pendingMetadata.copy();
			pendingMetadata = [];

			// Optional `(a:T, b:U)` parameter list.
			final nt = scanFunctionParamListOpen(i);
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
					final typeHint = scanParamTypeHint(i);
					i = typeHint.nextPos;
					ctorArgs.push({name: argName, typeHint: typeHint.hint, isOptional: pendingOptional});
					argIndex += 1;
					expectArg = false;
					pendingOptional = false;
					pendingRest = false;
				}
			}

			ctors.push({name: ctorName, args: ctorArgs, metadata: ctorMetadata});

			// Consume tokens until the terminating `;` so we don't interpret type names
			// as additional constructors.
			var tailParenDepth = 0;
			var tailBracketDepth = 0;
			var tailAngleDepth = 0;
			while (true) {
				final tt = scanNextToken(source, i);
				i = tt.nextPos;
				if (tt.text.length == 0)
					break;
				if (!tt.isIdent) {
					switch (tt.text) {
						case "(":
							tailParenDepth += 1;
						case ")":
							if (tailParenDepth > 0)
								tailParenDepth -= 1;
						case "[":
							tailBracketDepth += 1;
						case "]":
							if (tailBracketDepth > 0)
								tailBracketDepth -= 1;
						case "<":
							tailAngleDepth += 1;
						case ">":
							if (tailAngleDepth > 0)
								tailAngleDepth -= 1;
						case "{":
							depth += 1;
						case "}":
							depth -= 1;
							if (depth <= 0)
								break;
						case ";" | ",":
							if (depth == 1 && tailParenDepth == 0 && tailBracketDepth == 0 && tailAngleDepth == 0)
								break;
						case _:
					}
				}
			}
		}

		return {nextPos: i, ctors: ctors};
	}

	public static function scanEnumAbstractBodyForValues(source:String, start:Int):{nextPos:Int, fields:Array<HxFieldDecl>} {
		final fields = new Array<HxFieldDecl>();

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
			if (!isUpperStart(name))
				continue;

			var init:Null<HxExpr> = null;
			var scanPos = i;
			var initStart = -1;
			var parenDepth = 0;
			var bracketDepth = 0;
			var braceDepthInInit = 0;
			while (true) {
				final valueTok = scanNextToken(source, scanPos);
				if (valueTok.text.length == 0) {
					i = scanPos;
					break;
				}
				scanPos = valueTok.nextPos;
				if (parenDepth == 0 && bracketDepth == 0 && braceDepthInInit == 0 && valueTok.text == "=" && initStart < 0) {
					initStart = valueTok.nextPos;
					continue;
				}
				if (parenDepth == 0 && bracketDepth == 0 && braceDepthInInit == 0 && (valueTok.text == ";" || valueTok.text == ",")) {
					if (initStart >= 0)
						init = parseSimpleInitExpr(source.substring(initStart, valueTok.startPos));
					i = valueTok.nextPos;
					break;
				}
				switch (valueTok.text) {
					case "(":
						parenDepth += 1;
					case ")":
						parenDepth = parenDepth > 0 ? parenDepth - 1 : 0;
					case "[":
						bracketDepth += 1;
					case "]":
						bracketDepth = bracketDepth > 0 ? bracketDepth - 1 : 0;
					case "{":
						braceDepthInInit += 1;
					case "}":
						if (braceDepthInInit > 0) {
							braceDepthInInit -= 1;
						} else {
							if (initStart >= 0)
								init = parseSimpleInitExpr(source.substring(initStart, valueTok.startPos));
							i = valueTok.nextPos;
							depth -= 1;
							break;
						}
					case _:
				}
			}
			var fieldInit:HxExpr = EInt(0);
			if (init != null)
				fieldInit = init;
			fields.push(new HxFieldDecl(name, HxVisibility.Public, true, "Dynamic", fieldInit));
		}

		return {nextPos: i, fields: fields};
	}

	public static function scanClassBodyForStatics(source:String, start:Int):{nextPos:Int, fields:Array<HxFieldDecl>, functions:Array<HxFunctionDecl>} {
		final fields = new Array<HxFieldDecl>();
		final functions = new Array<HxFunctionDecl>();

		var depth = 1; // we start just after `{`
		var i = start;

		var sawStatic = false;
		var sawMacro = false;
		var sawOverload = false;
		var sawDynamic = false;
		var pendingMetadata = new Array<String>();
		var vis:HxVisibility = HxVisibility.Private;
		var declarationStart = -1;

		function noteDeclarationStart(index:Int):Void {
			if (declarationStart < 0)
				declarationStart = index;
		}

		function scanMetadataText(startPos:Int):{text:String, nextPos:Int} {
			var j = startPos;
			final colon = scanNextToken(source, j);
			if (colon.text == ":")
				j = colon.nextPos;
			final head = scanNextToken(source, j);
			if (!head.isIdent || head.text.length == 0)
				return {text: "", nextPos: startPos};
			final parts = [head.text];
			j = head.nextPos;
			final next = scanNextToken(source, j);
			if (next.text != "(")
				return {text: parts.join(""), nextPos: j};
			parts.push("(");
			j = next.nextPos;
			var depth = 1;
			while (depth > 0) {
				final tok = scanNextToken(source, j);
				if (tok.text.length == 0)
					return {text: parts.join(""), nextPos: j};
				j = tok.nextPos;
				parts.push(tok.text);
				if (tok.text == "(") {
					depth += 1;
				} else if (tok.text == ")") {
					depth -= 1;
				}
			}
			return {text: parts.join(""), nextPos: j};
		}

		function scanTypeHintUntil(startPos:Int, stopAtComma:Bool, stopAtUntypedBodyModifier:Bool = false):{hint:String, nextPos:Int} {
			final parts = new Array<String>();
			var j = startPos;
			var parenDepth = 0;
			var bracketDepth = 0;
			var braceDepth = 0;
			var angleDepth = 0;
			while (true) {
				final tok = scanNextToken(source, j);
				if (tok.text.length == 0)
					return {hint: parts.join(""), nextPos: j};
				final atTop = parenDepth == 0 && bracketDepth == 0 && braceDepth == 0 && angleDepth == 0;
				if (atTop && tok.isIdent && tok.text == "return")
					return {hint: parts.join(""), nextPos: j};
				if (atTop && tok.isIdent && expressionBodyKeywordStartsWithoutReturn(tok.text))
					return {hint: parts.join(""), nextPos: j};
				// Source-native helper scans keep type hints as token text. A return
				// signature may put `untyped` on the line before the body; that token
				// belongs to the body modifier, not to the return type.
				if (atTop && stopAtUntypedBodyModifier && tok.isIdent && tok.text == "untyped")
					return {hint: parts.join(""), nextPos: tok.nextPos};
				final startsStructuralType = atTop && tok.text == "{" && parts.length == 0;
				if (atTop
					&& (tok.text == ")"
						|| tok.text == "="
						|| (tok.text == "{" && !startsStructuralType)
						|| tok.text == ";"
						|| (stopAtComma && tok.text == ",")))
					return {hint: parts.join(""), nextPos: j};
				parts.push(tok.text);
				j = tok.nextPos;
				switch (tok.text) {
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
					case _:
				}
			}
			return {hint: parts.join(""), nextPos: j};
		}

		function scanDefaultValueUntil(startPos:Int):{text:String, nextPos:Int} {
			final parts = new Array<String>();
			var j = startPos;
			var parenDepth = 0;
			var bracketDepth = 0;
			var braceDepth = 0;
			while (true) {
				final tok = scanNextToken(source, j);
				if (tok.text.length == 0)
					return {text: StringTools.trim(parts.join("")), nextPos: j};
				final atTop = parenDepth == 0 && bracketDepth == 0 && braceDepth == 0;
				if (atTop && (tok.text == "," || tok.text == ")" || tok.text == "{" || tok.text == ";"))
					return {text: StringTools.trim(parts.join("")), nextPos: j};
				parts.push(tok.text);
				j = tok.nextPos;
				switch (tok.text) {
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
					case _:
				}
			}
		}

		function scanFunctionParamListOpen(startPos:Int):{
			isIdent:Bool,
			text:String,
			nextPos:Int,
			startPos:Int
		} {
			var j = startPos;
			var parenDepth = 0;
			var bracketDepth = 0;
			var braceDepth = 0;
			var angleDepth = 0;
			while (true) {
				final tok = scanNextToken(source, j);
				if (tok.text.length == 0)
					return tok;
				final atTop = parenDepth == 0 && bracketDepth == 0 && braceDepth == 0 && angleDepth == 0;
				if (atTop && tok.text == "(")
					return tok;
				if (atTop && (tok.text == "{" || tok.text == ";" || tok.text == "="))
					return tok;
				j = tok.nextPos;
				switch (tok.text) {
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
					case _:
				}
			}
		}

		function scannedDefaultValueFromText(text:String):HxDefaultValue {
			final trimmed = StringTools.trim(text == null ? "" : text);
			if (trimmed.length == 0)
				return HxDefaultValue.NoDefault;
			if (trimmed == "null")
				return HxDefaultValue.Default(HxExpr.ENull);
			if (trimmed == "true")
				return HxDefaultValue.Default(HxExpr.EBool(true));
			if (trimmed == "false")
				return HxDefaultValue.Default(HxExpr.EBool(false));
			if ((StringTools.startsWith(trimmed, "\"") && StringTools.endsWith(trimmed, "\""))
				|| (StringTools.startsWith(trimmed, "'") && StringTools.endsWith(trimmed, "'")))
				return HxDefaultValue.Default(HxExpr.EString(trimmed.substr(1, trimmed.length - 2)));
			final intValue = Std.parseInt(trimmed);
			if (intValue != null && Std.string(intValue) == trimmed)
				return HxDefaultValue.Default(HxExpr.EInt(intValue));
			return HxDefaultValue.Default(HxExpr.ENull);
		}

		while (true) {
			final t = scanNextToken(source, i);
			i = t.nextPos;
			if (t.text.length == 0)
				break;

			if (!t.isIdent) {
				switch (t.text) {
					case "@":
						if (depth == 1) {
							final meta = scanMetadataText(i);
							if (meta.text.length > 0)
								pendingMetadata.push(meta.text);
							i = meta.nextPos;
						}
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
							sawOverload = false;
							sawDynamic = false;
							pendingMetadata = [];
							declarationStart = -1;
							vis = HxVisibility.Private;
						}
					case _:
				}
				continue;
			}

			if (depth != 1)
				continue;

			switch (t.text) {
				case "public":
					noteDeclarationStart(t.startPos);
					vis = HxVisibility.Public;
				case "private":
					noteDeclarationStart(t.startPos);
					vis = HxVisibility.Private;
				case "static":
					noteDeclarationStart(t.startPos);
					sawStatic = true;
				case "macro":
					noteDeclarationStart(t.startPos);
					sawMacro = true;
				case "overload":
					noteDeclarationStart(t.startPos);
					sawOverload = true;
				case "dynamic":
					noteDeclarationStart(t.startPos);
					sawDynamic = true;
				case "inline" | "extern" | "override":
					// Keep scanning; these can appear between `static` and the declaration keyword.
					noteDeclarationStart(t.startPos);
				case "var" | "final":
					noteDeclarationStart(t.startPos);
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
						final accessors = scanFieldPropertyAccessors(source, ft.nextPos);
						final typeHint = scanFieldTypeHint(source, ft.nextPos);
						final initText = scanFieldInitializer(source, ft.nextPos);
						fields.push(new HxFieldDecl(name, fieldVis, wantStatic, typeHint, parseModuleStaticInitExpr(initText), pendingMetadata.copy(),
							posFromIndex(source, declarationStart), posFromIndex(source, scanFieldDeclarationEnd(source, ft.nextPos)), t.text == "final",
							accessors.getter, accessors.setter, initText));
					}

					sawStatic = false;
					sawMacro = false;
					sawOverload = false;
					sawDynamic = false;
					pendingMetadata = [];
					declarationStart = -1;
					vis = HxVisibility.Private;
					if (depth <= 0)
						break;
				case "function":
					noteDeclarationStart(t.startPos);
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
					final functionTypeParamsStart = i;
					final functionTypeParams = scanTypeParameterNames(source, i);
					i = functionTypeParams.nextPos;

					// Seek `(` for the parameter list while skipping generic type-parameter
					// constraints such as `<A:{x:Int} & {y:Float}>`.
					final sigTok = scanFunctionParamListOpen(i);

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
							var argType = "";
							var defaultValue:HxDefaultValue = HxDefaultValue.NoDefault;
							var defaultValueText = "";
							final colonTok = scanNextToken(source, i);
							if (colonTok.text == ":") {
								final scannedType = scanTypeHintUntil(colonTok.nextPos, true);
								argType = scannedType.hint;
								i = scannedType.nextPos;
							}
							final defaultTok = scanNextToken(source, i);
							if (defaultTok.text == "=") {
								final scannedDefault = scanDefaultValueUntil(defaultTok.nextPos);
								defaultValueText = scannedDefault.text;
								defaultValue = scannedDefaultValueFromText(defaultValueText);
								i = scannedDefault.nextPos;
							}
							args.push(new HxFunctionArg(argName, argType, defaultValue, pendingOptional, pendingRest, defaultValueText));
							argIndex += 1;
							expectArg = false;
							pendingOptional = false;
							pendingRest = false;
						}
					} else {
						i = sigTok.startPos;
					}

					var returnType = "";
					final returnTok = scanNextToken(source, i);
					if (returnTok.text == ":") {
						final scannedReturn = scanTypeHintUntil(returnTok.nextPos, false, true);
						returnType = scannedReturn.hint;
						i = scannedReturn.nextPos;
					}

					final bodyCapture = scanFunctionBody(source, i, true);
					final keepBody = fnName == "new" || !wantStaticFn || sawDynamic || scannedStaticBodyIsSafe(fnName, bodyCapture.body);
					final body = keepBody ? bodyCapture.body : [];
					final bodyText = (keepBody || fnName == "__init__") ? bodyCapture.bodyText : "";
					if (bodyCapture.nextPos > i)
						i = bodyCapture.nextPos;

					if (fnName.length > 0) {
						final metadata = pendingMetadata.copy()
							.concat(functionTypeParamsMetadata(source, functionTypeParamsStart, functionTypeParams.nextPos));
						if (sawMacro)
							metadata.push("macro");
						if (sawOverload)
							metadata.push("overload");
						if (sawDynamic)
							metadata.push("dynamic");
						functions.push(new HxFunctionDecl(fnName, fnVis, wantStaticFn, args, returnType, body, "", metadata,
							posFromIndex(source, declarationStart), posFromIndex(source, i), bodyText));
					}

					sawStatic = false;
					sawMacro = false;
					sawOverload = false;
					sawDynamic = false;
					pendingMetadata = [];
					declarationStart = -1;
					vis = HxVisibility.Private;
				case _:
			}
		}

		return {nextPos: i, fields: fields, functions: functions};
	}

	/**
		Convert a lightweight scanner offset into the same 1-based source position
		shape produced by `HxParser`, so native-parser enrichment can report
		diagnostics against scanned helper declarations instead of line 0.
	**/
	static function posFromIndex(source:String, index:Int):HxPos {
		if (source == null || index < 0 || index > source.length)
			return HxPos.unknown();
		var line = 1;
		var lineStart = 0;
		var i = 0;
		while (i < index) {
			final c = source.charCodeAt(i);
			i += 1;
			if (c == "\n".code) {
				line += 1;
				lineStart = i;
			}
		}
		return new HxPos(index, line, index - lineStart + 1);
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

	static function scanFieldPropertyAccessors(source:String, start:Int):{getter:String, setter:String} {
		final open = scanNextToken(source, start);
		if (open.text != "(")
			return {getter: "", setter: ""};
		final getter = scanNextToken(source, open.nextPos);
		if (getter.text.length == 0 || !getter.isIdent)
			return {getter: "", setter: ""};
		final comma = scanNextToken(source, getter.nextPos);
		if (comma.text != ",")
			return {getter: "", setter: ""};
		final setter = scanNextToken(source, comma.nextPos);
		if (setter.text.length == 0 || !setter.isIdent)
			return {getter: "", setter: ""};
		final close = scanNextToken(source, setter.nextPos);
		if (close.text != ")")
			return {getter: "", setter: ""};
		return {getter: getter.text, setter: setter.text};
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

	static function scanFieldDeclarationEnd(source:String, start:Int):Int {
		var i = start;
		var parenDepth = 0;
		var bracketDepth = 0;
		var braceDepth = 0;
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
						return i;
					braceDepth -= 1;
				case ";".code:
					if (parenDepth == 0 && bracketDepth == 0 && braceDepth == 0)
						return i + 1;
				case _:
			}
			i += 1;
		}
		return i;
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
		return null;
	}

	static function parseModuleStaticInitExpr(raw:String):Null<HxExpr> {
		final simple = parseSimpleInitExpr(raw);
		if (simple != null)
			return simple;
		final text = raw == null ? "" : StringTools.trim(raw);
		if (text.length == 0)
			return null;
		if (StringTools.startsWith(text, "untyped ") || StringTools.startsWith(text, "if "))
			return null;
		try {
			final expr = HxParser.parseExprText(text);
			return hasUnsupportedExpr(expr) ? null : expr;
		} catch (_:HxParseError) {
			return null;
		} catch (_:String) {
			return null;
		}
	}

	static function scanFunctionBody(source:String, start:Int, capture:Bool = true):{body:Array<HxStmt>, bodyText:String, nextPos:Int} {
		var i = start;
		var bodyStart = -1;
		var tok = scanNextToken(source, i);
		while (tok.text.length > 0 && tok.text != "{" && tok.text != ";") {
			if (tok.isIdent && tok.text == "return" && bodyStart < 0) {
				bodyStart = tok.nextPos - tok.text.length;
			} else if (bodyStart < 0 && expressionBodyKeywordStartsWithoutReturn(tok.text)) {
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
			return {body: body, bodyText: bodyText, nextPos: tok.nextPos};
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
		return {body: body, bodyText: block.bodyText, nextPos: block.nextPos};
	}

	static function expressionBodyKeywordStartsWithoutReturn(text:String):Bool {
		return switch (text) {
			case "for":
				true;
			case _:
				false;
		}
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
		// Keep scanned static helper bodies only when they are linear and every
		// statement is understood by the current source-native lowering path.
		for (stmt in stmts) {
			switch (stmt) {
				case SVar(_, _, init, _):
					if (hasUnsupportedExpr(init))
						return false;
				case SExpr(expr, _):
					if (hasUnsupportedExpr(expr))
						return false;
				case SReturn(expr, _):
					if (hasUnsupportedExpr(expr))
						return false;
				case _:
					return false;
			}
		}
		return switch (stmts[stmts.length - 1]) {
			case SReturn(_, _):
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
			case EField(obj, _), EUnop(_, _, obj), ECast(obj, _), EUntyped(obj):
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

	public static function scanNextToken(source:String, start:Int):{
		isIdent:Bool,
		text:String,
		nextPos:Int,
		startPos:Int
	} {
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
				final startString = i;
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
				return {
					isIdent: false,
					text: source.substr(startString, i - startString),
					nextPos: i,
					startPos: startString
				};
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
				return {
					isIdent: true,
					text: source.substr(startIdent, i - startIdent),
					nextPos: i,
					startPos: startIdent
				};
			}

			// Ellipsis
			if (c == ".".code && i + 2 < len && source.charCodeAt(i + 1) == ".".code && source.charCodeAt(i + 2) == ".".code) {
				return {
					isIdent: false,
					text: "...",
					nextPos: i + 3,
					startPos: i
				};
			}

			// Single-char symbol
			return {
				isIdent: false,
				text: String.fromCharCode(c),
				nextPos: i + 1,
				startPos: i
			};
		}

		return {
			isIdent: false,
			text: "",
			nextPos: len,
			startPos: len
		};
	}
}
