package hxhx.macro;

import haxe.macro.Expr;
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
				case other:
					return MacroContextWire.respondError(MacroContextWire.UNSUPPORTED, "Context service `" + other + "` is not available in hxhx yet");
			}
		} catch (error:String) {
			return MacroContextWire.respondError(MacroContextWire.INVALID, error);
		}
	}

	/**
		The services of one selected call: its file, the start of its first argument (when known),
		and the compilation's defines in `MacroState`.
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
			}
		};
	}

	/** Upstream's define name conversion: `-` becomes `_`. */
	static function defineName(name:String):String
		return name == null ? "" : StringTools.replace(name, "-", "_");
}
