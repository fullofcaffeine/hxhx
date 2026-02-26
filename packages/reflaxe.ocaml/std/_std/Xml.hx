/**
	OCaml target override for `Xml`.

	Why this exists
	- Upstream `Xml` delegates parsing/printing to `haxe.xml.Parser` and
	  `haxe.xml.Printer`.
	- In the OCaml backend we emit one OCaml module per Haxe module. If `Xml.ml`
	  depends on `haxe_xml_Parser.ml` / `haxe_xml_Printer.ml` and those modules
	  also depend back on `Xml.ml`, dune sees a circular dependency graph and
	  stops with a compile-time module-cycle error.
	- This override keeps the needed Xml parse/print behavior in one module so the
	  generated OCaml module graph is acyclic.

	Current scope
	- Preserve the core `Xml` node API and string rendering behavior.
	- Keep `toString()` self-contained in this module.
	- Provide a self-contained `parse()` for core document/element/pcdata behavior.
	- Full parity edge cases are tracked separately (see stdlib parity follow-ups).
**/
enum abstract XmlType(Int) {
	var Element = 0;
	var PCData = 1;
	var CData = 2;
	var Comment = 3;
	var DocType = 4;
	var ProcessingInstruction = 5;
	var Document = 6;

	public function toString():String {
		return switch (cast this : XmlType) {
			case Element: "Element";
			case PCData: "PCData";
			case CData: "CData";
			case Comment: "Comment";
			case DocType: "DocType";
			case ProcessingInstruction: "ProcessingInstruction";
			case Document: "Document";
		};
	}
}

class Xml {
	static public var Element(get, never):XmlType;
	static public var PCData(get, never):XmlType;
	static public var CData(get, never):XmlType;
	static public var Comment(get, never):XmlType;
	static public var DocType(get, never):XmlType;
	static public var ProcessingInstruction(get, never):XmlType;
	static public var Document(get, never):XmlType;

	static var elementValue(default, never):XmlType = cast(untyped __ocaml__("(Obj.repr 0)"));
	static var pcDataValue(default, never):XmlType = cast(untyped __ocaml__("(Obj.repr 1)"));
	static var cDataValue(default, never):XmlType = cast(untyped __ocaml__("(Obj.repr 2)"));
	static var commentValue(default, never):XmlType = cast(untyped __ocaml__("(Obj.repr 3)"));
	static var docTypeValue(default, never):XmlType = cast(untyped __ocaml__("(Obj.repr 4)"));
	static var processingInstructionValue(default, never):XmlType = cast(untyped __ocaml__("(Obj.repr 5)"));
	static var documentValue(default, never):XmlType = cast(untyped __ocaml__("(Obj.repr 6)"));

	static inline function get_Element():XmlType
		return elementValue;

	static inline function get_PCData():XmlType
		return pcDataValue;

	static inline function get_CData():XmlType
		return cDataValue;

	static inline function get_Comment():XmlType
		return commentValue;

	static inline function get_DocType():XmlType
		return docTypeValue;

	static inline function get_ProcessingInstruction():XmlType
		return processingInstructionValue;

	static inline function get_Document():XmlType
		return documentValue;

	static public function parse(source:String):Xml {
		final state = new XmlParseState(source);
		return parseDocument(state);
	}

	public var nodeType(default, null):XmlType;
	@:isVar public var nodeName(get, set):String;
	@:isVar public var nodeValue(get, set):String;
	public var parent(default, null):Xml;

	var children:Array<Dynamic>;
	var attributeMap:haxe.ds.StringMap<String>;

	function get_nodeName():String {
		if (nodeType != Element) {
			throw "Bad node type, expected Element";
		}
		return nodeName;
	}

	function set_nodeName(v:String):String {
		if (nodeType != Element) {
			throw "Bad node type, expected Element";
		}
		return this.nodeName = v;
	}

