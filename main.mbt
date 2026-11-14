///|
/// The module's entry point: the command line tool lives in src/mdcli, and
/// this package is only the executable that runs it.
///
/// The tool is synchronous on every target, so the entry point is a plain
/// `fn main`: native, wasm, js and wasm-gc all start the same way. An
/// `async fn main` would be the one thing wasm-gc cannot do - the host it
/// runs on has no async runtime to start.

///|
fn main {
  @mdcli.run(@env.args())
}
