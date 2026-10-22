import Main.Choice;
import Main.Other;

/** Observe upstream values independently of the candidate compiler's target representation. */
class OracleMain {
	static function main():Void {
		Main.main();
		Sys.println(Main.empty == Main.alias);
		Sys.println(Main.absent == null);
		Sys.println(Type.enumIndex(Main.empty));
		Sys.println(Type.enumIndex(Main.payload));
		Sys.println(Type.enumConstructor(Main.payload));
		switch Main.payload {
			case Carry(values):
				Sys.println(values[0]);
			case Empty:
				throw "payload constructor lost";
		}
		Sys.println(Type.getEnumName(Type.getEnum(Main.empty)));
		Sys.println(Type.getEnumName(Type.getEnum(Main.other)));
		Sys.println(Main.enumWasNullDuringStartup);
	}
}