	function get_nodeValue():String {
		if (nodeType == Document || nodeType == Element) {
			throw "Bad node type, unexpected node kind";
		}
		return nodeValue;
	}

	function set_nodeValue(v:String):String {
		if (nodeType == Document || nodeType == Element) {
			throw "Bad node type, unexpected node kind";
		}
		return this.nodeValue = v;
	}

	static public function createElement(name:String):Xml {
		var xml = new Xml(Element);
		xml.nodeName = name;
		return xml;
	}

	static public function createPCData(data:String):Xml {
		var xml = new Xml(PCData);
		xml.nodeValue = data;
		return xml;
	}

	static public function createCData(data:String):Xml {
		var xml = new Xml(CData);
		xml.nodeValue = data;
		return xml;
	}

	static public function createComment(data:String):Xml {
		var xml = new Xml(Comment);
		xml.nodeValue = data;
		return xml;
	}

	static public function createDocType(data:String):Xml {
		var xml = new Xml(DocType);
		xml.nodeValue = data;
		return xml;
	}

	static public function createProcessingInstruction(data:String):Xml {
		var xml = new Xml(ProcessingInstruction);
		xml.nodeValue = data;
		return xml;
	}

	static public function createDocument():Xml {
		return new Xml(Document);
	}

	public function get(att:String):String {
		if (nodeType != Element) {
			throw "Bad node type, expected Element";
		}
		return attributeMap.get(att);
	}

	public function set(att:String, value:String):Void {
		if (nodeType != Element) {
			throw "Bad node type, expected Element";
		}
		attributeMap.set(att, value);
	}

	public function remove(att:String):Void {
		if (nodeType != Element) {
			throw "Bad node type, expected Element";
		}
		attributeMap.remove(att);
	}

	public function exists(att:String):Bool {
		if (nodeType != Element) {
			throw "Bad node type, expected Element";
		}
		return attributeMap.exists(att);
	}

	public function attributes():Iterator<String> {
		if (nodeType != Element) {
			throw "Bad node type, expected Element";
		}
		return attributeMap.keys();
	}

	public function iterator():Iterator<Xml> {
		ensureElementType();
		return cast children.iterator();
	}

	public function elements():Iterator<Xml> {
		ensureElementType();
		var ret:Array<Xml> = [];
		for (childValue in children) {
			final child:Xml = cast childValue;
			if (child.nodeType == Element) {
				ret.push(child);
			}
		}
		return cast ret.iterator();
	}

	public function elementsNamed(name:String):Iterator<Xml> {
		ensureElementType();
		var ret:Array<Xml> = [];
		for (childValue in children) {
			final child:Xml = cast childValue;
			if (child.nodeType == Element && child.nodeName == name) {
				ret.push(child);
			}
		}
		return cast ret.iterator();
	}

	public function firstChild():Xml {
		ensureElementType();
		return cast children[0];
	}

	public function firstElement():Xml {
		ensureElementType();
		for (childValue in children) {
			final child:Xml = cast childValue;
			if (child.nodeType == Element) {
				return child;
			}
		}
		return null;
	}

	public function addChild(x:Xml):Void {
		ensureElementType();
		if (x.parent != null) {
			x.parent.removeChild(x);
		}
		final xDyn:Dynamic = untyped __ocaml__("x");
		children.push(xDyn);
		x.parent = this;
	}

	public function removeChild(x:Xml):Bool {
		ensureElementType();
		final xDyn:Dynamic = untyped __ocaml__("x");
		if (children.remove(xDyn)) {
			x.parent = null;
			return true;
		}
		return false;
	}

	public function insertChild(x:Xml, pos:Int):Void {
		ensureElementType();
		final xDyn:Dynamic = untyped __ocaml__("x");
		if (x.parent != null) {
			x.parent.children.remove(xDyn);
		}
		children.insert(pos, xDyn);
		x.parent = this;
	}

