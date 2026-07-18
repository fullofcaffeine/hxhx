package backend.cpp;

typedef CppKnownStdlibSignatureServices = {
	var sanitizeTypePath:String->String;
	var typeBaseName:String->String;
	var sanitizeIdentifier:String->String;
	var cppTypeHint:String->Null<CppRenderScope>->Null<CppClassLookup>->String;
	var cppReturnTypeHint:String->Null<CppRenderScope>->Null<CppClassLookup>->String;
	var isStringIteratorHelper:String->Bool;
	var isTypeResolverHelper:String->Bool;
	var isXmlParserSupportClass:String->Null<CppRenderScope>->Null<CppClassLookup>->Bool;
	var utestTestObjectCppType:Null<CppRenderScope>->Null<CppClassLookup>->String;
	var lookupForScope:Null<CppRenderScope>->Null<CppClassLookup>->CppClassLookup;
	var lookupClassForTypeHint:String->Null<CppRenderScope>->Null<CppClassLookup>->Null<HxClassDecl>;
	var renderedClassName:HxClassDecl->CppClassLookup->String;
};

/**
	Owns the C++ carrier signatures for already-recognized standard-library calls.

	This module does not select Haxe declarations or infer source-language
	semantics. Callers provide the existing scope-aware type-rendering services,
	and this table returns the same argument and result carrier types that the C++
	emitter previously kept inline. Keeping the declarative tables outside the
	main emitter shortens native compiler rebuilds and makes their target-specific
	ownership explicit.
**/
class CppKnownStdlibSignatures {
	final services:CppKnownStdlibSignatureServices;

	public function new(services:CppKnownStdlibSignatureServices) {
		this.services = services;
	}

