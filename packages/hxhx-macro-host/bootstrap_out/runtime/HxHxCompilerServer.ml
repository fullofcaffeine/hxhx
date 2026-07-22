(* HXHX Stage3 compiler-server socket bridge.

   Why
   - Stage3 currently needs `--wait <host:port>` / `--connect <host:port>` transport support,
     but bootstrap codegen does not yet reliably access `sys.net.Socket.input/output` from Haxe.

   What
   - [waitSocket mode max_request_bytes handle_request should_stop]:
       start a socket server, read bounded null-terminated request frames, and
       pass each valid payload to the Haxe-owned shared request dispatcher.
       After sending a reply, ask the Haxe owner whether the server should stop.
   - [connect mode request]:
       send one null-terminated request frame and return the raw response bytes.

   Native socket failures are converted to Haxe String exceptions at this
   boundary. This lets the Haxe caller give users one consistent, readable
   error instead of leaking an OCaml Unix exception and backtrace.

   Scope
   - This bridge owns socket/process operations only. It does not decide whether
     a request compiles code, serves editor data, succeeds, or fails.
*)

let transport_error_message (exn : exn) : string =
  match exn with
  | Unix.Unix_error (error, operation, argument) ->
      let attempted =
        if argument = "" then operation else operation ^ " " ^ argument
      in
      attempted ^ " failed: " ^ Unix.error_message error
  | Failure message | Invalid_argument message | Sys_error message -> message
  | exn -> Printexc.to_string exn

let raise_haxe_string (exn : exn) : 'a =
  HxRuntime.hx_throw_typed
    (Obj.repr (transport_error_message exn))
    [ "Dynamic"; "String" ]

let protect_transport (run : unit -> 'a) : 'a =
  try run () with
  | HxRuntime.Hx_exception _ as exn -> raise exn
  | HxRuntime.Hx_break -> raise HxRuntime.Hx_break
  | HxRuntime.Hx_continue -> raise HxRuntime.Hx_continue
  | HxRuntime.Hx_return value -> raise (HxRuntime.Hx_return value)
  | exn -> raise_haxe_string exn

let split_host_port (mode : string) : string * int =
  let trimmed = Stdlib.String.trim mode in
  if trimmed = "" then failwith "missing host/port value";
  let host, port_s =
    match Stdlib.String.rindex_opt trimmed ':' with
    | None -> ("127.0.0.1", trimmed)
    | Some idx ->
        let h = Stdlib.String.sub trimmed 0 idx |> Stdlib.String.trim in
        let p =
          Stdlib.String.sub trimmed (idx + 1) (Stdlib.String.length trimmed - idx - 1)
          |> Stdlib.String.trim
        in
        let h = if h = "" then "127.0.0.1" else h in
        (h, p)
  in
  let port =
    try int_of_string port_s with _ -> failwith ("invalid port: " ^ port_s)
  in
  if port <= 0 || port > 65535 then failwith ("invalid port: " ^ port_s);
  (host, port)

let resolve_host (host : string) : Unix.inet_addr =
  try Unix.inet_addr_of_string host
  with _ ->
    let entry = Unix.gethostbyname host in
    if Stdlib.Array.length entry.Unix.h_addr_list = 0 then
      failwith ("cannot resolve host: " ^ host)
    else Stdlib.Array.get entry.Unix.h_addr_list 0

let send_all (sock : Unix.file_descr) (payload : string) : unit =
  let bytes = Bytes.unsafe_of_string payload in
  let rec loop off len =
    if len > 0 then
      let sent = Unix.send sock bytes off len [] in
      if sent <= 0 then failwith "socket send failed" else loop (off + sent) (len - sent)
  in
  loop 0 (Bytes.length bytes)

let error_reply (message : string) : string = "\002\n" ^ message ^ "\n"

let protocol_error (message : string) : string =
  error_reply ("hxhx(stage3): socket request rejected: " ^ message)

let read_until_nul (sock : Unix.file_descr) (max_request_bytes : int) : string =
  if max_request_bytes <= 0 then failwith "maximum request size must be positive";
  let tmp = Bytes.create 4096 in
  let out = Buffer.create 256 in
  let out_length = ref 0 in
  let rec loop () =
    let n = Unix.recv sock tmp 0 4096 [] in
    if n = 0 then failwith "request frame ended before its NUL terminator"
    else
      let stop = ref false in
      let i = ref 0 in
      while !i < n && not !stop do
        let c = Bytes.get tmp !i in
        if c = '\000' then stop := true
        else if !out_length >= max_request_bytes then
          failwith
            ("request frame exceeds " ^ string_of_int max_request_bytes ^ " bytes")
        else (
          Buffer.add_char out c;
          incr out_length);
        incr i
      done;
      if !stop then Buffer.contents out else loop ()
  in
  loop ()

let read_all (sock : Unix.file_descr) : string =
  let tmp = Bytes.create 4096 in
  let out = Buffer.create 256 in
  let rec loop () =
    let n = Unix.recv sock tmp 0 4096 [] in
    if n = 0 then Buffer.contents out
    else (
      Buffer.add_subbytes out tmp 0 n;
      loop ())
  in
  loop ()

let waitSocket
    (mode : string)
    (max_request_bytes : int)
    (handle_request : string -> string)
    (should_stop : unit -> bool) : int =
  protect_transport (fun () ->
      let host, port = split_host_port mode in
      let addr = resolve_host host in
      let listener = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
      Fun.protect
        ~finally:(fun () -> try Unix.close listener with _ -> ())
        (fun () ->
          (try Unix.setsockopt listener Unix.SO_REUSEADDR true with _ -> ());
          Unix.bind listener (Unix.ADDR_INET (addr, port));
          Unix.listen listener 10;
          let running = ref true in
          while !running do
            let client, _ = Unix.accept listener in
            (try
               let reply =
                 try
                   let request = read_until_nul client max_request_bytes in
                   (try handle_request request
                    with exn ->
                      error_reply
                        ("hxhx(stage3): socket request handler failed: "
                        ^ Printexc.to_string exn))
                 with exn -> protocol_error (Printexc.to_string exn)
               in
               let response_delivered =
                 try
                   send_all client reply;
                   true
                 with _ -> false
               in
               let stop_requested = should_stop () in
               if response_delivered && stop_requested then running := false
             with _ -> ());
            (try Unix.close client with _ -> ())
          done;
          0))

let connect (mode : string) (request : string) : string =
  protect_transport (fun () ->
      let host, port = split_host_port mode in
      let addr = resolve_host host in
      let sock = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
      Fun.protect
        ~finally:(fun () -> try Unix.close sock with _ -> ())
        (fun () ->
          Unix.connect sock (Unix.ADDR_INET (addr, port));
          send_all sock (request ^ "\000");
          read_all sock))
