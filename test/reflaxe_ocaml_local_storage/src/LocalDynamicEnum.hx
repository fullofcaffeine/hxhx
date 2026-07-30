/** Ordinary Haxe enum used to prove the exact enum-to-Dynamic carrier seam. */
enum LocalDynamicEnum {
	Idle;
	Payload(value:Int);
}
