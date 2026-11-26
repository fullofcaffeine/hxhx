/** A cast method without a written return type: its result is inferred from the body. */
abstract Length(Int) {
	public function new(v)
		this = v;

	@:from static function ofString(s:String)
		return new Length(s.length);

	public function get()
		return this;
}
