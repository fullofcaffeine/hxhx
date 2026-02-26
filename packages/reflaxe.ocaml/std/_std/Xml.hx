/**
	OCaml target override for `Xml`.

	Why this exists
	- Upstream `Xml` calls `haxe.xml.Parser` and `haxe.xml.Printer` directly.
	- Those modules also depend on `Xml`, which creates an OCaml module cycle when
	  compiled as separate units.

	Current scope
	- Preserve the core `Xml` node API and string rendering behavior.
	- Keep `toString()` self-contained in this module.
	- `parse()` is intentionally not wired yet in this override (tracked follow-up).
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

	static public function parse(_str:String):Xml {
		throw "Xml.parse is not supported yet by this OCaml override.";
	}

	public var nodeType(default, null):XmlType;
	@:isVar public var nodeName(get, set):String;
	@:isVar public var nodeValue(get, set):String;
	public var parent(default, null):Xml;

	var children:Array<Xml>;
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
		return createArrayIterator(children);
	}

	public function elements():Iterator<Xml> {
		ensureElementType();
		var ret:Array<Xml> = [];
		for (child in children) {
			if (child.nodeType == Element) {
				ret.push(child);
			}
		}
		return createArrayIterator(ret);
	}

	public function elementsNamed(name:String):Iterator<Xml> {
		ensureElementType();
		var ret:Array<Xml> = [];
		for (child in children) {
			if (child.nodeType == Element && child.nodeName == name) {
				ret.push(child);
			}
		}
		return createArrayIterator(ret);
	}

	public function firstChild():Xml {
		ensureElementType();
		return children[0];
	}

	public function firstElement():Xml {
		ensureElementType();
		for (child in children) {
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
		children.push(x);
		x.parent = this;
	}

	public function removeChild(x:Xml):Bool {
		ensureElementType();
		if (children.remove(x)) {
			x.parent = null;
			return true;
		}
		return false;
	}

	public function insertChild(x:Xml, pos:Int):Void {
		ensureElementType();
		if (x.parent != null) {
			x.parent.children.remove(x);
		}
		children.insert(pos, x);
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
				final child:Xml = value.children[i];
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
					final child:Xml = value.children[childIndex];
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
			final child:Xml = value.children[i];
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

	private static function createArrayIterator(values:Array<Xml>):Iterator<Xml> {
		var index = 0;
		return {
			hasNext: function():Bool {
				return index < values.length;
			},
			next: function():Xml {
				var current = values[index];
				index++;
				return current;
			}
		};
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
