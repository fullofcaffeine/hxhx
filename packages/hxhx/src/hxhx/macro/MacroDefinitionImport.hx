package hxhx.macro;

import haxe.macro.Expr;
import hxhxmacrohost.MacroContextWire;

/**
	A type definition that hxhx cannot turn into parser declarations yet, or an invalid one.
	`MacroContextHostServices` reports it to the plugin as `unsupported` or `invalid`.
**/
class MacroDefinitionError {
	public final kind:String;
	public final message:String;

	public function new(kind:String, message:String) {
		this.kind = kind;
		this.message = message;
	}
}

/**
	Turn the type definitions of `Context.defineModule` and `Context.defineType` into one parsed
	module, built directly as parser declarations (no source text is rendered or parsed).

	Why
	- Upstream Haxe 4.3.7 types the definitions into a new module that depends on the calling
	  module (`src/typing/macroContext.ml`, `define_module` and `define_type`, lines 307-357).
	  hxhx gives the module to the request's macro pass (`MacroState.defineModule`), which adds it
	  to the modules the request types, so later code such as `new spec.TestAlpha()` finds it.

	What
	- `TDClass` becomes an `HxClassDecl`: the superclass, interfaces (or extended interfaces for an
	  interface), `isExtern`, and metadata, with parameters written as source.
	- `FFun` becomes an `HxFunctionDecl`. Its body is the imported expression as one statement, as
	  the parser stores `function f() <expr>`. `FVar` and `FProp` become an `HxFieldDecl`.
	- Access: `APublic` and `APrivate` set the visibility (private by default, as upstream);
	  `AStatic` and `AFinal` set their flags. `AInline`, `ADynamic`, `AMacro`, `AExtern`,
	  `AAbstract`, and `AOverload` become metadata, as the parser records them. `AOverride` is
	  dropped, as the parser drops it.
	- Imports and usings become module directives (`INormal`, `IAsName`, `IAll`, `using`).
	- Not yet, each as `unsupported`: other kinds (`TDEnum`, `TDStructure`, `TDAlias`,
	  `TDAbstract`, `TDField`), type parameters, abstract classes, and metadata parameters that are not
	  a constant, path, call, array, or object literal.
	  Types whose package differs from the module path are `invalid`.
	- Positions: syntax the macro built keeps no source position yet (`haxe_ocaml-9sj5p.2`).
**/
class MacroDefinitionImport {
	/**
		The parsed module `modulePath` with these types. `callFile` is the file of the macro call;
		the module gets its own synthetic file name so that it never shares a file with another
		module.
	**/
	public static function module(modulePath:String, types:Array<TypeDefinition>, imports:Null<Array<ImportExpr>>, usings:Null<Array<TypePath>>,
			callFile:String):ResolvedModule {
		final segments = modulePath == null ? [] : modulePath.split(".");
		if (segments.length == 0 || segments.filter(segment -> segment.length == 0).length > 0)
			throw new MacroDefinitionError(MacroContextWire.INVALID, "`" + modulePath + "` is not a module path");
		if (types == null || types.length == 0)
			throw new MacroDefinitionError(MacroContextWire.INVALID, "module `" + modulePath + "` defines no types");
		final packagePath = segments.slice(0, segments.length - 1).join(".");
		final moduleName = segments[segments.length - 1];
		final importer = new MacroSyntaxImport(new MacroSyntaxPositions(callFile));
		final classes = new Array<HxClassDecl>();
		for (definition in types) {
			final pack = definition.pack == null ? "" : definition.pack.join(".");
			if (pack != packagePath)
				throw new MacroDefinitionError(MacroContextWire.INVALID,
					"type `"
					+ definition.name
					+ "` has package `"
					+ pack
					+ "`, but module `"
					+ modulePath
					+ "` is in package `"
					+ packagePath
					+ "`");
			classes.push(classOf(definition, importer));
		}
		final directives = new Array<HxModuleDirective>();
		if (imports != null)
			for (entry in imports)
				directives.push(directiveOf(entry));
		if (usings != null)
			for (path in usings)
				directives.push(HxModuleDirective.usingDirective(MacroSyntaxImport.typePathText(path)));
		var main = classes[0];
		for (candidate in classes)
			if (HxClassDecl.getName(candidate) == moduleName)
				main = candidate;
		final declaration = new HxModuleDecl(packagePath, directives, main, classes, false, false);
		final filePath = "<defined>/" + segments.join("/") + ".hx";
		return new ResolvedModule(modulePath, filePath, new ParsedModule("", declaration, filePath));
	}

