/** Independently authored helpers for the array-element generic declaration rule. */
class ArrayCases {
	/** Valid: saves a copy and compares owned elements inside a returned closure. */
	public static function unchanged<T>(read:() -> Array<T>):() -> Bool {
		final saved = read().copy();
		return function() {
			final current = read();
			if (current.length != saved.length)
				return false;
			for (index in 0...saved.length)
				if (saved[index] != current[index])
					return false;
			return true;
		};
	}

	/** Printing an element needs an erased-value contract instead. */
	public static function printed<T>(read:() -> Array<T>):Int {
		final values = read();
		Sys.println(values[0]);
		return values.length;
	}

	/** Adding elements changes storage, which this rule does not prove. */
	public static function grown<T>(read:() -> Array<T>):Int {
		final values = read();
		values.push(values[0]);
		return values.length;
	}

	/** Writing an element changes storage, which this rule does not prove. */
	public static function written<T>(read:() -> Array<T>):Int {
		final values = read();
		values[0] = values[1];
		return values.length;
	}

	/** Passing the array to an arbitrary call lets it escape the element slot. */
	public static function escaped<T>(read:() -> Array<T>):Int {
		return Lambda.count(read());
	}

	/** Returning an element needs a polymorphic result proof. */
	public static function element<T>(read:() -> Array<T>):T {
		return read()[0];
	}

	/** An alias of the callback is not the declared callback. */
	public static function aliasedCallback<T>(read:() -> Array<T>):Int {
		final again = read;
		return again().length;
	}

	/** Reassigning a carrier local is outside the immutable binding rule. */
	public static function reassigned<T>(read:() -> Array<T>):Int {
		var values = read();
		values = read();
		return values.length;
	}

	/** A nested function cannot return an owned element. */
	public static function nestedElement<T>(read:() -> Array<T>):Int {
		final first = () -> read()[0];
		first();
		return 0;
	}

	/** Comparing an element with a value of another type is not an owned comparison. */
	public static function mixed<T>(read:() -> Array<T>, other:Dynamic):Bool {
		return read()[0] == other;
	}

	/** A forwarding declaration has the other kind's proof, not this one. */
	public static function forwarded<T>(body:() -> T):T {
		return body();
	}
}

/** Valid module function: owns a different T although the short name matches. */
function sameEnds<T>(read:() -> Array<T>):Bool {
	final values = read();
	return values.length > 0 && values[0] == values[values.length - 1];
}
