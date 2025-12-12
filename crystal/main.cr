require "json"

@[Link("sorbet")]
lib LibSorbet
  type Session = Void*

  # Standard API
  fun new = sorbet_new(args : LibC::Char*) : Session
  fun send = sorbet_send(session : Session, msg : LibC::Char*) : LibC::Char*

  # PERFORMANCE: Multi-threaded API
  fun new_mt = sorbet_new_mt(args : LibC::Char*, num_threads : Int32) : Session

  # PERFORMANCE: Batch API
  fun send_batch = sorbet_send_batch(session : Session, msgs : LibC::Char**, count : Int32) : LibC::Char*

  # Memory management
  fun free_string = sorbet_free_string(str : LibC::Char*)
  fun free = sorbet_free(session : Session)
end

class SorbetClient
  def initialize
    # Initialize with default args. silence-dev-message prevents startup noise.
    args = ["--silence-dev-message", "."].to_json
    @session = LibSorbet.new(args)
    if @session.null?
      raise "Failed to initialize Sorbet session"
    end
    
    perform_handshake
  end

  def perform_handshake
    # 1. initialize request
    init_msg = {
      jsonrpc: "2.0",
      id: 1,
      method: "initialize",
      params: {
        rootUri: "file://#{Dir.current}",
        capabilities: {} of String => String
      }
    }.to_json

    response_ptr = LibSorbet.send(@session, init_msg)
    # Free the response string after use
    LibSorbet.free_string(response_ptr) unless response_ptr.null?

    # 2. initialized notification
    initialized_msg = {
      jsonrpc: "2.0",
      method: "initialized",
      params: {} of String => String
    }.to_json

    response_ptr = LibSorbet.send(@session, initialized_msg)
    # Free the response string after use
    LibSorbet.free_string(response_ptr) unless response_ptr.null?
  end

  def typecheck(file_path : String, content : String)
    # 1. Open the file (send didOpen)
    msg = {
        jsonrpc: "2.0",
        method: "textDocument/didOpen",
        params: {
            textDocument: {
                uri: "file://#{File.expand_path(file_path)}",
                languageId: "ruby",
                version: 1,
                text: content
            }
        }
    }.to_json

    response_ptr = LibSorbet.send(@session, msg)
    if response_ptr.null?
        puts "No response from Sorbet"
        return
    end

    response_str = String.new(response_ptr)
    puts "Sorbet Response (didOpen): #{response_str}"

    # Check for publishDiagnostics notification
    begin
        json = JSON.parse(response_str)
        if json.as_a?
            json.as_a.each do |msg|
                check_diagnostics(msg)
            end
        end
    rescue ex
        puts "Error parsing JSON: #{ex.message}"
    ensure
        # Free the C string to prevent memory leak
        LibSorbet.free_string(response_ptr)
    end
  end

  def check_diagnostics(msg)
    if msg["method"]? == "textDocument/publishDiagnostics"
        diagnostics = msg["params"]["diagnostics"].as_a
        if diagnostics.empty?
            puts "No errors found!"
        else
            diagnostics.each do |d|
                puts "Error at line #{d["range"]["start"]["line"]}: #{d["message"]}"
            end
        end
    end
  end

  def close
    LibSorbet.free(@session)
  end
end

puts "Starting Sorbet via C ABI..."
client = SorbetClient.new
puts "Sorbet initialized."

file = "test.rb"
content = File.read(file)

puts "Typechecking #{file}..."
client.typecheck(file, content)

client.close
puts "Done."
