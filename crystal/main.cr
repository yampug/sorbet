require "json"

@[Link("sorbet")]
lib LibSorbet
  type Session = Void*
  fun new = sorbet_new(args : LibC::Char*) : Session
  fun send = sorbet_send(session : Session, msg : LibC::Char*) : LibC::Char*
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
    # verify response... (omitted for brevity)

    # 2. initialized notification
    initialized_msg = {
      jsonrpc: "2.0",
      method: "initialized",
      params: {} of String => String
    }.to_json
    LibSorbet.send(@session, initialized_msg)
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
    # Important: In a real app we'd need to free the pointer if we expose a free function for strings,
    # or rely on the fact that for this test we leak small amounts.
    # The current C API `sorbet_send` uses `malloc`, so we technically leak here unless we `free` it directly 
    # or expose `sorbet_free_string`. For this POC it's acceptable.

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
