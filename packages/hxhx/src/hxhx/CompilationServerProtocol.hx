package hxhx;

/**
	Safety rules shared by the native compiler-server transports.

	A compiler request may include command-line arguments and an unsaved editor
	buffer. The server accepts at most 64 MiB for that complete request. This is
	large enough for ordinary compiler and editor traffic while preventing a
	broken or untrusted local client from growing the long-lived process without
	a bound before compilation begins.
**/
class CompilationServerProtocol {
	public static inline final MAX_REQUEST_BYTES:Int = 64 * 1024 * 1024;

	/** Return a user-facing problem for an invalid frame length, or `null`. **/
	public static function requestLengthProblem(length:Int):Null<String> {
		if (length < 0)
			return "negative request frame length " + length;
		if (length > MAX_REQUEST_BYTES)
			return "request frame is " + length + " bytes; maximum is " + MAX_REQUEST_BYTES;
		return null;
	}
}
