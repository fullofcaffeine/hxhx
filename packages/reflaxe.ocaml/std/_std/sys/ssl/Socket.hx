package sys.ssl;

/**
	OCaml target override for `sys.ssl.Socket`.

	Why
	- The upstream eval implementation depends on `eval.vm.NativeSocket`, which is
	  not available in the cross/portable compilation lane.
	- We provide a concrete compatibility surface so `sys.Http` and stdlib probes
	  can type-check/run without pulling eval-only internals.

	What
	- Preserves the public API shape of `sys.ssl.Socket`.
	- Constructor succeeds; SSL/network operations throw "Not available on this platform".
**/
class Socket extends sys.net.Socket {
	public static var DEFAULT_VERIFY_CERT:Null<Bool> = true;
	public static var DEFAULT_CA:Null<Certificate> = null;

	public var verifyCert:Null<Bool>;

	public function new():Void {
		super();
		verifyCert = DEFAULT_VERIFY_CERT;
	}

	public function handshake():Void {
		throw "Not available on this platform";
	}

	public function setCA(cert:Certificate):Void {
		DEFAULT_CA = cert;
	}

	public function setHostname(name:String):Void {}

	public function setCertificate(cert:Certificate, key:Key):Void {
		throw "Not available on this platform";
	}

	public function addSNICertificate(cbServernameMatch:String->Bool, cert:Certificate, key:Key):Void {
		throw "Not available on this platform";
	}

	public function peerCertificate():Certificate {
		throw "Not available on this platform";
	}
}
