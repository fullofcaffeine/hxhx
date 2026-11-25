package hxhx.macro;

import haxe.macro.Expr;
import hxhx.macro.MacroDefinitionImport.MacroDefinitionError;
import hxhxmacrohost.MacroContextWire;

/**
	The compiler's answers to the Context requests of one macro call.

	Each field is one `haxe.macro.Context` service of `hxhx-macro-context.v1`. A plugin sends the
	request through the native host; `MacroContextHostServices.handle` decodes it, calls the
	field, and encodes the answer.
**/
typedef MacroContextServices = {
	/** The position of the macro call. */
	final currentPos:() -> Position;

	/** Whether the compilation defines `name`, after upstream's `-` to `_` conversion. */
	final defined:(name:String) -> Bool;

	/** The value of define `name`, or `null` when it is not defined. */
	final definedValue:(name:String) -> Null<String>;

	/** One expression parsed from `code`; throws `MacroContextParseError` for invalid code. */
	final parse:(code:String, position:Position) -> Expr;

	/**
		Add module `modulePath` with these types to the request; throws `MacroDefinitionError` for a
		definition hxhx cannot build yet or an invalid one.
	**/
	final defineModule:(modulePath:String, types:Array<TypeDefinition>, imports:Null<Array<ImportExpr>>, usings:Null<Array<TypePath>>) -> Void;
}

/** Invalid code given to `Context.parse` or `Context.parseInlineString`. */
class MacroContextParseError {
	public final message:String;

	public function new(message:String) {
		this.message = message;
	}
}

/**
	Answer plugin Context requests (`hxhx-macro-context.v1`) for one selected macro call.

	The services follow upstream Haxe 4.3.7 (`src/macro/macroApi.ml`):
	- `defined` and `definedValue` read the compilation's defines after `-` becomes `_`
	  (`Common.external_defined`, `src/context/common.ml`, lines 454-463); an undefined value is
	  `null`. They are the calling compilation's defines, including the target's (`sys`,
	  `target.*`), as upstream's macro API uses `ctx.com` (`MacroState.contextDefined`).
	- `parse` and `parseInlineString` apply conditional compilation (`#if`, `#elseif`, `#else`,
	  `#end`) to the text with those defines, as upstream's lexer does.
	- `parse` gives every node of the parsed syntax the position the macro passed.
	  `parseInlineString` does the same for now; upstream places each node inside the string,
	  which waits on per-node source ranges (`haxe_ocaml-9sj5p.2`).
	- `currentPos` is the call's file and the start of its first argument when the parser
	  recorded one. Upstream gives the whole call's range; that also waits on `haxe_ocaml-9sj5p.2`.
	- `defineModule` and `defineType` build parser declarations (`MacroDefinitionImport`) and queue
	  the module for the request (`MacroState.defineModule`); the expression macro pass types it.
	  `defineType` defines module `pack.name`, as upstream does.

	A failure never escapes as an exception: invalid code is an `error` at the given position, a
	service this version does not provide is `unsupported`, and a malformed request is `invalid`.
**/
class MacroContextHostServices {
	/** Answer one encoded request with one encoded response. */
	public static function handle(services:MacroContextServices, request:String):String {
		try {
			final opened = MacroContextWire.openRequest(request);
			final reader = opened.reader;
			switch opened.name {
				case MacroContextWire.CURRENT_POS:
					reader.finish();
					return MacroContextWire.respondPosition(services.currentPos());
				case MacroContextWire.DEFINED:
					final name = reader.string();
					reader.finish();
					return MacroContextWire.respondBool(services.defined(name));
				case MacroContextWire.DEFINED_VALUE:
					final name = reader.string();
					reader.finish();
					return MacroContextWire.respondOptionalString(services.definedValue(name));
				case MacroContextWire.PARSE | MacroContextWire.PARSE_INLINE_STRING:
					final code = reader.string();
					final position = reader.position();
					reader.finish();
					try {
						return MacroContextWire.respondExpr(services.parse(code, position), position);
					} catch (error:MacroContextParseError) {
						return MacroContextWire.respondError(MacroContextWire.ERROR, error.message, position);
					}
				case MacroContextWire.DEFINE_MODULE:
					final modulePath = reader.string();
					final types = reader.typeDefinitions();
					final imports = reader.optionalImportExprs();
					final usings = reader.optionalTypePaths();
					reader.finish();
					return define(() -> services.defineModule(modulePath, types, imports, usings), types);
				case MacroContextWire.DEFINE_TYPE:
					final definition = reader.typeDefinition();
					// Upstream records `moduleDependency` for its module cache; a defined module has none here.
					reader.optionalString();
					reader.finish();
					final pack = definition.pack == null ? [] : definition.pack;
					return define(() -> services.defineModule(pack.concat([definition.name]).join("."), [definition], null, null), [definition]);
				case other:
					return MacroContextWire.respondError(MacroContextWire.UNSUPPORTED, "Context service `" + other + "` is not available in hxhx yet");
			}
		} catch (error:String) {
			return MacroContextWire.respondError(MacroContextWire.INVALID, error);
		}
	}

	/** Run one definition; its failure is answered at the first type's position. */
	static function define(run:() -> Void, types:Array<TypeDefinition>):String {
		final position = types.length > 0 ? types[0].pos : null;
		try {
			run();
		} catch (error:MacroDefinitionError) {
			return MacroContextWire.respondError(error.kind, error.message, error.kind == MacroContextWire.ERROR ? position : null);
		}
		return MacroContextWire.respondUnit();
	}

	/**
		The services of one selected call: its file, the start of its first argument (when known),
		the compilation's defines in `MacroState`, and the modules it defines (`MacroState.defineModule`).
	**/
	public static function forCall(filePath:String, anchor:Null<HxPos>):MacroContextServices {
		return {
			currentPos: () -> {
				final start = anchor == null || !MacroSyntaxPositions.isKnown(anchor) ? 0 : anchor.getIndex();
				final position:Position = {file: filePath, min: start, max: start};
				return position;
			},
			defined: name -> MacroState.contextDefined(defineName(name)),
			definedValue: name -> MacroState.contextDefinedValue(defineName(name)),
			parse: (code, position) -> {
				// Upstream's lexer evaluates `#if` in the text with the same defines (haxe_ocaml-w1zmu).
				// The filter keeps every offset, so positions inside the text stay where they were.
				final active = HxConditionalCompilation.filterSource(code, MacroState.contextDefines());
				final parsed = try {
					HxParser.parseExprText(active);
				} catch (error:HxParseError) {
					throw new MacroContextParseError(error.message);
				} catch (error:String) {
					throw new MacroContextParseError(error);
				}
				final exporter = new MacroSyntaxExport(new MacroSyntaxPositions(position.file.length > 0 ? position.file : filePath));
				return try {
					exporter.quotation(parsed, position);
				} catch (error:String) {
					throw new MacroContextParseError(error);
				}
			},
			defineModule: (modulePath, types, imports, usings) -> {
				final module = try {
					MacroDefinitionImport.module(modulePath, types, imports, usings, filePath);
				} catch (error:String) {
					// The importer rejects syntax it has no parser form for yet.
					throw new MacroDefinitionError(MacroContextWire.UNSUPPORTED, error);
				}
				try {
					MacroState.defineModule(module);
				} catch (error:String) {
					throw new MacroDefinitionError(MacroContextWire.INVALID, error);
				}
			}
		};
	}

	/** Upstream's define name conversion: `-` becomes `_`. */
	static function defineName(name:String):String
		return name == null ? "" : StringTools.replace(name, "-", "_");
}
