package backend.cpp;

/**
	C++ target-owned macro expression model.

	Why
	- Full1 C++ macro quote pressure needs runtime-visible `haxe.macro.Expr`
	  shape, not just stable printable text.
	- Keeping this in a target helper prevents `CppTargetCore` from becoming a
	  fake macro stdlib/runtime dumping ground while still letting the C++ MVP
	  own the small structural subset it can execute.

	What
	- Emits a compact generated C++ support type for expression objects, enum
	  constructors, enum parameters, and string-like constant payloads.
	- Renders `EMacroExpr` recursively into that support type.

	How
	- Expression objects store their definition in `.expr`.
	- Enum nodes use `.__hx_ctor` and `.__hx_params`.
	- String payload nodes use `.__hx_value`.
**/
class CppMacroExpr {
	public static inline final CPP_TYPE = "__HxMacroExpr";

	public static function runtimePreludeLines():Array<String> {
		return [
			"struct __HxMacroExpr {",
			"  std::string __hx_ctor;",
			"  std::vector<__HxMacroExpr> __hx_params;",
			"  std::shared_ptr<__HxMacroExpr> expr;",
			"  std::string __hx_value;",
			"  bool __hx_bool_value = false;",
			"  bool __hx_has_bool = false;",
			"  operator std::string() const { return __hx_value; }",
			"  operator bool() const { return __hx_has_bool ? __hx_bool_value : !__hx_value.empty(); }",
			"};",
			"",
			"static __HxMacroExpr __hxhx_macro_expr(const __HxMacroExpr& expr) {",
			"  __HxMacroExpr out;",
			"  out.expr = std::make_shared<__HxMacroExpr>(expr);",
			"  return out;",
			"}",
			"",
			"static __HxMacroExpr __hxhx_macro_enum(const std::string& name, std::vector<__HxMacroExpr> params = {}) {",
			"  __HxMacroExpr out;",
			"  out.__hx_ctor = name;",
			"  out.__hx_params = params;",
			"  return out;",
			"}",
			"",
			"static __HxMacroExpr __hxhx_macro_string(const std::string& value) {",
			"  __HxMacroExpr out;",
			"  out.__hx_value = value;",
			"  return out;",
			"}",
			"",
			"static __HxMacroExpr __hxhx_macro_bool(bool value) {",
			"  __HxMacroExpr out;",
			"  out.__hx_bool_value = value;",
			"  out.__hx_has_bool = true;",
			"  return out;",
			"}",
			"",
			"static __HxMacroExpr __hxhx_macro_value(const __HxMacroExpr& value) {",
			"  return value;",
			"}",
			"",
			"static __HxMacroExpr __hxhx_macro_value(const std::string& value) {",
			"  return __hxhx_macro_string(value);",
			"}",
			"",
			"static __HxMacroExpr __hxhx_macro_value(const char* value) {",
			"  return __hxhx_macro_string(std::string(value));",
			"}",
			"",
			"template<typename T>",
			"static __HxMacroExpr __hxhx_macro_value(const T& value) {",
			"  std::ostringstream out;",
			"  out << value;",
			"  return __hxhx_macro_string(out.str());",
			"}",
			"",
			"static const __HxMacroExpr& __hxhx_macro_expr_field(const __HxMacroExpr& value) {",
			"  static const __HxMacroExpr empty;",
			"  return value.expr ? *value.expr : empty;",
			"}",
			"",
			"static __HxMacroExpr __hxhx_macro_param(const __HxMacroExpr& value, int index) {",
			"  if (index < 0 || index >= static_cast<int>(value.__hx_params.size())) return __HxMacroExpr{};",
			"  return value.__hx_params[static_cast<std::size_t>(index)];",
			"}",
			"",
			"template<typename T>",
			"static __HxMacroExpr __hxhx_macro_param(const T&, int) {",
			"  return __HxMacroExpr{};",
			"}",
			"",
			"static bool __hxhx_macro_ctor(const __HxMacroExpr& value, const std::string& name) {",
			"  return value.__hx_ctor == name;",
			"}",
			"",
			"template<typename T>",
			"static bool __hxhx_macro_ctor(const T&, const std::string&) {",
			"  return false;",
			"}",
			"",
			"static bool __hxhx_enum_eq(const __HxMacroExpr& value, const std::string& name) {",
			"  return value.__hx_ctor == name;",
			"}",
			"",
			"static bool __hxhx_enum_eq(const std::string& value, const std::string& name) {",
			"  return value == name;",
			"}",
			"",
			"template<typename T>",
			"static bool __hxhx_enum_eq(const T& value, const std::string& name) {",
			"  std::ostringstream out;",
			"  out << value;",
			"  return out.str() == name;",
			"}",
			"",
			"static std::string __hxhx_macro_to_string(const __HxMacroExpr& value) {",
			"  if (value.expr) return __hxhx_macro_to_string(*value.expr);",
			"  if (value.__hx_has_bool) return value.__hx_bool_value ? \"true\" : \"false\";",
			"  if (!value.__hx_value.empty()) return value.__hx_value;",
			"  if (value.__hx_ctor == \"CString\" && !value.__hx_params.empty()) return std::string(\"CString(\") + __hxhx_macro_to_string(value.__hx_params[0]) + \")\";",
			"  if ((value.__hx_ctor == \"CInt\" || value.__hx_ctor == \"CFloat\" || value.__hx_ctor == \"CIdent\") && !value.__hx_params.empty()) return value.__hx_ctor + \"(\" + __hxhx_macro_to_string(value.__hx_params[0]) + \")\";",
			"  if (value.__hx_ctor == \"EConst\" && !value.__hx_params.empty()) return std::string(\"EConst(\") + __hxhx_macro_to_string(value.__hx_params[0]) + \")\";",
			"  if ((value.__hx_ctor == \"EParenthesis\" || value.__hx_ctor == \"EUntyped\") && !value.__hx_params.empty()) return value.__hx_ctor + \"(\" + __hxhx_macro_to_string(value.__hx_params[0]) + \")\";",
			"  if (value.__hx_ctor == \"EField\" && value.__hx_params.size() >= 2) return std::string(\"EField(\") + __hxhx_macro_to_string(value.__hx_params[0]) + \",\" + __hxhx_macro_to_string(value.__hx_params[1]) + \")\";",
			"  if (value.__hx_ctor == \"EArray\" && value.__hx_params.size() >= 2) return std::string(\"EArray(\") + __hxhx_macro_to_string(value.__hx_params[0]) + \",\" + __hxhx_macro_to_string(value.__hx_params[1]) + \")\";",
			"  if (value.__hx_ctor == \"EBinop\" && value.__hx_params.size() >= 3) return std::string(\"EBinop(\") + __hxhx_macro_to_string(value.__hx_params[0]) + \",\" + __hxhx_macro_to_string(value.__hx_params[1]) + \",\" + __hxhx_macro_to_string(value.__hx_params[2]) + \")\";",
			"  if (value.__hx_ctor == \"EArrayDecl\") {",
			"    std::string out = \"EArrayDecl([\";",
			"    for (std::size_t i = 0; i < value.__hx_params.size(); ++i) {",
			"      if (i > 0) out += \",\";",
			"      out += __hxhx_macro_to_string(value.__hx_params[i]);",
			"    }",
			"    out += \"])\";",
			"    return out;",
			"  }",
			"  if (!value.__hx_ctor.empty()) {",
			"    std::string out = value.__hx_ctor;",
			"    if (!value.__hx_params.empty()) {",
			"      out += \"(\";",
			"      for (std::size_t i = 0; i < value.__hx_params.size(); ++i) {",
			"        if (i > 0) out += \",\";",
			"        out += __hxhx_macro_to_string(value.__hx_params[i]);",
			"      }",
			"      out += \")\";",
			"    }",
			"    return out;",
			"  }",
			"  return std::string();",
			"}",
			""
		];
	}

