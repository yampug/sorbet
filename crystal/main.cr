require "json"
require "file_utils"

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

# Enterprise-grade Sorbet Client for production use
class SorbetClient
  class TypecheckResult
    property file : String
    property errors : Array(DiagnosticError)
    property warnings : Array(DiagnosticError)

    def initialize(@file : String)
      @errors = [] of DiagnosticError
      @warnings = [] of DiagnosticError
    end

    def has_errors?
      !@errors.empty?
    end

    def has_warnings?
      !@warnings.empty?
    end

    def success?
      !has_errors?
    end
  end

  class DiagnosticError
    property message : String
    property line : Int32
    property column : Int32
    property severity : String

    def initialize(@message : String, @line : Int32, @column : Int32, @severity : String)
    end

    def to_s(io : IO)
      io << "#{@severity.upcase} at line #{@line}:#{@column} - #{@message}"
    end
  end

  getter session : LibSorbet::Session
  getter root_path : String
  getter multi_threaded : Bool

  def initialize(@root_path : String = ".", @multi_threaded : Bool = false, num_threads : Int32 = 4)
    # Expand path to absolute path for Sorbet
    @root_path = File.expand_path(@root_path)

    # Configure Sorbet arguments
    args = [
      "--silence-dev-message",
      "--lsp",
      "--disable-watchman",
      @root_path
    ].to_json

    @session = if @multi_threaded
      LibSorbet.new_mt(args, num_threads)
    else
      LibSorbet.new(args)
    end

    raise "Failed to initialize Sorbet session" if @session.null?

    perform_handshake
  end

  # Initialize LSP session
  private def perform_handshake
    # 1. initialize request
    init_msg = {
      jsonrpc: "2.0",
      id: 1,
      method: "initialize",
      params: {
        rootUri: "file://#{@root_path}",
        capabilities: {
          textDocument: {
            publishDiagnostics: {
              relatedInformation: true,
              tagSupport: {values: [1, 2]},
              versionSupport: true
            }
          }
        }
      }
    }.to_json

    response_ptr = LibSorbet.send(@session, init_msg)
    LibSorbet.free_string(response_ptr) unless response_ptr.null?

    # 2. initialized notification
    initialized_msg = {
      jsonrpc: "2.0",
      method: "initialized",
      params: {} of String => String
    }.to_json

    response_ptr = LibSorbet.send(@session, initialized_msg)
    LibSorbet.free_string(response_ptr) unless response_ptr.null?
  end

  # Typecheck a single file
  def typecheck_file(file_path : String) : TypecheckResult
    absolute_path = if file_path.starts_with?('/')
      file_path
    else
      File.expand_path(file_path, @root_path)
    end

    unless File.exists?(absolute_path)
      result = TypecheckResult.new(file_path)
      result.errors << DiagnosticError.new("File not found: #{absolute_path}", 0, 0, "error")
      return result
    end

    content = File.read(absolute_path)
    typecheck_file_content(file_path, content)
  end

  # Typecheck file with provided content
  def typecheck_file_content(file_path : String, content : String) : TypecheckResult
    absolute_path = if file_path.starts_with?('/')
      file_path
    else
      File.expand_path(file_path, @root_path)
    end

    msg = {
      jsonrpc: "2.0",
      method: "textDocument/didOpen",
      params: {
        textDocument: {
          uri: "file://#{absolute_path}",
          languageId: "ruby",
          version: 1,
          text: content
        }
      }
    }.to_json

    response_ptr = LibSorbet.send(@session, msg)
    result = process_response(file_path, response_ptr)
    LibSorbet.free_string(response_ptr) unless response_ptr.null?

    result
  end

  # Typecheck multiple files in batch
  def typecheck_files_batch(files : Hash(String, String)) : Array(TypecheckResult)
    return [] of TypecheckResult if files.empty?

    messages = [] of String

    files.each do |file_path, content|
      absolute_path = if file_path.starts_with?('/')
        file_path
      else
        File.expand_path(file_path, @root_path)
      end

      messages << {
        jsonrpc: "2.0",
        method: "textDocument/didOpen",
        params: {
          textDocument: {
            uri: "file://#{absolute_path}",
            languageId: "ruby",
            version: 1,
            text: content
          }
        }
      }.to_json
    end

    # Convert to C array
    c_messages = Pointer(Pointer(UInt8)).malloc(messages.size)
    messages.each_with_index do |msg, i|
      c_messages[i] = msg.to_unsafe
    end

    response_ptr = LibSorbet.send_batch(@session, c_messages, messages.size)
    results = process_batch_response(files.keys.to_a, response_ptr)
    LibSorbet.free_string(response_ptr) unless response_ptr.null?

    results
  end

  # Typecheck all Ruby files in a directory
  def typecheck_directory(dir_path : String = ".", pattern : String = "**/*.rb") : Array(TypecheckResult)
    search_path = File.expand_path(dir_path, @root_path)

    unless Dir.exists?(search_path)
      result = TypecheckResult.new(dir_path)
      result.errors << DiagnosticError.new("Directory not found: #{search_path}", 0, 0, "error")
      return [result]
    end

    files = {} of String => String

    # Find all matching Ruby files
    Dir.glob(File.join(search_path, pattern)).each do |file_path|
      next unless File.file?(file_path)

      begin
        content = File.read(file_path)
        relative_path = file_path.sub("#{@root_path}/", "")
        files[relative_path] = content
      rescue ex
        puts "Warning: Could not read file #{file_path}: #{ex.message}"
      end
    end

    if files.empty?
      puts "No Ruby files found matching pattern: #{pattern}"
      return [] of TypecheckResult
    end

    typecheck_files_batch(files)
  end

  # Close the session and free resources
  def close
    LibSorbet.free(@session)
  end

  # Process response from Sorbet
  private def process_response(file_path : String, response_ptr : Pointer(LibC::Char)) : TypecheckResult
    result = TypecheckResult.new(file_path)

    return result if response_ptr.null?

    response_str = String.new(response_ptr)

    begin
      json = JSON.parse(response_str)
      if json.as_a?
        json.as_a.each do |msg|
          extract_diagnostics(result, msg)
        end
      end
    rescue ex
      result.errors << DiagnosticError.new("Error parsing Sorbet response: #{ex.message}", 0, 0, "error")
    end

    result
  end

  # Process batch response from Sorbet
  private def process_batch_response(file_paths : Array(String), response_ptr : Pointer(LibC::Char)) : Array(TypecheckResult)
    results = {} of String => TypecheckResult
    file_paths.each { |path| results[path] = TypecheckResult.new(path) }

    return results.values unless response_ptr.null?

    response_str = String.new(response_ptr)

    begin
      json = JSON.parse(response_str)
      if json.as_a?
        json.as_a.each do |msg|
          if msg["method"]? == "textDocument/publishDiagnostics"
            uri = msg["params"]["uri"].as_s
            file_path = uri.sub("file://#{@root_path}/", "").sub("file://", "")

            result = results[file_path]? || TypecheckResult.new(file_path)
            extract_diagnostics(result, msg)
            results[file_path] = result
          end
        end
      end
    rescue ex
      puts "Error parsing batch response: #{ex.message}"
    end

    results.values
  end

  # Extract diagnostics from LSP message
  private def extract_diagnostics(result : TypecheckResult, msg : JSON::Any)
    if msg["method"]? == "textDocument/publishDiagnostics"
      diagnostics = msg["params"]["diagnostics"].as_a? || [] of JSON::Any

      diagnostics.each do |d|
        message = d["message"].as_s
        line = d["range"]["start"]["line"].as_i
        character = d["range"]["start"]["character"].as_i
        severity_num = d["severity"]?.try(&.as_i) || 1

        severity = case severity_num
        when 1 then "error"
        when 2 then "warning"
        when 3 then "information"
        when 4 then "hint"
        else "error"
        end

        diagnostic = DiagnosticError.new(message, line, character, severity)

        case severity
        when "error"
          result.errors << diagnostic
        when "warning"
          result.warnings << diagnostic
        end
      end
    end
  end
