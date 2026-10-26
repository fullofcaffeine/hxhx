import Functions;
import OtherFunctions;
import Functions.record as aliasRecord;

/** Imported Boolean calls must retain complete array-iterator types and effects. */
class Main {
	static function main():Void {
		final effects:Array<Int> = [];
		var accepted = 0;
		for (value in [
			record(effects, 1, false),
			aliasRecord(effects, 2, true),
			record(effects, 3, chosen())
		])
			if (value)
				accepted++;
		if (accepted != 2 || effects.join(",") != "1,2,3")
			throw "imported calls changed type, order or evaluation count";
		if (!Functions.classValue())
			throw "qualified ordinary static method changed";
		Sys.println("IMPORTED_MODULE_FUNCTION_ITERATOR:PASS");
	}
}