	public static function macroExpr(expr:HxExpr, wrappers:Array<String>):String {
		var exprDef = macroExprDef(expr);
		if (wrappers != null) {
			var i = wrappers.length;
			while (i > 0) {
				i--;
				exprDef = switch (wrappers[i]) {
					case "parenthesis":
						macroEnum("EParenthesis", [macroExprObject(exprDef)]);
					case "untyped":
						macroEnum("EUntyped", [macroExprObject(exprDef)]);
					case _:
						exprDef;
				}
			}
		}
		return macroExprObject(exprDef);
	}

	static function macroExprObject(exprDef:String):String {
		return "__hxhx_macro_expr(" + exprDef + ")";
	}

	static function macroEnum(name:String, params:Array<String>):String {
		if (params == null || params.length == 0)
			return "__hxhx_macro_enum(" + quoteString(name) + ")";
		return "__hxhx_macro_enum(" + quoteString(name) + ", std::vector<__HxMacroExpr>{" + params.join(", ") + "})";
	}

	static function macroString(value:String):String {
		return "__hxhx_macro_string(" + quoteString(value) + ")";
	}

	static function macroBool(value:Bool):String {
		return "__hxhx_macro_bool(" + (value ? "true" : "false") + ")";
	}

	static function macroExprDef(expr:HxExpr):String {
		return switch (expr) {
			case EString(value):
				macroEnum("EConst", [macroEnum("CString", [macroString(value), macroEnum("DoubleQuotes", [])])]);
			case EInt(value):
				macroEnum("EConst", [macroEnum("CInt", [macroString(Std.string(value))])]);
			case EFloat(value):
				macroEnum("EConst", [macroEnum("CFloat", [macroString(Std.string(value))])]);
			case ENull:
				macroEnum("EConst", [macroEnum("CIdent", [macroString("null")])]);
			case EIdent(name):
				macroEnum("EConst", [macroEnum("CIdent", [macroString(name)])]);
			case EField(receiver, field):
				macroEnum("EField", [macroExpr(receiver, []), macroString(field)]);
			case ENullSafeField(receiver, field):
				macroEnum("EField", [macroExpr(receiver, []), macroString(field), macroEnum("Safe", [])]);
			case EArrayAccess(receiver, index):
				macroEnum("EArray", [macroExpr(receiver, []), macroExpr(index, [])]);
			case EArrayDecl(values):
				macroEnum("EArrayDecl", values == null ? [] : [for (value in values) macroExpr(value, [])]);
			case EBinop("in", left, right):
				macroEnum("EBinop", [macroEnum("OpIn", []), macroExpr(left, []), macroExpr(right, [])]);
			case EBinop("=>", left, right):
				macroEnum("EBinop", [macroEnum("OpArrow", []), macroExpr(left, []), macroExpr(right, [])]);
			case EBinop(op, left, right):
				macroEnum("EBinop", [macroString(op), macroExpr(left, []), macroExpr(right, [])]);
			case EUnop(op, fixity, inner):
				HxUnaryOperatorTools.requireValidFixity(op, fixity);
				macroEnum("EUnop", [
					macroEnum(HxUnaryOperatorTools.macroConstructor(op), []),
					macroBool(fixity == HxUnaryFixity.Postfix),
					macroExpr(inner, [])
				]);
			case ECall(callee, args):
				macroEnum("ECall", [macroExpr(callee, [])].concat(args == null ? [] : [for (arg in args) macroExpr(arg, [])]));
			case EUntyped(inner):
				macroEnum("EUntyped", [macroExpr(inner, [])]);
			case EMacroExpr(inner, innerWrappers):
				macroExpr(inner, innerWrappers);
			case _:
				macroEnum("EUnsupported", [macroString(exprKind(expr))]);
		};
	}