	public function methodReturnCppType(className:String, methodName:String, typeHint:String, ?scope:CppRenderScope, ?classLookup:CppClassLookup):String {
		final owner = services.sanitizeTypePath(services.typeBaseName(className == null ? "" : className));
		final method = services.sanitizeIdentifier(methodName == null ? "" : methodName);
		final preludeReturn = preludeMethodReturnType(owner, method);
		if (preludeReturn.length > 0)
			return preludeReturn;
		if (services.isStringIteratorHelper(owner)) {
			if ((owner == "StringIteratorUnicode" && method == "unicodeIterator")
				|| (owner == "StringKeyValueIteratorUnicode" && method == "unicodeKeyValueIterator"))
				return services.cppTypeHint(owner, scope, classLookup);
			if (method == "hasNext")
				return "bool";
			if (method == "next")
				return owner == "StringIterator" || owner == "StringIteratorUnicode" ? "int" : "auto";
		}
		if (owner == "BalancedTree") {
			final treeNode = services.cppTypeHint("TreeNode<K,V>", scope, classLookup);
			return switch (method) {
				case "setLoop" | "removeLoop" | "merge" | "minBinding" | "removeMinBinding" | "balance":
					treeNode;
				case "compare":
					"int";
				case _:
					StringTools.trim(typeHint == null ? "" : typeHint).length > 0 ? services.cppReturnTypeHint(typeHint, scope, classLookup) : "";
			}
		}
		if (owner == "Template") {
			return switch (method) {
				case "parse" | "parseBlock":
					services.cppTypeHint("TemplateExpr", scope, classLookup);
				case "parseTokens":
					services.cppTypeHint("List<Token>", scope, classLookup);
				case "parseExpr":
					services.cppTypeHint("Void->Dynamic", scope, classLookup);
				case _:
					StringTools.trim(typeHint == null ? "" : typeHint).length > 0 ? services.cppReturnTypeHint(typeHint, scope, classLookup) : "";
			}
		}
		if (owner == "Bytes")
			return switch (method) {
				case "get" | "getUInt16" | "getInt32" | "compare" | "fastGet":
					"int";
				case "getDouble" | "getFloat":
					"double";
				case "set" | "blit" | "fill" | "setDouble" | "setFloat" | "setUInt16" | "setInt32" | "setInt64":
					"void";
				case "sub" | "alloc" | "ofString" | "ofData" | "ofHex":
					concreteClassReferenceCppType("Bytes", scope, classLookup);
				case "getInt64":
					"long long";
				case "getString" | "readString" | "toString" | "toHex":
					"std::string";
				case "getData":
					"std::vector<int>";
				case _:
					StringTools.trim(typeHint == null ? "" : typeHint).length > 0 ? services.cppReturnTypeHint(typeHint, scope, classLookup) : "";
			};
		if (owner == "BytesBuffer")
			return switch (method) {
				case "get_length":
					"int";
				case "addByte" | "add" | "addString" | "addInt32" | "addInt64" | "addFloat" | "addDouble" | "addBytes":
					"void";
				case "getBytes":
					services.cppTypeHint("Bytes", scope, classLookup);
				case _:
					StringTools.trim(typeHint == null ? "" : typeHint).length > 0 ? services.cppReturnTypeHint(typeHint, scope, classLookup) : "";
			};
		if (owner == "Input")
			return switch (method) {
				case "readByte" | "readBytes" | "readInt8" | "readInt16" | "readUInt16" | "readInt24" | "readUInt24" | "readInt32":
					"int";
				case "readAll" | "read":
					services.cppTypeHint("Bytes", scope, classLookup);
				case "close" | "readFullBytes":
					"void";
				case "set_bigEndian":
					"bool";
				case "readUntil" | "readLine" | "readString":
					"std::string";
				case "readFloat" | "readDouble":
					"double";
				case _:
					StringTools.trim(typeHint == null ? "" : typeHint).length > 0 ? services.cppReturnTypeHint(typeHint, scope, classLookup) : "";
			};
		if (owner == "Output")
			return switch (method) {
				case "writeByte" | "flush" | "close" | "write" | "writeFullBytes" | "writeFloat" | "writeDouble" | "writeInt8" | "writeInt16" |
					"writeUInt16" | "writeInt24" | "writeUInt24" | "writeInt32" | "prepare" | "writeInput" | "writeString":
					"void";
				case "writeBytes":
					"int";
				case "set_bigEndian":
					"bool";
				case _:
					StringTools.trim(typeHint == null ? "" : typeHint).length > 0 ? services.cppReturnTypeHint(typeHint, scope, classLookup) : "";
			};
		if (services.isTypeResolverHelper(owner)) {
			return switch (method) {
				case "resolveClass":
					"std::shared_ptr<Class>";
				case "resolveEnum":
					"std::shared_ptr<Enum>";
				case _:
					StringTools.trim(typeHint == null ? "" : typeHint).length > 0 ? services.cppReturnTypeHint(typeHint, scope, classLookup) : "";
			}
		}
		if (owner == "BaseCode") {
			return switch (method) {
				case "encodeBytes" | "decodeBytes":
					services.cppTypeHint("Bytes", scope, classLookup);
				case "encodeString" | "decodeString" | "encode" | "decode":
					"std::string";
				case "initTable":
					"void";
				case _:
					StringTools.trim(typeHint == null ? "" : typeHint).length > 0 ? services.cppReturnTypeHint(typeHint, scope, classLookup) : "";
			}
		}
		if (owner == "Base64") {
			return switch (method) {
				case "encode" | "urlEncode":
					"std::string";
				case "decode" | "urlDecode":
					services.cppTypeHint("Bytes", scope, classLookup);
				case _:
					StringTools.trim(typeHint == null ? "" : typeHint).length > 0 ? services.cppReturnTypeHint(typeHint, scope, classLookup) : "";
			}
		}
		if (owner == "Resource") {
			return switch (method) {
				case "listNames":
					services.cppTypeHint("Array<String>", scope, classLookup);
				case "getString":
					"std::string";
				case "getBytes":
					services.cppTypeHint("Bytes", scope, classLookup);
				case "__init__":
					"void";
				case _:
					StringTools.trim(typeHint == null ? "" : typeHint).length > 0 ? services.cppReturnTypeHint(typeHint, scope, classLookup) : "";
			}
		}
		if (owner == "Json") {
			return switch (method) {
				case "parse":
					"std::any";
				case "stringify":
					"std::string";
				case _:
					StringTools.trim(typeHint == null ? "" : typeHint).length > 0 ? services.cppReturnTypeHint(typeHint, scope, classLookup) : "";
			}
		}
		if (owner == "JsonParser") {
			return switch (method) {
				case "parse" | "doParse" | "parseRec" | "parseNumber":
					"std::any";
				case "parseString":
					"std::string";
				case "nextChar":
					"int";
				case "invalidChar" | "invalidNumber":
					"void";
				case _:
					StringTools.trim(typeHint == null ? "" : typeHint).length > 0 ? services.cppReturnTypeHint(typeHint, scope, classLookup) : "";
			}
		}
		if (owner == "JsonPrinter") {
			return switch (method) {
				case "print":
					"std::string";
				case "newl" | "write" | "addChar" | "add" | "classString" | "objString" | "fieldsString" | "quote" | "quoteUtf8":
					"void";
				case _:
					StringTools.trim(typeHint == null ? "" : typeHint).length > 0 ? services.cppReturnTypeHint(typeHint, scope, classLookup) : "";
			}
		}
		if (owner == "Unserializer") {
			return switch (method) {
				case "initCodes":
					"std::vector<int>";
				case "run" | "unserialize":
					"std::any";
				case "fastLength" | "fastCharCodeAt" | "get" | "readDigits":
					"int";
				case "fastCharAt" | "fastSubstr":
					"std::string";
				case _:
					StringTools.trim(typeHint == null ? "" : typeHint).length > 0 ? services.cppReturnTypeHint(typeHint, scope, classLookup) : "";
			}
		}
		if (owner == "Parser" && services.isXmlParserSupportClass(className, scope, classLookup)) {
			return switch (method) {
				case "parse":
					services.cppTypeHint("Xml", scope, classLookup);
				case _:
					StringTools.trim(typeHint == null ? "" : typeHint).length > 0 ? services.cppReturnTypeHint(typeHint, scope, classLookup) : "";
			}
		}
		if (owner == "Xml") {
			return switch (method) {
				case "parse" | "createElement" | "createPCData" | "createCData" | "createComment" | "createDocType" | "createProcessingInstruction" |
					"createDocument" | "firstChild" | "firstElement":
					services.cppTypeHint("Xml", scope, classLookup);
				case "get_nodeName" | "set_nodeName" | "get_nodeValue" | "set_nodeValue" | "get" | "toString":
					"std::string";
				case "set" | "remove" | "addChild" | "insertChild" | "ensureElementType":
					"void";
				case "exists" | "removeChild":
					"bool";
				case "attributes":
					services.cppTypeHint("Iterator<String>", scope, classLookup);
				case "iterator" | "elements" | "elementsNamed":
					services.cppTypeHint("Iterator<Xml>", scope, classLookup);
				case _:
					StringTools.trim(typeHint == null ? "" : typeHint).length > 0 ? services.cppReturnTypeHint(typeHint, scope, classLookup) : "";
			}
		}
		if (owner == "Md5") {
			return switch (method) {
				case "encode" | "hex":
					"std::string";
				case "make":
					services.cppTypeHint("Bytes", scope, classLookup);
				case "bytes2blks" | "str2blks" | "doEncode":
					"std::vector<int>";
				case "bitOR" | "bitXOR" | "bitAND" | "addme" | "rol" | "cmn" | "ff" | "gg" | "hh" | "ii":
					"int";
				case _:
					StringTools.trim(typeHint == null ? "" : typeHint).length > 0 ? services.cppReturnTypeHint(typeHint, scope, classLookup) : "";
			}
		}
		if (owner == "EReg" && method == "matchedPos")
			return services.cppTypeHint("{pos:Int,len:Int}", scope, classLookup);
		if (owner == "Exception" && (method == "caught" || method == "thrown"))
			return "std::shared_ptr<Exception>";
		return StringTools.trim(typeHint == null ? "" : typeHint).length > 0 ? services.cppReturnTypeHint(typeHint, scope, classLookup) : "";
	}

