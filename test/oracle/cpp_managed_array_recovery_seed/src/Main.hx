/** Black-box boundary probe: Dynamic is confined to the source under observation. */
class Main {
	static function recover(label:String, value:Dynamic):Void {
		try {
			final result:Array<Bool> = value;
			Sys.println(label + ":assigned:" + (result == null));
			if (result != null)
				Sys.println(label + ":first:" + result[0]);
		} catch (error:Dynamic) {
			Sys.println(label + ":caught");
		}
	}

	static function main():Void {
		recover("null", null);
		recover("record", {value: true});
		recover("scalar", 7);
		recover("bool", [true]);
		recover("int", [1]);
		final original = [true];
		final erased:Dynamic = original;
		final recovered:Array<Bool> = erased;
		recovered[0] = false;
		Sys.println("alias:" + original[0]);
		final integers = [0, -1, 2];
		final erasedIntegers:Dynamic = integers;
		final booleans:Array<Bool> = erasedIntegers;
		Sys.println("int-values:" + booleans[0] + ":" + booleans[1] + ":" + booleans[2]);
		booleans[0] = true;
		Sys.println("int-alias:" + integers[0]);
		final mixed:Array<Dynamic> = [true];
		final erasedMixed:Dynamic = mixed;
		final fromMixed:Array<Bool> = erasedMixed;
		fromMixed[0] = false;
		Sys.println("mixed-alias:" + mixed[0]);
		final emptyBool:Array<Bool> = [];
		final erasedEmptyBool:Dynamic = emptyBool;
		final boolResult:Array<Bool> = erasedEmptyBool;
		boolResult.push(true);
		Sys.println("empty-bool:" + emptyBool.length);
		final emptyInt:Array<Int> = [];
		final erasedEmptyInt:Dynamic = emptyInt;
		final intResult:Array<Bool> = erasedEmptyInt;
		intResult.push(true);
		Sys.println("empty-int:" + emptyInt.length);
		final emptyDynamic:Array<Dynamic> = [];
		final erasedEmptyDynamic:Dynamic = emptyDynamic;
		final dynamicResult:Array<Bool> = erasedEmptyDynamic;
		dynamicResult.push(true);
		Sys.println("empty-dynamic:" + emptyDynamic.length);
		final heterogeneous:Array<Dynamic> = [true, 2];
		final erasedHeterogeneous:Dynamic = heterogeneous;
		final heterogeneousResult:Array<Bool> = erasedHeterogeneous;
		Sys.println("heterogeneous-values:" + heterogeneousResult[0] + ":" + heterogeneousResult[1]);
		heterogeneousResult[0] = false;
		heterogeneousResult.push(true);
		Sys.println("heterogeneous-alias:" + heterogeneous[0] + ":" + heterogeneous.length);
		final widening:Array<Dynamic> = [true];
		final erasedWidening:Dynamic = widening;
		final wideningResult:Array<Bool> = erasedWidening;
		widening.push(2);
		Sys.println("widening:" + widening.length + ":" + wideningResult.length + ":" + wideningResult[0]);
	}
}
