require "json"

@[Link("sorbet")]
lib LibSorbet
  type Session = Void*

  # Standard API
  fun new = sorbet_new(args : LibC::Char*) : Session
  fun send = sorbet_send(session : Session, msg : LibC::Char*) : LibC::Char*

  # Batch API
  fun new_mt = sorbet_new_mt(args : LibC::Char*, num_threads : Int32) : Session
  fun send_batch = sorbet_send_batch(session : Session, msgs : LibC::Char**, count : Int32) : LibC::Char*

  # Memory management
  fun free_string = sorbet_free_string(str : LibC::Char*)
  fun free = sorbet_free(session : Session)
end

class SorbetSession
  def initialize(root_dir = ".", multi_threaded = false, num_threads = 2)
    args = ["--silence-dev-message", root_dir].to_json
    
    @session = if multi_threaded
      LibSorbet.new_mt(args, num_threads)
    else
      LibSorbet.new(args)
    end
    
    raise "Failed to initialize Sorbet session" if @session.nil?
    
    # Perform LSP handshake
    initialize_lsp
    initialized_notification
  end

  def close
    LibSorbet.free(@session.not_nil!) if @session
    @session = nil
  end

  def typecheck_file(file_path, content)
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

    send_message(msg)
  end

  def typecheck_files_batch(files)
    messages = [] of String
    
    files.each do |file_path, content|
      messages << {
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
    end

    # Convert to C array
    c_messages = Pointer(Pointer(UInt8)).malloc(messages.size)
    messages.each_with_index do |msg, i|
      c_messages[i] = msg.to_unsafe
    end

    response_ptr = LibSorbet.send_batch(@session.not_nil!, c_messages, messages.size)
    result = process_response(response_ptr)
    
    # Note: c_messages will be automatically freed when it goes out of scope
    result
  end

  def send_message(message)
    response_ptr = LibSorbet.send(@session.not_nil!, message)
    process_response(response_ptr)
  end

  def process_response(response_ptr)
    return [] of Hash(String, JSON::Any) if response_ptr.nil?
    
    response_str = String.new(response_ptr)
    diagnostics = [] of Hash(String, JSON::Any)
    
    begin
      json = JSON.parse(response_str)
      if json.as_a?
        json.as_a.each do |msg|
          if msg["method"]? == "textDocument/publishDiagnostics"
            if msg["params"]["diagnostics"].as_a?
              diagnostics += msg["params"]["diagnostics"].as_a
            end
          end
        end
      end
    rescue ex
      puts "Error parsing response: #{ex.message}"
    ensure
      LibSorbet.free_string(response_ptr)
    end
    
    diagnostics
  end

  private def initialize_lsp
    return unless @session
    
    init_msg = {
      jsonrpc: "2.0",
      id: 1,
      method: "initialize",
      params: {
        rootUri: "file://#{Dir.current}",
        capabilities: {} of String => String
      }
    }.to_json

    response_ptr = LibSorbet.send(@session.not_nil!, init_msg)
    LibSorbet.free_string(response_ptr) unless response_ptr.nil?
  end

  private def initialized_notification
    return unless @session
    
    initialized_msg = {
      jsonrpc: "2.0",
      method: "initialized",
      params: {} of String => JSON::Any
    }.to_json

    response_ptr = LibSorbet.send(@session.not_nil!, initialized_msg)
    LibSorbet.free_string(response_ptr) unless response_ptr.nil?
  end
end

# Test Helper
class TestHelper
  def self.create_test_file(content, filename = "test_#{rand(1000000)}.rb")
    File.write(filename, content)
    filename
  end

  def self.cleanup_file(filename)
    File.delete(filename) if File.exists?(filename)
  rescue
    # Ignore cleanup errors
  end

  def self.simple_ruby_code
    <<-RUBY
class TestClass
  def self.hello
    "Hello World"
  end
  
  def instance_method
    @value = 42
  end
end

# Usage
TestClass.hello
RUBY
  end

  def self.code_with_error
    <<-RUBY
class TestClass
  def self.method_with_error
    undefined_method_call
  end
end

TestClass.method_with_error
RUBY
  end

  def self.code_with_require
    <<-RUBY
require_relative 'helper'

class MainClass
  def self.run
    Helper.say_hello
  end
end

MainClass.run
RUBY
  end

  def self.helper_code
    <<-RUBY
class Helper
  def self.say_hello
    puts "Hello from Helper!"
  end
end
RUBY
  end
end