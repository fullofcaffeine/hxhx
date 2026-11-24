package hxhxmacrohost;

import haxe.macro.Expr;
import hxhxmacrohost.MacroSyntaxWire.MacroSyntaxWireReader;
import hxhxmacrohost.MacroSyntaxWire.MacroSyntaxWireWriter;

/**
	Versioned requests from a plugin's `haxe.macro.Context` to the compiler, and their responses.

	Why
	- A project-macro plugin cannot type or parse source itself: the compiler owns defines,
	  positions, and the parser. hxhx's plugin `haxe.macro.Context` therefore sends one request
	  per service call through the native host (`HxHxMacroModuleHost.call_host`), and the
	  compiler answers it (`hxhx.macro.MacroContextHostServices`). Native code passes both
	  strings through unread.
	- Both sides compile this module, so the format has one owner. Expressions and positions
	  use the `MacroSyntaxWire` encoders.

	What
	- Request: the header line `hxhx-macro-context.v1`, the letter `C`, the message name, and its
	  arguments. Names in this version: `context.currentPos`, `context.defined` (name),
	  `context.definedValue` (name), `context.parse` (code, position), and
	  `context.parseInlineString` (code, position).
	- Response: `R` and the value (a position, a Bool, an optional String, or an expression), or
	  `E`, an error kind, a message, and an optional position. The kinds are `error` (a compile
	  error at that position, as `Context.error`), `unsupported` (the compiler does not provide
	  this service yet), and `invalid` (a malformed request).
	- Decoders on the plugin side turn an `error` into `MacroContextAbort` and any other failure
	  into a String thrown from the macro.

	Plain functions instead of an enum: plugin code is compiled by the Stage3 emitter, which has
	no enum payload representation for the opaque macro `Position` (haxe_ocaml-fmiag).
**/
class MacroContextWire {
	public static inline final VERSION:String = "hxhx-macro-context.v1";

	public static inline final CURRENT_POS:String = "context.currentPos";
	public static inline final DEFINED:String = "context.defined";
	public static inline final DEFINED_VALUE:String = "context.definedValue";
	public static inline final PARSE:String = "context.parse";
	public static inline final PARSE_INLINE_STRING:String = "context.parseInlineString";

	public static inline final ERROR:String = "error";
	public static inline final UNSUPPORTED:String = "unsupported";
	public static inline final INVALID:String = "invalid";

	// Requests (plugin side).

	public static function requestCurrentPos():String
		return request(CURRENT_POS).toString();

	public static function requestDefined(name:String):String {
		final writer = request(DEFINED);
		writer.string(name == null ? "" : name);
		return writer.toString();
	}

	public static function requestDefinedValue(name:String):String {
		final writer = request(DEFINED_VALUE);
		writer.string(name == null ? "" : name);
		return writer.toString();
	}

	/** `inlined` selects `parseInlineString`; otherwise `parse`. */
	public static function requestParse(code:String, position:Position, inlined:Bool):String {
		final writer = request(inlined ? PARSE_INLINE_STRING : PARSE);
		writer.string(code == null ? "" : code);
		writer.position(position);
		return writer.toString();
	}

	static function request(name:String):MacroSyntaxWireWriter {
		final writer = new MacroSyntaxWireWriter(VERSION, "C");
		writer.string(name);
		return writer;
	}

	// Request decoding (compiler side).

	/** The reader of a request, positioned after its message name, which `name` returns. */
	public static function openRequest(payload:String):{name:String, reader:MacroSyntaxWireReader} {
		final reader = new MacroSyntaxWireReader(VERSION, payload, "C");
		final name = reader.string();
		return {name: name, reader: reader};
	}

	// Responses (compiler side).

	public static function respondPosition(position:Position):String {
		final writer = new MacroSyntaxWireWriter(VERSION, "R");
		writer.position(position);
		return writer.toString();
	}

	public static function respondBool(value:Bool):String {
		final writer = new MacroSyntaxWireWriter(VERSION, "R");
		writer.bool(value);
		return writer.toString();
	}

	public static function respondOptionalString(value:Null<String>):String {
		final writer = new MacroSyntaxWireWriter(VERSION, "R");
		writer.optionalString(value);
		return writer.toString();
	}

	/** An expression; with `everyPosition`, each of its positions is written as that one. */
	public static function respondExpr(value:Expr, ?everyPosition:Position):String {
		final writer = new MacroSyntaxWireWriter(VERSION, "R");
		if (everyPosition != null)
			writer.useEveryPosition(everyPosition);
		writer.expr(value);
		return writer.toString();
	}

	public static function respondError(kind:String, message:String, ?position:Position):String {
		final writer = new MacroSyntaxWireWriter(VERSION, "E");
		writer.string(kind);
		writer.string(message == null ? "" : message);
		writer.optionalPosition(position);
		return writer.toString();
	}

	// Response decoding (plugin side).

	public static function readPosition(payload:String):Position {
		final reader = value(payload);
		final result = reader.position();
		reader.finish();
		return result;
	}

	public static function readBool(payload:String):Bool {
		final reader = value(payload);
		final result = reader.bool();
		reader.finish();
		return result;
	}

	public static function readOptionalString(payload:String):Null<String> {
		final reader = value(payload);
		final result = reader.optionalString();
		reader.finish();
		return result;
	}

	public static function readExpr(payload:String):Expr {
		final reader = value(payload);
		final result = reader.expr();
		reader.finish();
		return result;
	}

	/** The reader of an `R` response; an `E` response is thrown (see the class comment). */
	static function value(payload:String):MacroSyntaxWireReader {
		if (payload == null || payload.length == 0)
			throw "macro context: the compiler installed no macro context service for this call";
		if (StringTools.startsWith(payload, VERSION + "\nE")) {
			final reader = new MacroSyntaxWireReader(VERSION, payload, "E");
			final kind = reader.string();
			final message = reader.string();
			final position = reader.optionalPosition();
			reader.finish();
			if (kind == ERROR && position != null)
				throw new MacroContextAbort(message, position);
			throw "macro context: " + kind + ": " + message;
		}
		return new MacroSyntaxWireReader(VERSION, payload, "R");
	}
}