	public function toString():String {
		var output = new StringBuf();
		writeNode(this, "", output, false);
		return output.toString();
	}

	private static function writeNode(value:Xml, tabs:String, output:StringBuf, pretty:Bool):Void {
		if (value.nodeType == CData) {
			output.add(tabs + "<![CDATA[");
			output.add(value.nodeValue);
			output.add("]]>");
			if (pretty)
				output.add("\n");
		} else if (value.nodeType == Comment) {
			var commentContent = value.nodeValue;
			commentContent = ~/[\n\r\t]+/g.replace(commentContent, "");
			commentContent = "<!--" + commentContent + "-->";
			output.add(tabs);
			output.add(StringTools.trim(commentContent));
			if (pretty)
				output.add("\n");
		} else if (value.nodeType == Document) {
			var i = 0;
			while (i < value.children.length) {
				final child:Xml = cast value.children[i];
				writeNode(child, tabs, output, pretty);
				i++;
			}
		} else if (value.nodeType == Element) {
			output.add(tabs + "<");
			output.add(value.nodeName);
			for (attribute in value.attributes()) {
				output.add(" " + attribute + "=\"");
				output.add(StringTools.htmlEscape(value.get(attribute), true));
				output.add("\"");
			}
			if (hasChildren(value)) {
				output.add(">");
				if (pretty)
					output.add("\n");
				var childIndex = 0;
				while (childIndex < value.children.length) {
					final child:Xml = cast value.children[childIndex];
					writeNode(child, pretty ? tabs + "\t" : tabs, output, pretty);
					childIndex++;
				}
				output.add(tabs + "</");
				output.add(value.nodeName);
				output.add(">");
				if (pretty)
					output.add("\n");
			} else {
				output.add("/>");
				if (pretty)
					output.add("\n");
			}
		} else if (value.nodeType == PCData) {
			var nodeValue = value.nodeValue;
			if (nodeValue.length != 0) {
				output.add(tabs + StringTools.htmlEscape(nodeValue));
				if (pretty)
					output.add("\n");
			}
		} else if (value.nodeType == ProcessingInstruction) {
			output.add("<?" + value.nodeValue + "?>");
			if (pretty)
				output.add("\n");
		} else if (value.nodeType == DocType) {
			output.add("<!DOCTYPE " + value.nodeValue + ">");
			if (pretty)
				output.add("\n");
		}
	}

	private static function hasChildren(value:Xml):Bool {
		var i = 0;
		while (i < value.children.length) {
			final child:Xml = cast value.children[i];
			if (child.nodeType == Element || child.nodeType == PCData) {
				return true;
			}
			if (child.nodeType == CData || child.nodeType == Comment) {
				if (StringTools.ltrim(child.nodeValue).length != 0) {
					return true;
				}
			}
			i++;
		}
		return false;
	}

	private static function parseDocument(state:XmlParseState):Xml {
		final document = Xml.createDocument();
		skipWhitespace(state);
		while (!isEnd(state)) {
			if (matchString(state, "<!--")) {
				document.addChild(Xml.createComment(readUntil(state, "-->")));
				skipWhitespace(state);
				continue;
			}
			if (matchString(state, "<?")) {
				document.addChild(Xml.createProcessingInstruction(StringTools.trim(readUntil(state, "?>"))));
				skipWhitespace(state);
				continue;
			}
			if (matchString(state, "<!DOCTYPE")) {
				document.addChild(Xml.createDocType(StringTools.trim(readUntil(state, ">"))));
				skipWhitespace(state);
				continue;
			}
			if (peekChar(state) == "<") {
				document.addChild(parseElement(state));
				skipWhitespace(state);
				continue;
			}
			final text = decodeEntities(readText(state));
			if (text.length > 0) {
				document.addChild(Xml.createPCData(text));
			}
			skipWhitespace(state);
		}
		return document;
	}

