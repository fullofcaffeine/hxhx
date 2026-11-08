/**
	Constant patterns and compound assignments must check value kinds as Haxe 4.3.7 does.

	Before this test, hxhx accepted `switch (i:Int) { case 1.5: }`, `anon.f |= 1` on a
	Float field and `b.x /= 2` on an Int field. The accepted groups also hold forms that
	a first version of these checks rejected by mistake: code inside `untyped`, the Float
	result of `/`, locals first assigned `null`, and abstracts reached through `from`. Upstream rejects each with
	`Float should be Int`. Every case below is first checked with upstream Haxe, then
	typed by hxhx with the production class paths. Rejected cases must give upstream's
	first-line message; accepted cases share one module per group.

	The compound matrix covers every compound operator on Int, Float, haxe.Int32,
	UInt and Dynamic locals, on class and structure fields, and on array items, with
	an Int and a Float value. Its expected messages were retained from Haxe 4.3.7.
 */
class M14PatternCompoundKindsTest {
	static final root = ".tmp/pattern_compound_kinds";

	/** Declarations that the case bodies use. */
	static final declarations = "abstract AInt(Int) from Int to Int {}\n"
		+ "abstract AFloat(Float) from Float to Float {}\n"
		+ "enum abstract EA(Int) { var One = 1; var Two = 2; }\n"
		+ "abstract Money(Int) from Int to Int { @:op(A / B) static function div(a:Money, b:Int):Money return Std.int((a:Int) / b); }\n"
		+ "enum E { A(i:Int); B(f:Float, s:String); }\n"
		+ "class Pt { public var x:Int; public function new() x = 1; }\n"
		+ "class Box { public var x:Int = 1; public var f:Float = 1.5; public var i32:haxe.Int32 = 1; public function new() {} }\n"
		+ "enum abstract EB(Int) from Int { var Eins = 1; var Zwei = 2; }\n"
		+ "abstract TO(Int) to Int {}\n"
		+ "abstract S(String) from String to String {}\n"
		+ "enum abstract ETo(Int) to Int { var TOne = 1; var TTwo = 2; }\n"
		+ "abstract M(Float) from Int to Float {}\n"
		+ "abstract N(Null<Int>) from Int {}\n"
		+ "class H { public static function half(i:Int) return i / 2; }\n";

	/** `name -> [declaration, place]` for the compound matrix. */
	static final places = [
		"IntLocal" => ["var p:Int = 1;", "p"],
		"FloatLocal" => ["var p:Float = 1.5;", "p"],
		"Int32Local" => ["var p:haxe.Int32 = 1;", "p"],
		"UIntLocal" => ["var p:UInt = 1;", "p"],
		"DynamicLocal" => ["var p:Dynamic = 1;", "p"],
		"IntField" => ["final b = new Box();", "b.x"],
		"FloatField" => ["final b = new Box();", "b.f"],
		"Int32Field" => ["final b = new Box();", "b.i32"],
		"FloatAnonField" => ["final o = {f: 1.5};", "o.f"],
		"IntArrayItem" => ["final a = [1];", "a[0]"],
		"FloatArrayItem" => ["final a = [1.5];", "a[0]"]
	];

