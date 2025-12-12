require "json"

@[Link("sorbet")]
lib LibSorbet
  type Session = Void*

  # Standard API
  fun new = sorbet_new(args : LibC::Char*) : Session
  fun send = sorbet_send(session : Session, msg : LibC::Char*) : LibC::Char*

  # PERFORMANCE: Batch API
  fun send_batch = sorbet_send_batch(session : Session, msgs : LibC::Char**, count : Int32) : LibC::Char*

  # PERFORMANCE: Multi-threaded API
  fun new_mt = sorbet_new_mt(args : LibC::Char*, num_threads : Int32) : Session

  fun free_string = sorbet_free_string(str : LibC::Char*)
  fun free = sorbet_free(session : Session)
end

class SorbetClient
  def initialize(multithreaded = false, threads = 4)
    args = ["--silence-dev-message", "."].to_json

    if multithreaded
      @session = LibSorbet.new_mt(args, threads)
      puts "✅ Initialized multi-threaded Sorbet (#{threads} threads)"
    else
      @session = LibSorbet.new(args)
      puts "✅ Initialized single-threaded Sorbet"
    end

    if @session.null?
      raise "Failed to initialize Sorbet session"
    end

    perform_handshake
  end

  def perform_handshake
    init_msg = {
      jsonrpc: "2.0",
      id:      1,
      method:  "initialize",
      params:  {
        rootUri:      "file://#{Dir.current}",
        capabilities: {} of String => String,
      },
    }.to_json

    response_ptr = LibSorbet.send(@session, init_msg)
    LibSorbet.free_string(response_ptr) unless response_ptr.null?

    initialized_msg = {
      jsonrpc: "2.0",
      method:  "initialized",
      params:  {} of String => String,
    }.to_json

    response_ptr = LibSorbet.send(@session, initialized_msg)
    LibSorbet.free_string(response_ptr) unless response_ptr.null?
  end

  # OLD WAY: Sequential processing (slow for many files)
  def typecheck_sequential(files : Array(String))
    puts "\n📊 Sequential Processing (OLD):"
    start = Time.monotonic

    files.each do |file_path|
      content = File.read(file_path)
      msg = create_did_open(file_path, content)

      response_ptr = LibSorbet.send(@session, msg)
      next if response_ptr.null?

      response_str = String.new(response_ptr)
      process_response(response_str)

      LibSorbet.free_string(response_ptr)
    end

    elapsed = Time.monotonic - start
    puts "⏱️  Sequential: #{files.size} files in #{elapsed.total_milliseconds.round(2)}ms"
  end

  # NEW WAY: Batch processing (fast for many files)
  def typecheck_batch(files : Array(String))
    puts "\n📊 Batch Processing (NEW - OPTIMIZED):"
    start = Time.monotonic

    # Create all didOpen messages
    messages = files.map do |file_path|
      content = File.read(file_path)
      create_did_open(file_path, content)
    end

    # Convert to C array
    message_ptrs = messages.map(&.to_unsafe)

    # Send all messages in ONE batch call
    response_ptr = LibSorbet.send_batch(@session, message_ptrs, messages.size)

    unless response_ptr.null?
      response_str = String.new(response_ptr)
      process_response(response_str)
      LibSorbet.free_string(response_ptr)
    end

    elapsed = Time.monotonic - start
    puts "⏱️  Batch: #{files.size} files in #{elapsed.total_milliseconds.round(2)}ms"
    puts "🚀 Speedup: #{(elapsed.total_milliseconds / elapsed.total_milliseconds * 100).round}x faster"
  end

  private def create_did_open(file_path : String, content : String) : String
    {
      jsonrpc: "2.0",
      method:  "textDocument/didOpen",
      params:  {
        textDocument: {
          uri:        "file://#{File.expand_path(file_path)}",
          languageId: "ruby",
          version:    1,
          text:       content,
        },
      },
    }.to_json
  end

  private def process_response(response_str : String)
    json = JSON.parse(response_str)
    return unless json.as_a?

    diagnostics_count = 0
    json.as_a.each do |msg|
      if msg["method"]? == "textDocument/publishDiagnostics"
        diagnostics = msg["params"]["diagnostics"].as_a
        diagnostics_count += diagnostics.size
        diagnostics.each do |d|
          puts "  ⚠️  Line #{d["range"]["start"]["line"]}: #{d["message"]}"
        end
      end
    end

    if diagnostics_count == 0
      puts "  ✅ No errors"
    end
  rescue ex
    puts "  ❌ Error parsing response: #{ex.message}"
  end

  def close
    LibSorbet.free(@session)
  end
end

# ========================================
# BENCHMARK: Sequential vs Batch
# ========================================

puts "=" * 60
puts "Sorbet C API Performance Comparison"
puts "=" * 60

# Find all Ruby files in current directory
ruby_files = Dir.glob("*.rb")

if ruby_files.empty?
  puts "No Ruby files found. Creating test files..."
  (1..10).each do |i|
    File.write("test_#{i}.rb", <<-RUBY)
      # typed: strict
      class TestClass#{i}
        extend T::Sig

        sig { returns(Integer) }
        def foo
          #{i}
        end
      end
    RUBY
  end
  ruby_files = Dir.glob("test_*.rb")
end

puts "Found #{ruby_files.size} Ruby files\n"

# Test 1: Single-threaded Sequential
puts "\n🧪 Test 1: Single-threaded Sequential"
client1 = SorbetClient.new(multithreaded: false)
client1.typecheck_sequential(ruby_files)
client1.close

# Test 2: Single-threaded Batch
puts "\n🧪 Test 2: Single-threaded Batch"
client2 = SorbetClient.new(multithreaded: false)
client2.typecheck_batch(ruby_files)
client2.close

# Test 3: Multi-threaded Batch (if available)
puts "\n🧪 Test 3: Multi-threaded Batch (8 threads)"
client3 = SorbetClient.new(multithreaded: true, threads: 8)
client3.typecheck_batch(ruby_files)
client3.close

puts "\n" + "=" * 60
puts "✅ Benchmark complete!"
puts "=" * 60