	private static function parseElement(state:XmlParseState):Xml {
		expectChar(state, "<");
		if (matchChar(state, "/")) {
			failParse(state, "Unexpected closing tag start");
		}
		final name = parseName(state);
		final element = Xml.createElement(name);
		skipWhitespace(state);

		while (!isEnd(state)) {
			if (matchString(state, "/>")) {
				return element;
			}
			if (matchChar(state, ">")) {
				return parseChildren(state, element, name);
			}
			final attributeName = parseName(state);
			skipWhitespace(state);
			expectChar(state, "=");
			skipWhitespace(state);
			final attributeValue = parseAttributeValue(state);
			element.set(attributeName, decodeEntities(attributeValue));
			skipWhitespace(state);
		}

		failParse(state, "Unexpected end of input while reading start tag `" + name + "`");
		return element;
	}

	private static function parseChildren(state:XmlParseState, element:Xml, name:String):Xml {
		while (!isEnd(state)) {
			if (matchString(state, "</")) {
				final closeName = parseName(state);
				skipWhitespace(state);
				expectChar(state, ">");
				if (closeName != name) {
					failParse(state, "Mismatched closing tag, expected `" + name + "` but got `" + closeName + "`");
				}
				return element;
			}
			if (matchString(state, "<!--")) {
				element.addChild(Xml.createComment(readUntil(state, "-->")));
				continue;
			}
			if (matchString(state, "<![CDATA[")) {
				element.addChild(Xml.createCData(readUntil(state, "]]>")));
				continue;
			}
			if (matchString(state, "<?")) {
				element.addChild(Xml.createProcessingInstruction(StringTools.trim(readUntil(state, "?>"))));
				continue;
			}
			if (matchString(state, "<!DOCTYPE")) {
				element.addChild(Xml.createDocType(StringTools.trim(readUntil(state, ">"))));
				continue;
			}
			if (peekChar(state) == "<") {
				element.addChild(parseElement(state));
				continue;
			}
			final text = decodeEntities(readText(state));
			if (text.length > 0) {
				element.addChild(Xml.createPCData(text));
			}
		}

		failParse(state, "Unexpected end of input while reading element `" + name + "`");
		return element;
	}

	private static function parseName(state:XmlParseState):String {
		if (isEnd(state)) {
			failParse(state, "Unexpected end of input while reading name");
		}
		final start = state.index;
		final startCode = codeAt(state, state.index);
		if (!isNameStart(startCode)) {
			failParse(state, "Invalid name start");
		}
		state.index++;
		while (!isEnd(state) && isNameChar(codeAt(state, state.index))) {
			state.index++;
		}
		return state.source.substring(start, state.index);
	}

	private static function parseAttributeValue(state:XmlParseState):String {
		if (isEnd(state)) {
			failParse(state, "Unexpected end of input while reading attribute value");
		}
		final quote = state.source.charAt(state.index);
		if (quote != "\"" && quote != "'") {
			failParse(state, "Expected quoted attribute value");
		}
		state.index++;
		final start = state.index;
		while (!isEnd(state) && state.source.charAt(state.index) != quote) {
			state.index++;
		}
		if (isEnd(state)) {
			failParse(state, "Unterminated attribute value");
		}
		final value = state.source.substring(start, state.index);
		state.index++;
		return value;
	}

	private static function readText(state:XmlParseState):String {
		final start = state.index;
		while (!isEnd(state) && state.source.charAt(state.index) != "<") {
			state.index++;
		}
		return state.source.substring(start, state.index);
	}

	private static function readUntil(state:XmlParseState, terminator:String):String {
		final start = state.index;
		final end = state.source.indexOf(terminator, state.index);
		if (end == -1) {
			failParse(state, "Unterminated sequence, expected `" + terminator + "`");
		}
		state.index = end + terminator.length;
		return state.source.substring(start, end);
	}