	static function quoteString(value:String):String {
		final s = value == null ? "" : value;
		final b = new StringBuf();
		b.add("\"");
		for (i in 0...s.length) {
			final c = s.charCodeAt(i);
			switch (c) {
				case "\\".code:
					b.add("\\\\");
				case "\"".code:
					b.add("\\\"");
				case "\n".code:
					b.add("\\n");
				case "\r".code:
					b.add("\\r");
				case "\t".code:
					b.add("\\t");
				case _:
					b.addChar(c);
			}
		}
		b.add("\"");
		return b.toString();
	}

	static function exprKind(expr:HxExpr):String {
		return switch (expr) {
			case ENull: "ENull";
			case EBool(_): "EBool";
			case EString(_): "EString";
			case EInt(_): "EInt";
			case EFloat(_): "EFloat";
			case EEnumValue(_): "EEnumValue";
			case EThis: "EThis";
			case ESuper: "ESuper";
			case EIdent(name): "EIdent(" + name + ")";
			case EField(receiver, field): "EField(" + exprKind(receiver) + "." + field + ")";
			case ENullSafeField(receiver, field): "ENullSafeField(" + exprKind(receiver) + "?." + field + ")";
			case ECall(callee, _): "ECall(" + exprKind(callee) + ")";
			case EReturn(_): "EReturn";
			case EMacroExpr(_, _): "EMacroExpr";
			case EMacroType(_): "EMacroType";
			case ELambda(_, _): "ELambda";
			case EBinop(op, _, _): "EBinop(" + op + ")";
			case EUnop(op, fixity, _):
				"EUnop("
				+ HxUnaryOperatorTools.sourceToken(op)
				+ ","
				+ (fixity == HxUnaryFixity.Postfix ? "postfix" : "prefix")
				+ ")";
			case ETernary(_, _, _): "ETernary";
			case ESwitchRaw(_): "ESwitchRaw";
			case ESwitch(_, _, _): "ESwitch";
			case ECast(_, _): "ECast";
			case EUntyped(_): "EUntyped";
			case ENew(typePath, _): "ENew(" + typePath + ")";
			case EAnon(_, _): "EAnon";
			case EArrayDecl(_): "EArrayDecl";
			case EArrayAccess(_, _): "EArrayAccess";
			case EArrayComprehension(_, _, _, _): "EArrayComprehension";
			case ERange(_, _): "ERange";
			case ETryCatchRaw(_): "ETryCatchRaw";
			case EUnsupported(_): "EUnsupported";
		};
	}
}
