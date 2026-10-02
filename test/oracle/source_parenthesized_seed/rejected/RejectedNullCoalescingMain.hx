/** Parentheses around a null-coalescing assignment destination are not writable. */
class RejectedNullCoalescingMain {
	static function main():Void {
		var value:Null<Int> = null;
		(value) ??= 4;
	}
}
