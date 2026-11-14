///|
/// The file and process layer the command line tool stands on.
///
/// The tool is the one part of this module that touches the outside world:
/// it reads a file, it writes a file, and it starts a browser. Everything
/// else - the Markdown parser, the Mermaid reader, the page layout - is
/// pure, and runs on every target.
///
/// So the layer is written as a set of plain functions with one contract,
/// and every target brings its own implementation of it:
///
///   io_native.mbt    native and wasm: the file system and the process
///                    runtime of the toolchain, driven to completion from a
///                    synchronous caller
///   io_js.mbt        js: Node's own file system and process modules
///   io_wasm_gc.mbt   wasm-gc: the file system bridge of the wasm host
///
/// The contract, the same on every target:
///
///   io_exists         whether a path is there
///   io_first_existing the first path of a list that is there
///   io_read_text      the content of a file, or None when it cannot be read
///   io_write_text     write a file, and say whether it was written
///   io_remove         take a file away, and say whether it is gone
///   io_file_size      the size of a file in bytes, or -1
///   io_run            run a program, and collect what it said
///
/// Nothing here raises. A failure is a value, so the caller decides what to
/// do with it and the exit code can be set from one place - which is what
/// makes the tool's own error model the same on every target.

///|
/// What running a program produced.
///
/// The three parts are kept apart because they are not interchangeable: the
/// exit code says whether it worked, the output is what it drew, and the
/// error output is what it complained about.
priv struct IoResult {
  code : Int32
  out : String
  err : String
}