	public function preludeMethodReturnType(className:String, methodName:String):String {
		final owner = services.sanitizeTypePath(services.typeBaseName(className == null ? "" : className));
		final method = services.sanitizeIdentifier(methodName == null ? "" : methodName);
		if (owner == "Timer" && method == "stamp")
			return "double";
		if (owner == "Timer" && method == "delay")
			return "std::shared_ptr<Timer>";
		if (owner == "Timer" && method == "stop")
			return "void";
		if (owner == "Http" && (method == "setPostData" || method == "setPostBytes" || method == "request"))
			return "void";
		if (owner == "Lock" && (method == "acquire" || method == "release"))
			return "void";
		if (owner == "Lock" && method == "wait")
			return "bool";
		if (owner == "Mutex" && (method == "acquire" || method == "release"))
			return "void";
		if (owner == "Mutex" && method == "tryAcquire")
			return "bool";
		if (owner == "MainLoop" && method == "add")
			return "std::shared_ptr<MainEvent>";
		if (owner == "MainLoop" && method == "hasEvents")
			return "bool";
		if (owner == "MainLoop" && method == "tick")
			return "double";
		if (owner == "MainLoop" && method == "sortEvents")
			return "void";
		if (owner == "MainEvent" && (method == "delay" || method == "stop" || method == "wakeup"))
			return "void";
		if (owner == "EntryPoint" && (method == "wakeup" || method == "runInMainThread" || method == "addThread"))
			return "void";
		if (owner == "EntryPoint" && method == "processEvents")
			return "double";
		return "";
	}

