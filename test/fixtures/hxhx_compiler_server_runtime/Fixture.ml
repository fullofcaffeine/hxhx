let reserve_loopback_port () =
  let socket = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  Unix.bind socket (Unix.ADDR_INET (Unix.inet_addr_loopback, 0));
  let port =
    match Unix.getsockname socket with
    | Unix.ADDR_INET (_, port) -> port
    | Unix.ADDR_UNIX _ -> failwith "expected a loopback TCP address"
  in
  Unix.close socket;
  port

let pause seconds =
  ignore (Unix.select [] [] [] seconds)

let connect_with_retry endpoint =
  let rec loop attempts =
    try HxHxCompilerServer.connect endpoint "trigger-handler-error"
    with
    | Unix.Unix_error ((Unix.ECONNREFUSED | Unix.ENOENT), _, _) when attempts > 0 ->
        pause 0.05;
        loop (attempts - 1)
    | HxRuntime.Hx_exception (_, tags)
      when attempts > 0 && HxRuntime.tags_has tags "String" ->
        pause 0.05;
        loop (attempts - 1)
  in
  loop 100

let raw_exchange endpoint payload =
  let host, port = HxHxCompilerServer.split_host_port endpoint in
  let sock = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  Unix.connect sock (Unix.ADDR_INET (HxHxCompilerServer.resolve_host host, port));
  HxHxCompilerServer.send_all sock payload;
  Unix.shutdown sock Unix.SHUTDOWN_SEND;
  let response = HxHxCompilerServer.read_all sock in
  Unix.close sock;
  response

let starts_with_control_error response =
  String.length response > 0 && Char.code response.[0] = 0x02

let contains text needle =
  let text_length = String.length text in
  let needle_length = String.length needle in
  let rec loop index =
    if index + needle_length > text_length then false
    else if String.sub text index needle_length = needle then true
    else loop (index + 1)
  in
  needle_length = 0 || loop 0

let expect_haxe_string_exception label run required_text =
  let received = ref None in
  (try run () with
  | HxRuntime.Hx_exception (value, tags) ->
      if not (HxRuntime.tags_has tags "String") then
        failwith (label ^ " did not carry the Haxe String type tag");
      received := Some (Obj.obj value : string));
  match !received with
  | None -> failwith (label ^ " did not raise a Haxe String exception")
  | Some message ->
      if not (contains message required_text) then
        failwith (label ^ " lacked useful context: " ^ message)

let verify_occupied_endpoint_error () =
  let owner = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  Fun.protect
    ~finally:(fun () -> try Unix.close owner with _ -> ())
    (fun () ->
      Unix.bind owner (Unix.ADDR_INET (Unix.inet_addr_loopback, 0));
      Unix.listen owner 1;
      let port =
        match Unix.getsockname owner with
        | Unix.ADDR_INET (_, port) -> port
        | Unix.ADDR_UNIX _ -> failwith "expected a loopback TCP address"
      in
      let endpoint = "127.0.0.1:" ^ string_of_int port in
      expect_haxe_string_exception
        "occupied wait endpoint"
        (fun () ->
          ignore (HxHxCompilerServer.waitSocket endpoint 32 (fun request -> request) (fun () -> false)))
        "Address already in use";
      match Unix.getsockname owner with
      | Unix.ADDR_INET (_, actual_port) when actual_port = port -> ()
      | _ -> failwith "occupied endpoint owner was disturbed")

let () =
  verify_occupied_endpoint_error ();
  let port = reserve_loopback_port () in
  let endpoint = "127.0.0.1:" ^ string_of_int port in
  let child_reaped = ref false in
  let child =
    Unix.fork ()
  in
  if child = 0 then (
    let stop = ref false in
    ignore
      (HxHxCompilerServer.waitSocket endpoint 32 (fun request ->
           if request = "trigger-handler-error" then failwith "fixture-handler-exploded"
           else if request = "shutdown" then (
             stop := true;
             "stopping")
           else "handled:" ^ request)
         (fun () ->
           let requested = !stop in
           stop := false;
           requested));
    exit 0)
  else
    Fun.protect
      ~finally:(fun () ->
        if not !child_reaped then (
          (try Unix.kill child Sys.sigterm with Unix.Unix_error (Unix.ESRCH, _, _) -> ());
          try ignore (Unix.waitpid [] child) with Unix.Unix_error (Unix.ECHILD, _, _) -> ()))
      (fun () ->
        let response = connect_with_retry endpoint in
        if not (starts_with_control_error response) then
          failwith "handler exception did not produce the Haxe error control byte";
        if not (contains response "socket request handler failed") then
          failwith ("handler exception response lacked context: " ^ response);
        if not (contains response "fixture-handler-exploded") then
          failwith ("handler exception response lacked the original failure: " ^ response);

        let oversized = raw_exchange endpoint (String.make 33 'x' ^ "\000") in
        if not (starts_with_control_error oversized) then
          failwith "oversized request did not produce the Haxe error control byte";
        if not (contains oversized "exceeds 32 bytes") then
          failwith ("oversized request response lacked its limit: " ^ oversized);

        let truncated = raw_exchange endpoint "unterminated" in
        if not (starts_with_control_error truncated) then
          failwith "unterminated request did not produce the Haxe error control byte";
        if not (contains truncated "before its NUL terminator") then
          failwith ("unterminated request response lacked context: " ^ truncated);

        let recovered = HxHxCompilerServer.connect endpoint "ok" in
        if recovered <> "handled:ok" then
          failwith ("server did not recover after malformed clients: " ^ recovered);

        let shutdown = HxHxCompilerServer.connect endpoint "shutdown" in
        if shutdown <> "stopping" then
          failwith ("shutdown response was not sent before exit: " ^ shutdown);
        let _, status = Unix.waitpid [] child in
        child_reaped := true;
        (match status with
        | Unix.WEXITED 0 -> ()
        | _ -> failwith "socket server did not exit cleanly after shutdown");
        print_endline "HXHX_COMPILER_SERVER_RUNTIME_FIXTURE:PASS")