	static function classOf(definition:TypeDefinition, importer:MacroSyntaxImport):HxClassDecl {
		final name = definition.name;
		if (definition.params != null && definition.params.length > 0)
			throw unsupported("type parameters of defined type `" + name + "`");
		final metadata = metadataOf(definition.meta, "type `" + name + "`");
		return switch definition.kind {
			case TDClass(superClass, interfaces, isInterface, _, isAbstract):
				if (isAbstract == true)
					throw unsupported("abstract defined class `" + name + "`");
				final interfacePaths = interfaces == null ? [] : [for (path in interfaces) MacroSyntaxImport.typePathText(path)];
				final functions = new Array<HxFunctionDecl>();
				final fields = new Array<HxFieldDecl>();
				for (field in definition.fields)
					memberOf(field, name, importer, functions, fields);
				new HxClassDecl(name, false, functions, fields, superClass == null ? null : MacroSyntaxImport.typePathText(superClass), metadata,
					isInterface == true, isInterface == true ? [] : interfacePaths, HxVisibility.Public, isInterface == true ? interfacePaths : [],
					definition.isExtern == true);
			case TDEnum | TDStructure | TDAlias(_) | TDAbstract(_, _, _, _) | TDField(_, _):
				throw unsupported("defined type `" + name + "` of kind " + kindName(definition.kind) + "; only classes (`TDClass`) are defined yet");
		};
	}

	static function memberOf(field:Field, owner:String, importer:MacroSyntaxImport, functions:Array<HxFunctionDecl>, fields:Array<HxFieldDecl>):Void {
		final label = "field `" + owner + "." + field.name + "`";
		var visibility = HxVisibility.Private;
		var isStatic = false;
		var isFinal = false;
		final metadata = metadataOf(field.meta, label);
		if (field.access != null)
			for (access in field.access)
				switch access {
					case APublic:
						visibility = HxVisibility.Public;
					case APrivate:
						visibility = HxVisibility.Private;
					case AStatic:
						isStatic = true;
					case AFinal:
						isFinal = true;
					case AOverride:
					case AInline:
						metadata.push("inline");
					case ADynamic:
						metadata.push("dynamic");
					case AMacro:
						metadata.push("macro");
					case AExtern:
						metadata.push("extern");
					case AAbstract:
						metadata.push("abstract");
					case AOverload:
						metadata.push("overload");
				}
		switch field.kind {
			case FFun(f):
				if (f.params != null && f.params.length > 0)
					throw unsupported("type parameters of " + label);
				final args = [
					for (argument in f.args)
						new HxFunctionArg(argument.name, argument.type == null ? "" : MacroSyntaxImport.typeText(argument.type),
							argument.value == null ? HxDefaultValue.NoDefault : HxDefaultValue.Default(importer.result(argument.value)), argument.opt == true,
							false, "", metadataOf(argument.meta, "argument `" + argument.name + "` of " + label))
				];
				final body = f.expr == null ? [] : [HxStmt.SExpr(importer.result(f.expr), HxPos.unknown())];
				functions.push(new HxFunctionDecl(field.name, visibility, isStatic, args, f.ret == null ? "" : MacroSyntaxImport.typeText(f.ret), body, "",
					metadata, HxPos.unknown(), HxPos.unknown(), "", f.expr != null, false, false));
			case FVar(type, value):
				fields.push(new HxFieldDecl(field.name, visibility, isStatic, type == null ? "" : MacroSyntaxImport.typeText(type),
					value == null ? null : importer.result(value), metadata, HxPos.unknown(), HxPos.unknown(), isFinal, "", "", ""));
			case FProp(get, set, type, value):
				fields.push(new HxFieldDecl(field.name, visibility, isStatic, type == null ? "" : MacroSyntaxImport.typeText(type),
					value == null ? null : importer.result(value), metadata, HxPos.unknown(), HxPos.unknown(), isFinal, get, set, ""));
		}
	}