	/**
		Resolve a known concrete API class directly to its rendered reference type.

		Known stdlib signatures have already established that these positions are
		class references, so they do not need the generic type-hint classifier's
		abstract, structural, container, and function probes. Class lookup remains
		scope-aware so module-local rendered names and package collisions keep their
		existing emitted identity.
	**/
	function concreteClassReferenceCppType(typeHint:String, ?scope:CppRenderScope, ?classLookup:CppClassLookup):String {
		final lookup = services.lookupForScope(scope, classLookup);
		final cls = services.lookupClassForTypeHint(typeHint, scope, lookup);
		final rendered = cls == null ? services.sanitizeTypePath(services.typeBaseName(typeHint)) : services.renderedClassName(cls, lookup);
		return "std::shared_ptr<" + rendered + ">";
	}

	public function preludeMethodParamTypes(className:String, methodName:String):Array<String> {
		final owner = services.sanitizeTypePath(services.typeBaseName(className == null ? "" : className));
		final method = services.sanitizeIdentifier(methodName == null ? "" : methodName);
		if (owner == "Timer" && method == "delay")
			return ["std::function<void()>", "double"];
		if (owner == "MainLoop" && method == "add")
			return ["std::function<void()>", "int"];
		if (owner == "EntryPoint" && (method == "runInMainThread" || method == "addThread"))
			return ["std::function<void()>"];
		if (owner == "Http" && method == "setPostData")
			return ["std::string"];
		return [];
	}