end

# ============================================================================
# Example Usage: Enterprise CI/CD Integration
# ============================================================================

def print_separator
  puts "=" * 80
end

def print_results(results : Array(SorbetClient::TypecheckResult))
  total_files = results.size
  files_with_errors = results.count(&.has_errors?)
  files_with_warnings = results.count(&.has_warnings?)
  total_errors = results.sum { |r| r.errors.size }
  total_warnings = results.sum { |r| r.warnings.size }

  print_separator
  puts "Typecheck Summary:"
  puts "  Total files:      #{total_files}"
  puts "  Files with errors: #{files_with_errors}"
  puts "  Total errors:     #{total_errors}"
  puts "  Total warnings:   #{total_warnings}"
  print_separator

  if files_with_errors > 0
    puts "\nFiles with errors:"
    results.select(&.has_errors?).each do |result|
      puts "\n📄 #{result.file}:"
      result.errors.each do |error|
        puts "  #{error}"
      end
    end
  end

  if files_with_warnings > 0
    puts "\nFiles with warnings:"
    results.select(&.has_warnings?).each do |result|
      puts "\n📄 #{result.file}:"
      result.warnings.each do |warning|
        puts "  #{warning}"
      end
    end
  end

  if files_with_errors == 0
    puts "\n✅ All files passed typecheck!"
  else
    puts "\n❌ Typecheck failed with #{total_errors} error(s)"
  end

  files_with_errors == 0
