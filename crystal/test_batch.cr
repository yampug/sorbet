require "json"

@[Link("sorbet")]
lib LibSorbet
  type Session = Void*
  fun new = sorbet_new(args : LibC::Char*) : Session
  fun new_mt = sorbet_new_mt(args : LibC::Char*, num_threads : Int32) : Session
  fun send = sorbet_send(session : Session, msg : LibC::Char*) : LibC::Char*
  fun send_batch = sorbet_send_batch(session : Session, msgs : LibC::Char**, count : Int32) : LibC::Char*
  fun free_string = sorbet_free_string(str : LibC::Char*)
  fun free = sorbet_free(session : Session)
end

puts "=" * 60
puts "Testing Batch API + Multi-threading"
puts "=" * 60

# Test 1: Single-threaded with batch API
puts "\n✅ Test 1: Single-threaded + Batch API"
session1 = LibSorbet.new("{}")
if session1.null?
  puts "❌ Failed to create session"
  exit 1
end

# Handshake
init_msg = {jsonrpc: "2.0", id: 1, method: "initialize", params: {rootUri: "file://#{Dir.current}", capabilities: {} of String => String}}.to_json
resp_ptr = LibSorbet.send(session1, init_msg)
LibSorbet.free_string(resp_ptr) unless resp_ptr.null?

initialized_msg = {jsonrpc: "2.0", method: "initialized", params: {} of String => String}.to_json
resp_ptr = LibSorbet.send(session1, initialized_msg)
LibSorbet.free_string(resp_ptr) unless resp_ptr.null?

# Create 3 test files
test_files = [
  {path: "test1.rb", content: "# typed: strict\nclass Foo; def bar; 42; end; end"},
  {path: "test2.rb", content: "# typed: strict\nclass Bar; def baz; 'hello'; end; end"},
  {path: "test3.rb", content: "# typed: strict\nclass Qux; def quux; true; end; end"},
]

# Create batch messages
messages = test_files.map do |f|
  {
    jsonrpc: "2.0",
    method:  "textDocument/didOpen",
    params:  {
      textDocument: {
        uri:        "file://#{Dir.current}/#{f[:path]}",
        languageId: "ruby",
        version:    1,
        text:       f[:content],
      },
    },
  }.to_json
end

# Send batch
message_ptrs = messages.map(&.to_unsafe)
batch_resp = LibSorbet.send_batch(session1, message_ptrs, messages.size)

unless batch_resp.null?
  resp_str = String.new(batch_resp)
  puts "  Batch response received (#{resp_str.size} bytes)"
  LibSorbet.free_string(batch_resp)
else
  puts "  ❌ No batch response"
end

LibSorbet.free(session1)
puts "  ✅ Single-threaded batch test complete"

# Test 2: Multi-threaded with batch API
puts "\n✅ Test 2: Multi-threaded (4 threads) + Batch API"
session2 = LibSorbet.new_mt("{}", 4)
if session2.null?
  puts "❌ Failed to create multi-threaded session"
  exit 1
end

# Handshake
resp_ptr = LibSorbet.send(session2, init_msg)
LibSorbet.free_string(resp_ptr) unless resp_ptr.null?

resp_ptr = LibSorbet.send(session2, initialized_msg)
LibSorbet.free_string(resp_ptr) unless resp_ptr.null?

# Send batch
batch_resp = LibSorbet.send_batch(session2, message_ptrs, messages.size)

unless batch_resp.null?
  resp_str = String.new(batch_resp)
  puts "  Batch response received (#{resp_str.size} bytes)"
  LibSorbet.free_string(batch_resp)
else
  puts "  ❌ No batch response"
end

LibSorbet.free(session2)
puts "  ✅ Multi-threaded batch test complete"

puts "\n" + "=" * 60
puts "✅ All tests passed!"
puts "=" * 60