	/**
		Return the target parameter types for known stdlib methods.

		Declaration lookups omit `providedArgCount` and receive the complete
		signature. Call sites may provide their arity so unused optional positions
		that require type classification can be excluded without changing the
		types or adaptation of supplied arguments.
	**/
	public function methodParamCppTypes(className:String, methodName:String, ?scope:CppRenderScope, ?classLookup:CppClassLookup,
			providedArgCount:Int = -1):Array<String> {
		final owner = services.sanitizeTypePath(services.typeBaseName(className == null ? "" : className));
		final method = services.sanitizeIdentifier(methodName == null ? "" : methodName);
		return switch (owner) {
			case "Bytes":
				switch (method) {
					case "alloc":
						["int"];
					case "ofString":
						providedArgCount == 1 ? ["std::string"] : ["std::string", services.cppTypeHint("Encoding", scope, classLookup)];
					case "ofHex":
						["std::string"];
					case "ofData":
						["std::vector<int>"];
					case "fastGet":
						["std::vector<int>", "int"];
					case "get" | "getUInt16" | "getInt32" | "getInt64" | "getDouble" | "getFloat":
						["int"];
					case "readString":
						["int", "int"];
					case "set" | "setUInt16" | "setInt32":
						["int", "int"];
					case "setInt64":
						["int", "long long"];
					case "setDouble" | "setFloat":
						["int", "double"];
					case "blit":
						["int", concreteClassReferenceCppType("Bytes", scope, classLookup), "int", "int"];
					case "sub":
						["int", "int"];
					case "getString":
						["int", "int", services.cppTypeHint("Encoding", scope, classLookup)];
					case "fill":
						["int", "int", "int"];
					case "compare":
						[concreteClassReferenceCppType("Bytes", scope, classLookup)];
					case _:
						[];
				}
			case "BytesBuffer":
				switch (method) {
					case "addByte" | "addInt32":
						["int"];
					case "addInt64":
						["long long"];
					case "addFloat" | "addDouble":
						["double"];
					case "add":
						[services.cppTypeHint("Bytes", scope, classLookup)];
					case "addString":
						["std::string", services.cppTypeHint("Encoding", scope, classLookup)];
					case "addBytes":
						[services.cppTypeHint("Bytes", scope, classLookup), "int", "int"];
					case _:
						[];
				}
			case "Input":
				switch (method) {
					case "readBytes" | "readFullBytes":
						[services.cppTypeHint("Bytes", scope, classLookup), "int", "int"];
					case "read" | "readUntil":
						["int"];
					case "readAll":
						["std::optional<int>"];
					case "readString":
						["int", services.cppTypeHint("Encoding", scope, classLookup)];
					case "set_bigEndian":
						["bool"];
					case _:
						[];
				}
			case "Output":
				switch (method) {
					case "writeByte" | "writeInt8" | "writeInt16" | "writeUInt16" | "writeInt24" | "writeUInt24" | "writeInt32" | "prepare":
						["int"];
					case "writeBytes" | "writeFullBytes":
						[services.cppTypeHint("Bytes", scope, classLookup), "int", "int"];
					case "write":
						[services.cppTypeHint("Bytes", scope, classLookup)];
					case "writeFloat" | "writeDouble":
						["double"];
					case "writeInput":
						[services.cppTypeHint("Input", scope, classLookup), "std::optional<int>"];
					case "writeString":
						["std::string", services.cppTypeHint("Encoding", scope, classLookup)];
					case "set_bigEndian":
						["bool"];
					case _:
						[];
				}
			case "Base64":
				final bytesType = services.cppTypeHint("Bytes", scope, classLookup);
				switch (method) {
					case "encode" | "urlEncode":
						[bytesType, "bool"];
					case "decode" | "urlDecode":
						["std::string", "bool"];
					case _:
						[];
				}
			case "BaseCode":
				final bytesType = services.cppTypeHint("Bytes", scope, classLookup);
				switch (method) {
					case "encodeBytes" | "decodeBytes":
						[bytesType];
					case "encodeString" | "decodeString":
						["std::string"];
					case "encode" | "decode":
						["std::string", "std::string"];
					case _:
						[];
				}
			case "Resource":
				switch (method) {
					case "getString" | "getBytes":
						["std::string"];
					case _:
						[];
				}
			case "JsonParser":
				switch (method) {
					case "parse":
						["std::string"];
					case "parseNumber" | "invalidNumber":
						["int"];
					case _:
						[];
				}
			case "JsonPrinter":
				final jsonPrinterReplacerType = "std::function<std::string(std::string, std::string)>";
				switch (method) {
					case "print":
						[
							"std::any",
							"std::optional<" + jsonPrinterReplacerType + ">",
							"std::optional<std::string>"
						];
					case "write":
						["std::any", "std::any"];
					case "addChar":
						["int"];
					case "add" | "quote" | "quoteUtf8":
						["std::string"];
					case "classString" | "objString":
						["std::any"];
					case "fieldsString":
						["std::any", "std::vector<std::string>"];
					case _:
						[];
				}
			case "Unserializer":
				switch (method) {
					case "unserializeObject":
						["std::any"];
					case "fastLength":
						["std::string"];
					case "fastCharCodeAt" | "fastCharAt":
						["std::string", "int"];
					case "fastSubstr":
						["std::string", "int", "int"];
					case _:
						[];
				}
			case "Xml":
				final xmlType = services.cppTypeHint("Xml", scope, classLookup);
				switch (method) {
					case "parse" | "createElement" | "createPCData" | "createCData" | "createComment" | "createDocType" | "createProcessingInstruction" |
						"set_nodeName" | "set_nodeValue" | "get" | "remove" | "exists" | "elementsNamed":
						["std::string"];
					case "set":
						["std::string", "std::string"];
					case "addChild" | "removeChild":
						[xmlType];
					case "insertChild":
						[xmlType, "int"];
					case _:
						[];
				}
			case "Test":
				switch (method) {
					case "exc" | "unspec":
						["std::function<void()>", "std::optional<PosInfos>"];
					case _:
						[];
				}
			case "Md5":
				final bytesType = services.cppTypeHint("Bytes", scope, classLookup);
				switch (method) {
					case "encode":
						["std::string"];
					case "make":
						[bytesType];
					case _:
						[];
				}
			case "TypeResolver" | "DefaultResolver" | "NullResolver":
				switch (method) {
					case "resolveClass" | "resolveEnum":
						["std::string"];
					case _:
						[];
				}
			case "Type":
				switch (method) {
					case "resolveClass" | "resolveEnum":
						["std::string"];
					case "getEnumName" | "getEnumConstructs" | "allEnums":
						["std::shared_ptr<Enum>"];
					case "createEnum":
						["std::shared_ptr<Enum>", "std::string", "std::vector<std::any>"];
					case "createEnumIndex":
						["std::shared_ptr<Enum>", "int"];
					case _:
						[];
				}
			case "Runner":
				final utestTargetType = services.utestTestObjectCppType(scope, classLookup);
				if (utestTargetType.length == 0) []; else switch (method) {
					case "addCase" | "addCaseOld" | "isMethod":
						[utestTargetType];
					case _:
						[];
				}
			case _:
				[];
		}
	}
}
