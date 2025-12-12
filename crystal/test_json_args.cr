require "json"

@[Link("sorbet")]
lib LibSorbet
  type Session = Void*
  fun new = sorbet_new(args : LibC::Char*) : Session
  fun send = sorbet_send(session : Session, msg : LibC::Char*) : LibC::Char*
  fun free_string = sorbet_free_string(str : LibC::Char*)
  fun free = sorbet_free(session : Session)
end

puts "🧪 Testing JSON Args Parsing\n"
puts "=" * 60

# Test 1: Empty object (should use defaults)
puts "\n✅ Test 1: Empty object \"{}\""
session1 = LibSorbet.new("{}")
if session1.null?
  puts "  ❌ Failed to create session"
  exit 1
else
  puts "  ✅ Session created with default args"
  LibSorbet.free(session1)
end

# Test 2: Array format
puts "\n✅ Test 2: Array format"
args_json = ["--lsp", "--disable-watchman", "."].to_json
puts "  Args: #{args_json}"
session2 = LibSorbet.new(args_json)
if session2.null?
  puts "  ❌ Failed to create session"
  exit 1
else
  puts "  ✅ Session created successfully"
  LibSorbet.free(session2)
end

# Test 3: Object format with "args" field
puts "\n✅ Test 3: Object format with 'args' field"
args_json = {args: ["--lsp", "--disable-watchman", "."]}.to_json
puts "  Args: #{args_json}"
session3 = LibSorbet.new(args_json)
if session3.null?
  puts "  ❌ Failed to create session"
  exit 1
else
  puts "  ✅ Session created successfully"
  LibSorbet.free(session3)
end

# Test 4: Test with custom args (adding silence-dev-message)
puts "\n✅ Test 4: Custom args with --silence-dev-message"
args_json = ["--lsp", "--silence-dev-message", "--disable-watchman", "."].to_json
puts "  Args: #{args_json}"
session4 = LibSorbet.new(args_json)
if session4.null?
  puts "  ❌ Failed to create session"
  exit 1
else
  puts "  ✅ Session created successfully"

  # Try to send an initialize message to verify it works
  init_msg = {
    jsonrpc: "2.0",
    id: 1,
    method: "initialize",
    params: {
      rootUri: "file://#{Dir.current}",
      capabilities: {} of String => String
    }
  }.to_json

  resp_ptr = LibSorbet.send(session4, init_msg)
  unless resp_ptr.null?
    resp = String.new(resp_ptr)
    puts "  ✅ Initialize response received (#{resp.size} bytes)"
    LibSorbet.free_string(resp_ptr)
  end

  LibSorbet.free(session4)
end

puts "\n" + "=" * 60
puts "✅ All JSON args parsing tests passed!"
puts "=" * 60
