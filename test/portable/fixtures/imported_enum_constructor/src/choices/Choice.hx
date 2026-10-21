package choices;

/** Imported enum whose constructors must retain their owning OCaml module. */
enum Choice {
	Empty;
	Pair(count:Int, label:String);
}