	/**
		Metadata entries in the parser's text form: `@name`, or `@name(a, b)` with each parameter
		written as source. The parser keeps a metadata entry as its source text
		(`HxParser.parseMetadataText`); upstream decodes each parameter as an expression
		(`decode_meta_entry`, `src/macro/macroApi.ml` lines 792-795).
	**/
	static function metadataOf(meta:Null<Metadata>, label:String):Array<String> {
		final out = new Array<String>();
		if (meta != null)
			for (entry in meta) {
				if (entry.params == null || entry.params.length == 0) {
					out.push("@" + entry.name);
					continue;
				}
				final what = "a parameter of metadata `@" + entry.name + "` on " + label;
				out.push("@" + entry.name + "(" + [for (param in entry.params) metadataParameter(param, what)].join(", ") + ")");
			}
		return out;
	}

	/**
		A metadata parameter as source text, for the expressions metadata uses: constants,
		identifiers and field paths, calls (`@:build(Macro.build())`), arrays, objects, negation, and
		parentheses. Any other expression is `unsupported`.
	**/
	static function metadataParameter(param:Null<Expr>, what:String):String {
		if (param == null || param.expr == null)
			throw unsupported(what + " is empty");
		final text = (value:Expr) -> metadataParameter(value, what);
		return switch param.expr {
			case EConst(CInt(value, suffix)) if (suffix == null): value;
			case EConst(CFloat(value, suffix)) if (suffix == null): value;
			case EConst(CString(value, SingleQuotes)) if (value.indexOf("$") >= 0):
				throw unsupported(what + " is a single-quoted string with interpolation");
			case EConst(CString(value, SingleQuotes)): "'" + escapeString(value, "'") + "'";
			case EConst(CString(value, _)): "\"" + escapeString(value, "\"") + "\"";
			case EConst(CIdent(name)): name;
			case EConst(CRegexp(pattern, options)): "~/" + pattern + "/" + options;
			case EField(owner, field, kind): text(owner) + (kind == Safe ? "?." : ".") + field;
			case ECall(callee, arguments): text(callee) + "(" + [for (argument in arguments) text(argument)].join(", ") + ")";
			case EArrayDecl(values): "[" + [for (value in values) text(value)].join(", ") + "]";
			case EObjectDecl(fields):
				"{" + [
					for (field in fields)
						(field.quotes == Quoted ? "\"" + escapeString(field.field, "\"") + "\"" : field.field) + ": " + text(field.expr)
				].join(", ") + "}";
			case EUnop(OpNeg, false, value): "-" + text(value);
			case EUnop(OpNot, false, value): "!" + text(value);
			case EParenthesis(value): "(" + text(value) + ")";
			case _: throw unsupported(what + " is not a constant, path, call, array, or object literal");
		};
	}

	/** `value` as the text between `quote` characters, with Haxe's string escapes. */
	static function escapeString(value:String, quote:String):String {
		final out = new StringBuf();
		for (index in 0...value.length) {
			final c = value.charAt(index);
			out.add(switch c {
				case "\\": "\\\\";
				case "\n": "\\n";
				case "\r": "\\r";
				case "\t": "\\t";
				case _ if (c == quote): "\\" + c;
				case _: c;
			});
		}
		return out.toString();
	}

	static function directiveOf(entry:ImportExpr):HxModuleDirective {
		final path = [for (part in entry.path) part.name].join(".");
		return switch entry.mode {
			case INormal: HxModuleDirective.normalImport(path);
			case IAsName(alias): HxModuleDirective.aliasImport(path, alias);
			case IAll: HxModuleDirective.wildcardImport(path);
		};
	}

	static function kindName(kind:TypeDefKind):String {
		return switch kind {
			case TDEnum: "TDEnum";
			case TDStructure: "TDStructure";
			case TDClass(_, _, _, _, _): "TDClass";
			case TDAlias(_): "TDAlias";
			case TDAbstract(_, _, _, _): "TDAbstract";
			case TDField(_, _): "TDField";
		};
	}

	static function unsupported(what:String):MacroDefinitionError
		return new MacroDefinitionError(MacroContextWire.UNSUPPORTED, what + " is not supported in hxhx yet");
}
