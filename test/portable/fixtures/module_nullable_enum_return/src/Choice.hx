/** A native enum with a mutable payload exposes identity across return boundaries. */
enum Choice {
	Empty;
	Payload(values:Array<Int>);
}