	static function main():Void {
		for (entry in [
			{name: "IntSubjectFloat", body: "var i:Int = 1; switch (i) { case 1.5: case _: }", diagnostic: "Float should be Int"},
			{name: "IntSubjectFloatInOr", body: "var i:Int = 1; switch (i) { case 1 | 2.5: case _: }", diagnostic: "Float should be Int"},
			{name: "IntSubjectWholeFloat", body: "var i:Int = 1; switch (i) { case 1.0: case _: }", diagnostic: "Float should be Int"},
			{name: "IntSubjectNegativeFloat", body: "var i:Int = 1; switch (i) { case -1.5: case _: }", diagnostic: "Float should be Int"},
			{name: "IntSubjectExponent", body: "var i:Int = 1; switch (i) { case 1e3: case _: }", diagnostic: "Float should be Int"},
			{name: "IntSubjectString", body: "var i:Int = 1; switch (i) { case \"a\": case _: }", diagnostic: "String should be Int"},
			{name: "BoolSubjectInt", body: "var b = true; switch (b) { case 1: case _: }", diagnostic: "Int should be Bool"},
			{name: "StringSubjectFloat", body: "var s:String = \"a\"; switch (s) { case 1.5: case _: }", diagnostic: "Float should be String"},
			{name: "NullIntSubjectFloat", body: "var i:Null<Int> = 1; switch (i) { case 1.5: case _: }", diagnostic: "Float should be Null<Int>"},
			{name: "Int32SubjectFloat", body: "var i:haxe.Int32 = 1; switch (i) { case 1.5: case _: }", diagnostic: "Float should be haxe.Int32"},
			{name: "UIntSubjectFloat", body: "var u:UInt = 1; switch (u) { case 1.5: case _: }", diagnostic: "Float should be UInt"},
			{name: "AbstractIntSubjectFloat", body: "var a:AInt = 1; switch (a) { case 1.5: case _: }", diagnostic: "Float should be AInt"},
			{name: "EnumAbstractSubjectFloat", body: "var e:EA = One; switch (e) { case 1.5: case _: }", diagnostic: "Float should be EA"},
			{name: "ArrayItemFloat", body: "var a = [1]; switch (a) { case [1.5]: case _: }", diagnostic: "Float should be Int"},
			{name: "AnonFieldFloat", body: "var o = {a: 1}; switch (o) { case {a: 1.5}: case _: }", diagnostic: "Float should be Int"},
			{name: "NestedAnonFieldFloat", body: "var t = {a: {b: 1}}; switch (t) { case {a: {b: 1.5}}: case _: }", diagnostic: "Float should be Int"},
			{name: "ClassFieldFloat", body: "var p = new Pt(); switch (p) { case {x: 1.5}: case _: }", diagnostic: "Float should be Int"},
			{name: "EnumPayloadFloat", body: "var e = A(1); switch (e) { case A(1.5): case _: }", diagnostic: "Float should be Int"},
			{
				name: "EnumPayloadIntForString",
				body: "var e = B(1.5, \"s\"); switch (e) { case B(1, \"s\"): case B(_, 2): case _: }",
				diagnostic: "Int should be String"
			},
			{
				name: "OptionPayloadFloat",
				body: "var o:haxe.ds.Option<Int> = Some(1); switch (o) { case Some(1.5): case _: }",
				diagnostic: "Float should be Int"
			},
			{name: "CaptureFloat", body: "var i = 1; switch (i) { case (x = 1.5): case _: }", diagnostic: "Float should be Int"},
			{name: "GuardedFloat", body: "var i:Int = 1; switch (i) { case 1.5 if (true): case _: }", diagnostic: "Float should be Int"},
			{name: "SwitchExpressionFloat", body: "var i:Int = 1; var r = switch (i) { case 1.5: 1; case _: 2; }", diagnostic: "Float should be Int"},
			// A bare enum-abstract value has the abstract's type, so its underlying Int is no path.
			{name: "BareEnumAbstractInt", body: "var e = One; switch (e) { case 1: case _: }", diagnostic: "Int should be EA"},
			// Upstream names a nullable place's own type for a bitwise operator.
			{name: "NullFloatBitwise", body: "var n:Null<Float> = 1.5; n |= 1;", diagnostic: "Null<Float> should be Int"},
			// An operator-less abstract value acts through its `to` type.
			{name: "ToStringAbstractPlusInt", body: "var s:S = \"a\"; var x = s + 1;", diagnostic: "S should be Int"},
			{name: "ToFloatAbstractOperandInt", body: "var m:M = 1; var x = m + 1;", diagnostic: "M should be Int"},
			// A `to` type is no path for a constant.
			{name: "ToOnlyAbstractInt", body: "var t:TO = cast 1; switch (t) { case 1: case _: }", diagnostic: "Int should be TO"},
			// A constant covers the enum-abstract member with the same value; coverage names the rest.
			{name: "EnumAbstractConstantPartial", body: "var e = Eins; switch (e) { case 1: }", diagnostic: "Unmatched patterns: Zwei"},
			{name: "EnumAbstractConstantNoMember", body: "var e = Eins; switch (e) { case 3: }", diagnostic: "Unmatched patterns: Eins | Zwei"},
			{name: "EnumAbstractMemberAndConstant", body: "var e = Eins; switch (e) { case Eins: case 3: }", diagnostic: "Unmatched patterns: Zwei"}
		])
			reject("Pattern" + entry.name, entry.body, entry.diagnostic);
		accept("PatternAccepted", [
			"var i:Int = 1; switch (i) { case 1: case 0x10: case -3: case _: }",
			"var f:Float = 1.5; switch (f) { case 1: case 1.5: case _: }",
			"var d:Dynamic = 1; switch (d) { case 1.5: case 1: case \"s\": case _: }",
			"var x:Any = 1; switch (x) { case 1.5: case _: }",
			"var a:AInt = 1; switch (a) { case 1: case _: }",
			"var a:AFloat = 1.5; switch (a) { case 1: case 1.5: case _: }",
			"var m:Null<Float> = 1.5; switch (m) { case 1 | 2.5 | null: case _: }",
			"var o:haxe.ds.Option<Float> = Some(1.5); switch (o) { case Some(1): case Some(2.5): case _: }",
			"var a:Array<Float> = [1.5]; switch (a) { case [1, 2.5]: case _: }",
			"var s = \"a\"; switch (s) { case \"a\" | \"b\": case _: }",
			"var c = \"x\".code; switch (c) { case \"x\".code: case _: }",
			"var i:Int = 1; switch (i) { case v if (v > 1.5): case _: }",
			// Inside `untyped`, upstream does not report a constant's kind.
			"var i:Int = 1; untyped switch (i) { case 1.5: case _: }",
			// `/` always produces Float, so these subjects are Float.
			"var i:Int = 3; switch (i / 2) { case 0.5: case _: }",
			"switch (H.half(2)) { case 0.5: case _: }",
			// A local first assigned `null` has no known type for the constant to fail against.
			"var x = null; x = 1.5; switch (x) { case 1.5: case _: }",
			// Declared `from` types are paths for a constant.
			"var m:M = 1; switch (m) { case 1: case _: }",
			"var n:N = 1; switch (n) { case 1: case _: }",
			// Constants on a `from Int` enum abstract cover its members by value.
			"var e = Eins; switch (e) { case 1: case _: }",
			"var e:EB = Eins; switch (e) { case 1: case _: }",
			"var e = Eins; switch (e) { case 1: case 2: }",
			"var e = Eins; switch (e) { case 1: case Zwei: }"
		]);
		for (row in [
			"IntLocal += 1.5 Float should be Int",
			"IntLocal -= 1.5 Float should be Int",
			"IntLocal *= 1.5 Float should be Int",
			"IntLocal /= 1 Float should be Int",
			"IntLocal /= 1.5 Float should be Int",
			"IntLocal %= 1.5 Float should be Int",
			"IntLocal <<= 1.5 Float should be Int",
			"IntLocal >>= 1.5 Float should be Int",
			"IntLocal >>>= 1.5 Float should be Int",
			"IntLocal &= 1.5 Float should be Int",
			"IntLocal |= 1.5 Float should be Int",
			"IntLocal ^= 1.5 Float should be Int",
			"FloatLocal <<= 1 Float should be Int",
			"FloatLocal <<= 1.5 Float should be Int",
			"FloatLocal >>= 1 Float should be Int",
			"FloatLocal >>= 1.5 Float should be Int",
			"FloatLocal >>>= 1 Float should be Int",
			"FloatLocal >>>= 1.5 Float should be Int",
			"FloatLocal &= 1 Float should be Int",
			"FloatLocal &= 1.5 Float should be Int",
			"FloatLocal |= 1 Float should be Int",
			"FloatLocal |= 1.5 Float should be Int",
			"FloatLocal ^= 1 Float should be Int",
			"FloatLocal ^= 1.5 Float should be Int",
			"Int32Local += 1.5 Float should be haxe.Int32",
			"Int32Local -= 1.5 Float should be haxe.Int32",
			"Int32Local *= 1.5 Float should be haxe.Int32",
			"Int32Local /= 1 Float should be haxe.Int32",
			"Int32Local /= 1.5 Float should be haxe.Int32",
			"Int32Local %= 1.5 Float should be haxe.Int32",
			"Int32Local <<= 1.5 Float should be Int",
			"Int32Local >>= 1.5 Float should be Int",
			"Int32Local >>>= 1.5 Float should be Int",
			"Int32Local &= 1.5 Float should be Int",
			"Int32Local |= 1.5 Float should be Int",
			"Int32Local ^= 1.5 Float should be Int",
			"UIntLocal += 1.5 Float should be UInt",
			"UIntLocal -= 1.5 Float should be UInt",
			"UIntLocal *= 1.5 Float should be UInt",
			"UIntLocal /= 1 Float should be UInt",
			"UIntLocal /= 1.5 Float should be UInt",
			"UIntLocal %= 1.5 Float should be UInt",
			"UIntLocal <<= 1.5 Float should be Int",
			"UIntLocal >>= 1.5 Float should be Int",
			"UIntLocal >>>= 1.5 Float should be Int",
			"UIntLocal &= 1.5 Float should be Int",
			"UIntLocal |= 1.5 Float should be Int",
			"UIntLocal ^= 1.5 Float should be Int",
			"DynamicLocal <<= 1.5 Float should be Int",
			"DynamicLocal >>= 1.5 Float should be Int",
			"DynamicLocal >>>= 1.5 Float should be Int",
			"DynamicLocal &= 1.5 Float should be Int",
			"DynamicLocal |= 1.5 Float should be Int",
			"DynamicLocal ^= 1.5 Float should be Int",
			"IntField += 1.5 Float should be Int",
			"IntField -= 1.5 Float should be Int",
			"IntField *= 1.5 Float should be Int",
			"IntField /= 1 Float should be Int",
			"IntField /= 1.5 Float should be Int",
			"IntField %= 1.5 Float should be Int",
			"IntField <<= 1.5 Float should be Int",
			"IntField >>= 1.5 Float should be Int",
			"IntField >>>= 1.5 Float should be Int",
			"IntField &= 1.5 Float should be Int",
			"IntField |= 1.5 Float should be Int",
			"IntField ^= 1.5 Float should be Int",
			"FloatField <<= 1 Float should be Int",
			"FloatField <<= 1.5 Float should be Int",
			"FloatField >>= 1 Float should be Int",
			"FloatField >>= 1.5 Float should be Int",
			"FloatField >>>= 1 Float should be Int",
			"FloatField >>>= 1.5 Float should be Int",
			"FloatField &= 1 Float should be Int",
			"FloatField &= 1.5 Float should be Int",
			"FloatField |= 1 Float should be Int",
			"FloatField |= 1.5 Float should be Int",
			"FloatField ^= 1 Float should be Int",
			"FloatField ^= 1.5 Float should be Int",
			"Int32Field += 1.5 Float should be haxe.Int32",
			"Int32Field -= 1.5 Float should be haxe.Int32",
			"Int32Field *= 1.5 Float should be haxe.Int32",
			"Int32Field /= 1 Float should be haxe.Int32",
			"Int32Field /= 1.5 Float should be haxe.Int32",
			"Int32Field %= 1.5 Float should be haxe.Int32",
			"Int32Field <<= 1.5 Float should be Int",
			"Int32Field >>= 1.5 Float should be Int",
			"Int32Field >>>= 1.5 Float should be Int",
			"Int32Field &= 1.5 Float should be Int",
			"Int32Field |= 1.5 Float should be Int",
			"Int32Field ^= 1.5 Float should be Int",
			"FloatAnonField <<= 1 Float should be Int",
			"FloatAnonField <<= 1.5 Float should be Int",
			"FloatAnonField >>= 1 Float should be Int",
			"FloatAnonField >>= 1.5 Float should be Int",
			"FloatAnonField >>>= 1 Float should be Int",
			"FloatAnonField >>>= 1.5 Float should be Int",
			"FloatAnonField &= 1 Float should be Int",
			"FloatAnonField &= 1.5 Float should be Int",
			"FloatAnonField |= 1 Float should be Int",
			"FloatAnonField |= 1.5 Float should be Int",
			"FloatAnonField ^= 1 Float should be Int",
			"FloatAnonField ^= 1.5 Float should be Int",
			"IntArrayItem += 1.5 Float should be Int",
			"IntArrayItem -= 1.5 Float should be Int",
			"IntArrayItem *= 1.5 Float should be Int",
			"IntArrayItem /= 1 Float should be Int",
			"IntArrayItem /= 1.5 Float should be Int",
			"IntArrayItem %= 1.5 Float should be Int",
			"IntArrayItem <<= 1.5 Float should be Int",
			"IntArrayItem >>= 1.5 Float should be Int",
			"IntArrayItem >>>= 1.5 Float should be Int",
			"IntArrayItem &= 1.5 Float should be Int",
			"IntArrayItem |= 1.5 Float should be Int",
			"IntArrayItem ^= 1.5 Float should be Int",
			"FloatArrayItem <<= 1 Float should be Int",
			"FloatArrayItem <<= 1.5 Float should be Int",
			"FloatArrayItem >>= 1 Float should be Int",
			"FloatArrayItem >>= 1.5 Float should be Int",
			"FloatArrayItem >>>= 1 Float should be Int",
			"FloatArrayItem >>>= 1.5 Float should be Int",
			"FloatArrayItem &= 1 Float should be Int",
			"FloatArrayItem &= 1.5 Float should be Int",
			"FloatArrayItem |= 1 Float should be Int",
			"FloatArrayItem |= 1.5 Float should be Int",
			"FloatArrayItem ^= 1 Float should be Int",
			"FloatArrayItem ^= 1.5 Float should be Int"
		]) {
			final parts = row.split(" ");
			final place = places.get(parts[0]);
			reject("Compound"
				+ parts[0]
				+ "_"
				+ operatorName(parts[1])
				+ "_"
				+ (parts[2] == "1" ? "Int" : "Float"),
				place[0]
				+ " "
				+ place[1]
				+ " "
				+ parts[1]
				+ " "
				+ parts[2]
				+ ";", parts.slice(3).join(" "));
		}
		final matrixAccepted = new Array<String>();
		for (row in [
			"IntLocal += 1",
			"IntLocal -= 1",
			"IntLocal *= 1",
			"IntLocal %= 1",
			"IntLocal <<= 1",
			"IntLocal >>= 1",
			"IntLocal >>>= 1",
			"IntLocal &= 1",
			"IntLocal |= 1",
			"IntLocal ^= 1",
			"FloatLocal += 1",
			"FloatLocal += 1.5",
			"FloatLocal -= 1",
			"FloatLocal -= 1.5",
			"FloatLocal *= 1",
			"FloatLocal *= 1.5",
			"FloatLocal /= 1",
			"FloatLocal /= 1.5",
			"FloatLocal %= 1",
			"FloatLocal %= 1.5",
			"Int32Local += 1",
			"Int32Local -= 1",
			"Int32Local *= 1",
			"Int32Local %= 1",
			"Int32Local <<= 1",
			"Int32Local >>= 1",
			"Int32Local >>>= 1",
			"Int32Local &= 1",
			"Int32Local |= 1",
			"Int32Local ^= 1",
			"UIntLocal += 1",
			"UIntLocal -= 1",
			"UIntLocal *= 1",
			"UIntLocal %= 1",
			"UIntLocal <<= 1",
			"UIntLocal >>= 1",
			"UIntLocal >>>= 1",
			"UIntLocal &= 1",
			"UIntLocal |= 1",
			"UIntLocal ^= 1",
			"DynamicLocal += 1",
			"DynamicLocal += 1.5",
			"DynamicLocal -= 1",
			"DynamicLocal -= 1.5",
			"DynamicLocal *= 1",
			"DynamicLocal *= 1.5",
			"DynamicLocal /= 1",
			"DynamicLocal /= 1.5",
			"DynamicLocal %= 1",
			"DynamicLocal %= 1.5",
			"DynamicLocal <<= 1",
			"DynamicLocal >>= 1",
			"DynamicLocal >>>= 1",
			"DynamicLocal &= 1",
			"DynamicLocal |= 1",
			"DynamicLocal ^= 1",
			"IntField += 1",
			"IntField -= 1",
			"IntField *= 1",
			"IntField %= 1",
			"IntField <<= 1",
			"IntField >>= 1",
			"IntField >>>= 1",
			"IntField &= 1",
			"IntField |= 1",
			"IntField ^= 1",
			"FloatField += 1",
			"FloatField += 1.5",
			"FloatField -= 1",
			"FloatField -= 1.5",
			"FloatField *= 1",
			"FloatField *= 1.5",
			"FloatField /= 1",
			"FloatField /= 1.5",
			"FloatField %= 1",
			"FloatField %= 1.5",
			"Int32Field += 1",
			"Int32Field -= 1",
			"Int32Field *= 1",
			"Int32Field %= 1",
			"Int32Field <<= 1",
			"Int32Field >>= 1",
			"Int32Field >>>= 1",
			"Int32Field &= 1",
			"Int32Field |= 1",
			"Int32Field ^= 1",
			"FloatAnonField += 1",
			"FloatAnonField += 1.5",
			"FloatAnonField -= 1",
			"FloatAnonField -= 1.5",
			"FloatAnonField *= 1",
			"FloatAnonField *= 1.5",
			"FloatAnonField /= 1",
			"FloatAnonField /= 1.5",
			"FloatAnonField %= 1",
			"FloatAnonField %= 1.5",
			"IntArrayItem += 1",
			"IntArrayItem -= 1",
			"IntArrayItem *= 1",
			"IntArrayItem %= 1",
			"IntArrayItem <<= 1",
			"IntArrayItem >>= 1",
			"IntArrayItem >>>= 1",
			"IntArrayItem &= 1",
			"IntArrayItem |= 1",
			"IntArrayItem ^= 1",
			"FloatArrayItem += 1",
			"FloatArrayItem += 1.5",
			"FloatArrayItem -= 1",
			"FloatArrayItem -= 1.5",
			"FloatArrayItem *= 1",
			"FloatArrayItem *= 1.5",
			"FloatArrayItem /= 1",
			"FloatArrayItem /= 1.5",
			"FloatArrayItem %= 1",
			"FloatArrayItem %= 1.5"
		]) {
			final parts = row.split(" ");
			final place = places.get(parts[0]);
			matrixAccepted.push("{ " + place[0] + " " + place[1] + " " + parts[1] + " " + parts[2] + "; }");
		}
		accept("CompoundMatrixAccepted", matrixAccepted);
		accept("CompoundAccepted", [
			"var n:Null<Int> = 1; n += 1;",
			"var i:Int = 1; var d:Dynamic = 1.5; i += d;",
			"var s = \"a\"; s += 1; s += 1.5;",
			"var f = 1.5; f += 1; f /= 2; f %= 2;",
			"var i32:haxe.Int32 = 1; i32 += 1; i32 <<= 2; i32 |= 3;",
			"var m:Money = 10; m /= 2;",
			"var u:UInt = 1; u += 1; u <<= 1;",
			"var i = 1; i >>>= 1; i ^= 3; i %= 2;",
			"var c = \"a\".code; c += 1;",
			"var i:Int = 1; i += untyped 1.5;",
			"untyped { var i:Int = 1; i |= 1.5; }",
			"untyped { var i:Int = 1; i += 1.5; }",
			"untyped { var i:Int = 1; i /= 2; }",
			"var i:Int = 3; var r = i / 2; r += 0.5;",
			"var x = TOne + 1; var y = TOne * 1.5; var i = 0; i += TOne; i |= TTwo; var f = 1.5; f += TOne;",
			"var s:S = \"a\"; var t = s + \"c\"; var u = \"n=\" + TOne;",
			"var m:M = 1; var x = m + 1.5;"
		].map(body -> "{ " + body + " }"));
		Sys.println("PATTERN_COMPOUND_KINDS:PASS");
	}