	private static function decodeEntities(text:String):String {
		if (text.indexOf("&") == -1) {
			return text;
		}
		final output = new StringBuf();
		var position = 0;
		while (position < text.length) {
			final char = text.charAt(position);
			if (char != "&") {
				output.add(char);
				position++;
				continue;
			}
			final semicolon = text.indexOf(";", position + 1);
			if (semicolon == -1) {
				output.add(char);
				position++;
				continue;
			}
			final entity = text.substring(position + 1, semicolon);
			final decoded = decodeEntity(entity);
			if (decoded == null) {
				output.add("&");
				output.add(entity);
				output.add(";");
			} else {
				output.add(decoded);
			}
			position = semicolon + 1;
		}
		return output.toString();
	}

	private static function decodeEntity(entity:String):Null<String> {
		return switch (entity) {
			case "amp": "&";
			case "lt": "<";
			case "gt": ">";
			case "quot": "\"";
			case "apos": "'";
			case _:
				decodeNumericEntity(entity);
		};
	}

	private static function decodeNumericEntity(entity:String):Null<String> {
		if (!StringTools.startsWith(entity, "#")) {
			return null;
		}
		final numericValue:Null<Int> = if (StringTools.startsWith(entity, "#x") || StringTools.startsWith(entity, "#X")) {
			Std.parseInt("0x" + entity.substring(2));
		} else {
			Std.parseInt(entity.substring(1));
		};
		if (numericValue == null) {
			return null;
		}
		if (numericValue < 0 || numericValue > 0x10ffff) {
			return null;
		}
		return String.fromCharCode(numericValue);
	}

	private static function skipWhitespace(state:XmlParseState):Void {
		while (!isEnd(state)) {
			final code = codeAt(state, state.index);
			if (code == 32 || code == 9 || code == 10 || code == 13) {
				state.index++;
			} else {
				return;
			}
		}
	}

	private static function matchString(state:XmlParseState, value:String):Bool {
		if (value.length == 0) {
			return true;
		}
		if (state.index + value.length > state.length) {
			return false;
		}
		if (state.source.substr(state.index, value.length) == value) {
			state.index += value.length;
			return true;
		}
		return false;
	}

	private static function matchChar(state:XmlParseState, value:String):Bool {
		if (isEnd(state)) {
			return false;
		}
		if (state.source.charAt(state.index) == value) {
			state.index++;
			return true;
		}
		return false;
	}

	private static function expectChar(state:XmlParseState, value:String):Void {
		if (!matchChar(state, value)) {
			failParse(state, "Expected `" + value + "`");
		}
	}

	private static function peekChar(state:XmlParseState):String {
		return isEnd(state) ? "" : state.source.charAt(state.index);
	}

	private static function isEnd(state:XmlParseState):Bool {
		return state.index >= state.length;
	}

	private static function codeAt(state:XmlParseState, position:Int):Int {
		final code = state.source.charCodeAt(position);
		return code == null ? -1 : code;
	}

	private static function isNameStart(code:Int):Bool {
		return (code >= 65 && code <= 90) || (code >= 97 && code <= 122) || code == 95 || code == 58 || code > 127;
	}

	private static function isNameChar(code:Int):Bool {
		return isNameStart(code) || (code >= 48 && code <= 57) || code == 45 || code == 46;
	}

	private static function failParse(state:XmlParseState, message:String):Void {
		throw message + " at position " + state.index;
	}

	function new(nodeType:XmlType) {
		this.nodeType = nodeType;
		this.parent = null;
		children = [];
		attributeMap = new haxe.ds.StringMap<String>();
	}

	inline function ensureElementType() {
		if (nodeType != Document && nodeType != Element) {
			throw "Bad node type, expected Element or Document";
		}
	}
}

private class XmlParseState {
	public final source:String;
	public final length:Int;
	public var index:Int;

	public function new(source:String) {
		this.source = source;
		this.length = source.length;
		this.index = 0;
	}
}
