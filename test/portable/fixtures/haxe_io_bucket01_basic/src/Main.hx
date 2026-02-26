class Main {
	static function main() {
		final bytes = haxe.io.Bytes.ofString("abcdef");
		final view = haxe.io.ArrayBufferView.fromBytes(bytes, 1, 4);
		final viewSub = view.sub(1, 2);
		final viewSlice = view.subarray(2, 4);
		Sys.println("abv=" + view.byteOffset + ":" + view.byteLength + ":" + viewSub.byteOffset + ":" + viewSub.byteLength + ":" + viewSlice.byteOffset
			+ ":" + viewSlice.byteLength);

		final sourceInput = new haxe.io.StringInput("hello");
		final stagingBuffer = haxe.io.Bytes.alloc(8);
		final bufferedInput = new haxe.io.BufferInput(sourceInput, stagingBuffer);
		Sys.println("bufferinput.created=" + (bufferedInput != null));
		Sys.println("bufferinput.readByte=" + bufferedInput.readByte());

		final bytesInput = new haxe.io.BytesInput(haxe.io.Bytes.ofString("xyz"));
		final bytesInputLen = bytesInput.length;
		Sys.println("bytesinput.len=" + bytesInputLen);

		final bytesOutput = new haxe.io.BytesOutput();
		bytesOutput.writeByte("A".code);
		bytesOutput.writeString("BC", haxe.io.Encoding.UTF8);
		final bytesOutputResult = bytesOutput.getBytes().toString();
		Sys.println("bytesoutput=" + bytesOutput.length + ":" + bytesOutputResult);

		final encodingUtf8 = haxe.io.Encoding.UTF8;
		final encodingRaw = haxe.io.Encoding.RawNative;
		Sys.println("encoding=" + Std.string(encodingUtf8) + ":" + Std.string(encodingRaw));

		final f32 = haxe.io.Float32Array.fromArray([1.5, 2.25]);
		Sys.println("f32.len=" + f32.length);
		Sys.println("f32.values=" + f32[0] + ":" + f32[1]);

		final f64 = haxe.io.Float64Array.fromArray([3.5, 4.75]);
		Sys.println("f64.len=" + f64.length);
		Sys.println("f64.values=" + f64[0] + ":" + f64[1]);

		final i32 = haxe.io.Int32Array.fromArray([10, 20]);
		Sys.println("i32.len=" + i32.length);
		Sys.println("i32.values=" + i32[0] + ":" + i32[1]);

		Sys.println("mime=" + haxe.io.Mime.ApplicationJson);
		Sys.println("scheme=" + haxe.io.Scheme.Https);

		final stringInput = new haxe.io.StringInput("ok");
		Sys.println("stringinput.created=" + (stringInput != null));

		final u16 = haxe.io.UInt16Array.fromArray([65535, 7]);
		Sys.println("u16.len=" + u16.length);
		Sys.println("u16.values=" + u16[0] + ":" + u16[1]);
	}
}