	static function operatorName(op:String):String
		return switch op {
			case "+=": "add";
			case "-=": "sub";
			case "*=": "mul";
			case "/=": "div";
			case "%=": "mod";
			case "<<=": "shl";
			case ">>=": "shr";
			case ">>>=": "ushr";
			case "&=": "and";
			case "|=": "or";
			case "^=": "xor";
			case _: throw "unknown compound operator " + op;
		};

	static function write(name:String, statements:Array<String>):String {
		final directory = root + "/" + name;
		sys.FileSystem.createDirectory(directory);
		sys.io.File.saveContent(directory
			+ "/Main.hx",
			declarations
			+ "class Main {\n\tstatic function main():Void {\n\t\t"
			+ statements.join("\n\t\t")
			+ "\n\t}\n}\n");
		return directory;
	}

	static function reject(name:String, body:String, diagnostic:String):Void {
		final directory = write(name, [body]);
		upstream(directory, diagnostic);
		var message:Null<String> = null;
		try
			CppResolvedFixture.load({sourceRoot: directory, mainModule: "Main", requiredModules: []})
		catch (error:TyperError)
			message = error.getMessage();
		if (message != diagnostic)
			throw "kind diagnostic differs for " + name + ": " + message + ", upstream " + diagnostic;
		Sys.println("PATTERN_COMPOUND_KINDS_REJECT:PASS " + name);
	}

	static function accept(name:String, statements:Array<String>):Void {
		final directory = write(name, statements);
		upstream(directory, null);
		CppResolvedFixture.load({sourceRoot: directory, mainModule: "Main", requiredModules: []});
		Sys.println("PATTERN_COMPOUND_KINDS_ACCEPT:PASS " + name);
	}

	/** The first upstream diagnostic line must end with the retained message. */
	static function upstream(directory:String, diagnostic:Null<String>):Void {
		final process = new sys.io.Process("node_modules/.bin/haxe", ["-cp", directory, "-main", "Main", "--no-output"]);
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (diagnostic == null ? code != 0 : code == 0 || !StringTools.endsWith(stderr.split("\n")[0], " : " + diagnostic))
			throw "upstream kind contract differs for " + directory + ": " + stderr;
	}
}
