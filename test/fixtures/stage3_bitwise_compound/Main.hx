import haxe.Int32;

class Flags {
	public var bits:Int;
	public var bits32:Int32;

	public function new(bits:Int) {
		this.bits = bits;
		this.bits32 = bits;
	}

	/** Implicit-receiver field updates inside an instance method. */
	public function mix(mask:Int):Int {
		bits ^= mask;
		return bits <<= 1;
	}
}

class Main {
	static function amount(label:String, value:Int):Int {
		Sys.print("[" + label + "]");
		return value;
	}

	static function main():Void {
		// Locals in statement position, including negative values and shift masking.
		var x = 3;
		x <<= 2;
		x |= 1;
		x ^= 4;
		x >>= 1;
		Sys.println("local " + x);
		var negative = -20;
		negative >>= 2;
		final signed = negative;
		negative = -20;
		negative >>>= 28;
		final unsigned = negative;
		var masked = 1;
		masked <<= 33;
		var all = 0xFF;
		all &= 0x0F;
		Sys.println("signs " + signed + " " + unsigned + " " + masked + " " + all);

		// Locals in value position: the stored value is the result, and the old
		// value is read before the right operand runs.
		var y = 3;
		final r = (y <<= 2);
		Sys.println("value " + r + " " + y);
		var z = 5;
		final ordered = (z |= amount("rhs", 2));
		Sys.println(" ordered " + ordered + " " + z);
		var dynamicBits:Dynamic = 3;
		dynamicBits |= 4;
		dynamicBits <<= 1;
		Sys.println("dynamic " + dynamicBits);
		var nullable:Null<Int> = 12;
		nullable &= 10;
		Sys.println("nullable " + nullable);

		// Instance, implicit-receiver, anonymous-object and array targets. Static fields
		// need mutable static storage first (haxe_ocaml-nq65n, haxe_ocaml-8k5ja).
		final flags = new Flags(5);
		flags.bits |= 2;
		flags.bits &= 6;
		final fieldValue = (flags.bits ^= 1);
		Sys.println("field " + flags.bits + " " + fieldValue + " " + flags.mix(3));
		final anon = {mask: 9};
		anon.mask |= 6;
		anon.mask >>= 1;
		Sys.println("anon " + anon.mask + " " + (anon.mask &= 3));
		anon.mask += 10;
		Sys.println("anon arithmetic " + anon.mask + " " + (anon.mask -= 4));
		final cells = [1, 2, 3];
		cells[0] <<= 4;
		cells[1] |= 8;
		cells[2] ^= 1;
		Sys.println("array " + cells.join(",") + " " + (cells[0] >>= 2));

		// Int `%=` keeps the sign of the dividend on every target.
		flags.bits = 7;
		flags.bits %= 4;
		final remainder = {value: -7};
		remainder.value %= 3;
		final remainders = [9, -9];
		remainders[0] %= 4;
		remainders[1] %= 4;
		var localRemainder = -10;
		localRemainder %= 3;
		Sys.println("remainder "
			+ flags.bits
			+ " "
			+ remainder.value
			+ " "
			+ remainders.join(",")
			+ " "
			+ localRemainder
			+ " "
			+ (remainders[0] %= 2));

		// haxe.Int32 targets: 32-bit wrapping on every update.
		var word:Int32 = 0x40000000;
		word <<= 1;
		final shifted = word;
		word >>>= 4;
		word |= 3;
		word ^= 0x7;
		Sys.println("int32 local " + shifted + " " + word + " " + (word &= 0xFF));
		flags.bits32 <<= 30;
		final field32 = flags.bits32;
		Sys.println("int32 field " + field32 + " " + (flags.bits32 |= 8));
		final words:Array<Int32> = [1, 0x7FFFFFFF];
		words[0] <<= 31;
		words[1] ^= -1;
		Sys.println("int32 array " + words[0] + " " + words[1]);
		final anon32:{value:Int32} = {value: 3};
		anon32.value <<= 30;
		Sys.println("int32 anon " + anon32.value + " " + (anon32.value >>>= 30));
	}
}
