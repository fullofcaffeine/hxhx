/**
	Recovering a structural view preserves the original value until a field is used.
	Dynamic appears only at the conversion boundary under test. Assignment does not
	validate field contents, allocate a copy, or discard fields outside the view.
	Invalid field calls are deliberately separate from this assignment contract.
 */
class RecoveryContract {
	static var conversions:Int = 0;

	static function recover(value:Dynamic):{item:() -> Int} {
		conversions++;
		return value;
	}

	/** Observe the stored values without requiring structural-width operator selection. */
	static function identical(left:Dynamic, right:Dynamic):Bool {
		return left == right;
	}

	static function same(value:Dynamic):Void {
		final recovered = recover(value);
		if (!identical(recovered, value))
			throw "structural recovery changed the stored value";
	}

	static function main():Void {
		// These values are legal assignments. Their later accesses have distinct
		// behavior and must not be eagerly executed or validated by recovery.
		same({item: 7, extra: true});
		same({extra: true});
		same({item: "text"});
		same({item: null});
		same(null);
		same(7);
		same("text");
		same([1]);
		same({item: () -> 9});

		var captured = 3;
		final original = {item: () -> captured, extra: 11};
		final recovered = recover(original);
		captured = 7;
		if (!identical(recovered, original) || recovered.item() != 7 || original.extra != 11)
			throw "structural recovery lost identity, capture, or an extra field";
		recovered.item = () -> captured + 1;
		if (original.item() != 8 || conversions != 10)
			throw "structural recovery copied storage or repeated conversion";
	}
}
