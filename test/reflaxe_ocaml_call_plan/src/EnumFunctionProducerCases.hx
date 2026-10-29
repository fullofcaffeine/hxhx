/** Distinguishes an unchanged function literal from a replaced local function. */
class EnumFunctionProducerCases {
	public static function unchanged(flag:Bool):Void {
		final producer = function():Null<PreliminaryCallFactsEnum> {
			if (flag)
				return null;
			return Ready;
		};
		final result = producer();
	}

	public static function reassigned(flag:Bool, replacement:Void->Null<PreliminaryCallFactsEnum>):Void {
		var producer = function():Null<PreliminaryCallFactsEnum> {
			if (flag)
				return null;
			return Ready;
		};
		producer = replacement;
		final result = producer();
	}

	public static function capturedWrite(flag:Bool, replacement:Void->Null<PreliminaryCallFactsEnum>):Void {
		var producer = function():Null<PreliminaryCallFactsEnum> {
			if (flag)
				return null;
			return Ready;
		};
		final replace = function():Void {
			producer = replacement;
		};
		replace();
		final result = producer();
	}
}