end

# ============================================================================
# Main Application
# ============================================================================

puts "Sorbet C API Enterprise Example"
print_separator

# Parse command line arguments
root_path = ARGV[0]? || "."
use_mt = ARGV.includes?("--multi-threaded") || ARGV.includes?("-mt")
threads = 4

if idx = ARGV.index("--threads")
  threads = ARGV[idx + 1]?.try(&.to_i) || 4
end

puts "Configuration:"
puts "  Root path:       #{File.expand_path(root_path)}"
puts "  Multi-threaded:  #{use_mt}"
puts "  Threads:         #{threads}" if use_mt
print_separator

# Initialize Sorbet client
puts "\n🚀 Initializing Sorbet session..."
client = SorbetClient.new(root_path, use_mt, threads)
puts "✅ Sorbet initialized successfully"

# Example 1: Typecheck a single file
if File.exists?(File.join(root_path, "test.rb"))
  puts "\n📝 Example 1: Typechecking single file (test.rb)..."
  result = client.typecheck_file("test.rb")

  if result.success?
    puts "✅ test.rb: No errors"
  else
    puts "❌ test.rb: #{result.errors.size} error(s)"
    result.errors.each { |e| puts "  #{e}" }
  end
end

# Example 2: Typecheck all Ruby files in current directory
puts "\n📂 Example 2: Typechecking all Ruby files in repository..."
start_time = Time.monotonic
results = client.typecheck_directory(root_path, "**/*.rb")
elapsed = Time.monotonic - start_time

puts "\n⏱️  Typecheck completed in #{elapsed.total_seconds.round(2)} seconds"

success = print_results(results)

# Example 3: Demonstrate batch processing with specific files
if results.size > 0
  puts "\n📦 Example 3: Demonstrating batch processing..."
  sample_files = results.first(5).to_h do |r|
    path = File.join(root_path, r.file)
    content = File.exists?(path) ? File.read(path) : ""
    {r.file, content}
  end

  batch_results = client.typecheck_files_batch(sample_files)
  puts "✅ Batch processed #{batch_results.size} files"
end

# Cleanup
puts "\n🧹 Closing Sorbet session..."
client.close
puts "✅ Done."

# Exit with appropriate code for CI/CD
exit(success ? 0 : 1)
