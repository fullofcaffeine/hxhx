# Escaping iteration captures

Run `haxe test/m14_js_iteration_capture_test.hxml`.
The same authored assertions run through upstream and candidate JavaScript. They observe
distinct iteration values, writes after capture, sharing between readers and writers,
range and array loops, nested forwarding, and the instance receiver.
The candidate must retain ES5-compatible output and exact typed capture ownership.
