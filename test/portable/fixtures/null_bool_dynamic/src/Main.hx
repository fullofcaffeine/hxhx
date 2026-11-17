class Main {
	static function describe(label:String, value:Dynamic):Void {
		Sys.println(label + "=" + Std.string(value) + " bool=" + Std.isOfType(value, Bool) + " int=" + Std.isOfType(value, Int));
	}

	static function main() {
		var yes:Null<Bool> = (true : Null<Bool>);
		var no:Null<Bool> = (false : Null<Bool>);
		var none:Null<Bool> = null;
		var dynamicYes:Dynamic = yes;
		var dynamicNo:Dynamic = no;
		var dynamicNone:Dynamic = none;
		describe("yes", dynamicYes);
		describe("no", dynamicNo);
		Sys.println("none=" + (dynamicNone == null));
		var anyYes:Any = yes;
		Sys.println("any=" + Std.string(anyYes));
		var back:Null<Bool> = dynamicYes;
		Sys.println("back=" + back);
		var plain:Bool = dynamicNo;
		Sys.println("plain=" + plain);
		Sys.println("cast=" + Std.string((yes : Dynamic)));
	}
}
