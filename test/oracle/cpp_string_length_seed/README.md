# Native C++ String length

Ordinary `String.length` reads use the native text representation. A String
does not need an allocated class instance to expose its length.

Haxe 4.3.7 with hxcpp 4.3.2 produced the eleven lines in `expected.stdout`.
The independently authored reference covers empty text, ASCII, accented text,
an emoji, combining characters, embedded zeroes, null, receiver effects, and
a same-named field on an ordinary class.

With those upstream tools configured, run:

```sh
haxe -cp test/oracle/cpp_string_length_seed -main Main \
  -cpp .tmp/upstream-string-length -D HXCPP_COMPILE_THREADS=2
.tmp/upstream-string-length/Main
```

Native C++ counts UTF-16 units: `"Aé😀Z"` has length five. The emoji contributes
two units. An embedded zero contributes one, and a null String has length zero.
The interpreter uses a different Unicode representation, so its output is not
the reference for this native contract.

Run the compiler regression with:

```sh
haxe test/m14_cpp_string_length_test.hxml
```

The test loads real String declarations and emits C++ from authored Haxe.
It rejects copied field expressions, a changed owning body, and a same-named
user field presented as the standard field. A native observer checks lengths,
once-only receiver evaluation, failure order, and root cleanup.
Both O0 and O2 profiles use address and undefined-behavior sanitizers.

The runtime reuses its UTF-8 scalar decoder and counts units without allocating
a converted string. It checks the Int limit before incrementing the result.
Malformed foreign bytes remain rejected by the existing decoder. This fixture
does not establish parity for separate foreign input codecs or other String fields.
