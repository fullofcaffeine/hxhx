package;

import contract.ContractBox;

/** Supplies a small typed program to the custom-generator contract fixture. */
class Main {
	public static final valueProbe:Int = 7;

	public static function main():Void {
		final box:ContractBox<String> = new ContractBox("fixture");
		trace(box.read());
	}
}
