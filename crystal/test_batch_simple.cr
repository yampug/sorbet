require "json"

@[Link("sorbet")]
lib LibSorbet
  type Session = Void*
  fun new = sorbet_new(args : LibC::Char*) : Session
  fun send = sorbet_send(session : Session, msg : LibC::Char*) : LibC::Char*
  fun send_batch = sorbet_send_batch(session : Session, msgs : LibC::Char**, count : Int32) : LibC::Char*
  fun free_string = sorbet_free_string(str : LibC::Char*)
  fun free = sorbet_free(session : Session)
end

puts "🧪 Testing Batch API Performance\n"

# Initialize
session = LibSorbet.new("{}")
raise "Failed to init" if session.null?

# Handshake
init = {jsonrpc: "2.0", id: 1, method: "initialize", params: {rootUri: "file://#{Dir.current}", capabilities: {} of String => String}}.to_json
resp = LibSorbet.send(session, init)
LibSorbet.free_string(resp) unless resp.null?

initialized = {jsonrpc: "2.0", method: "initialized", params: {} of String => String}.to_json
resp = LibSorbet.send(session, initialized)
LibSorbet.free_string(resp) unless resp.null?

puts "✅ Sorbet initialized\n"

# Create test messages
messages = (1..10).map do |i|
  {
    jsonrpc: "2.0",
    method:  "textDocument/didOpen",
    params:  {
      textDocument: {
        uri:        "file://#{Dir.current}/test#{i}.rb",
        languageId: "ruby",
        version:    1,
        text:       "# typed: strict\nclass Test#{i}; def foo; #{i}; end; end",
      },
    },
  }.to_json
end

# Test sequential processing
puts "📊 Sequential processing (10 files):"
start = Time.monotonic
messages.each do |msg|
  resp = LibSorbet.send(session, msg)
  LibSorbet.free_string(resp) unless resp.null?
end
sequential_time = Time.monotonic - start
puts "  Time: #{(sequential_time.total_milliseconds).round(2)}ms\n"

# Test batch processing
puts "📊 Batch processing (10 files):"
start = Time.monotonic
message_ptrs = messages.map(&.to_unsafe)
batch_resp = LibSorbet.send_batch(session, message_ptrs, messages.size)
unless batch_resp.null?
  resp_str = String.new(batch_resp)
  puts "  Response: #{resp_str.size} bytes"
  LibSorbet.free_string(batch_resp)
end
batch_time = Time.monotonic - start
puts "  Time: #{(batch_time.total_milliseconds).round(2)}ms\n"

# Calculate speedup
speedup = sequential_time / batch_time
puts "🚀 Speedup: #{speedup.round(2)}x faster with batch API!"

LibSorbet.free(session)
puts "\n✅ Test complete!"
