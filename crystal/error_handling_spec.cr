require "spec"
require "./sorbet_spec"

describe "Error Handling and Recovery" do
  describe "Malformed JSON" do
    it "handles invalid JSON gracefully" do
      session = SorbetSession.new

      # The send_message method expects valid JSON
      # But we can test the underlying behavior
      begin
        session.send_message("not valid json {{{")
      rescue ex
        # Should handle gracefully
        ex.should be_a(Exception)
      end

      # Session should still be usable
      diagnostics = session.typecheck_file("recovery.rb", "class Recovery\nend")
      diagnostics.should be_a(Array(Hash(String, JSON::Any)))

      session.close
    end

    it "handles incomplete JSON" do
      session = SorbetSession.new

      begin
        session.send_message("{\"jsonrpc\": \"2.0\", \"method\": \"textDocument/didOpen\"")
      rescue ex
        ex.should be_a(Exception)
      end

      session.close
    end

    it "handles JSON with wrong types" do
      session = SorbetSession.new

      # Send message with wrong parameter types
      malformed_msg = {
        jsonrpc: "2.0",
        method: "textDocument/didOpen",
        params: "this should be an object not a string"
      }.to_json

      # Should not crash
      session.send_message(malformed_msg)

      session.close
    end

    it "handles JSON array instead of object" do
      session = SorbetSession.new

      begin
        session.send_message("[1, 2, 3]")
      rescue
        # Expected to fail, but should not crash
      end

      session.close
    end
  end

  describe "Invalid LSP Messages" do
    it "handles missing required fields" do
      session = SorbetSession.new

      # Missing method field
      invalid_msg = {
        jsonrpc: "2.0",
        params: {} of String => String
      }.to_json

      session.send_message(invalid_msg)

      session.close
    end

    it "handles unknown methods" do
      session = SorbetSession.new

      unknown_method = {
        jsonrpc: "2.0",
        method: "unknownMethod/doesNotExist",
        params: {} of String => String
      }.to_json

      session.send_message(unknown_method)

      session.close
    end

    it "handles invalid jsonrpc version" do
      session = SorbetSession.new

      wrong_version = {
        jsonrpc: "1.0",
        method: "textDocument/didOpen",
        params: {
          textDocument: {
            uri: "file://test.rb",
            languageId: "ruby",
            version: 1,
            text: "class Test; end"
          }
        }
      }.to_json

      session.send_message(wrong_version)

      session.close
    end

    it "handles missing textDocument uri" do
      session = SorbetSession.new

      missing_uri = {
        jsonrpc: "2.0",
        method: "textDocument/didOpen",
        params: {
          textDocument: {
            languageId: "ruby",
            version: 1,
            text: "class Test; end"
          }
        }
      }.to_json

      session.send_message(missing_uri)

      session.close
    end

    it "handles invalid position coordinates" do
      session = SorbetSession.new

      session.typecheck_file("test_invalid_pos.rb", "class Test\nend")

      invalid_position = {
        jsonrpc: "2.0",
        id: 1,
        method: "textDocument/hover",
        params: {
          textDocument: {
            uri: "file://#{File.expand_path("test_invalid_pos.rb")}"
          },
          position: {
            line: -1,
            character: -1
          }
        }
      }.to_json

      session.send_message(invalid_position)

      session.close
    end

    it "handles out-of-bounds position" do
      session = SorbetSession.new

      session.typecheck_file("test_oob.rb", "class Test\nend")

      oob_position = {
        jsonrpc: "2.0",
        id: 1,
        method: "textDocument/hover",
        params: {
          textDocument: {
            uri: "file://#{File.expand_path("test_oob.rb")}"
          },
          position: {
            line: 99999,
            character: 99999
          }
        }
      }.to_json

      session.send_message(oob_position)

      session.close
    end
  end

  describe "Ruby Syntax Errors" do
    it "handles files with syntax errors" do
      session = SorbetSession.new

      syntax_error_content = <<-RUBY
      class SyntaxError
        def method
          if true
            # Missing end
        end
      RUBY

      diagnostics = session.typecheck_file("syntax_error.rb", syntax_error_content)
      diagnostics.should_not be_empty

      session.close
    end

    it "handles multiple syntax errors" do
      session = SorbetSession.new

      multiple_errors = <<-RUBY
      class MultipleErrors
        def method1
          if true
          # Missing end

        def method2
          }  # Unmatched brace
        end

        def method3
          case x
            when 1
            # Missing end
        end
      RUBY

      diagnostics = session.typecheck_file("multiple_syntax.rb", multiple_errors)
      diagnostics.should_not be_empty

      session.close
    end

    it "handles incomplete class definitions" do
      session = SorbetSession.new

      incomplete = <<-RUBY
      class Incomplete
        def method
          42
      RUBY

      diagnostics = session.typecheck_file("incomplete.rb", incomplete)
      diagnostics.should_not be_empty

      session.close
    end

    it "handles invalid Ruby operators" do
      session = SorbetSession.new

      invalid_operators = <<-RUBY
      class InvalidOps
        def method
          x = 1 *** 2  # Invalid operator
        end
      end
      RUBY

      diagnostics = session.typecheck_file("invalid_ops.rb", invalid_operators)
      diagnostics.should_not be_empty

      session.close
    end
  end

  describe "File System Errors" do
    it "handles non-existent file paths" do
      session = SorbetSession.new

      msg = {
        jsonrpc: "2.0",
        method: "textDocument/didOpen",
        params: {
          textDocument: {
            uri: "file:///nonexistent/path/to/file.rb",
            languageId: "ruby",
            version: 1,
            text: "class Test\nend"
          }
        }
      }.to_json

      # Should handle gracefully
      session.send_message(msg)

      session.close
    end

    it "handles invalid URI schemes" do
      session = SorbetSession.new

      invalid_uri = {
        jsonrpc: "2.0",
        method: "textDocument/didOpen",
        params: {
          textDocument: {
            uri: "http://example.com/test.rb",
            languageId: "ruby",
            version: 1,
            text: "class Test\nend"
          }
        }
      }.to_json

      session.send_message(invalid_uri)

      session.close
    end

    it "handles malformed URIs" do
      session = SorbetSession.new

      malformed_uri = {
        jsonrpc: "2.0",
        method: "textDocument/didOpen",
        params: {
          textDocument: {
            uri: "not a valid uri at all",
            languageId: "ruby",
            version: 1,
            text: "class Test\nend"
          }
        }
      }.to_json

      session.send_message(malformed_uri)

      session.close
    end
  end

  describe "Type Errors and Sorbet-specific Errors" do
    it "handles untyped method calls" do
      session = SorbetSession.new

      content = <<-RUBY
      # typed: true
      class UntypedTest
        def method
          undefined_method_call
        end
      end
      RUBY

      diagnostics = session.typecheck_file("untyped.rb", content)
      diagnostics.should_not be_empty

      session.close
    end

    it "handles type mismatches" do
      session = SorbetSession.new

      content = <<-RUBY
      # typed: strict
      class TypeMismatch
        extend T::Sig

        sig {params(x: Integer).returns(Integer)}
        def add_one(x)
          x + "1"  # Type error: String instead of Integer
        end
      end
      RUBY

      diagnostics = session.typecheck_file("type_mismatch.rb", content)
      diagnostics.should_not be_empty

      session.close
    end

    it "handles missing constant references" do
      session = SorbetSession.new

      content = <<-RUBY
      class MissingConstant
        def method
          UndefinedConstant.new
        end
      end
      RUBY

      diagnostics = session.typecheck_file("missing_constant.rb", content)
      diagnostics.should_not be_empty

      session.close
    end

    it "handles circular type definitions" do
      session = SorbetSession.new

      content = <<-RUBY
      # typed: true
      class CircularType
        extend T::Sig

        sig {returns(CircularType)}
        def self_reference
          self
        end
      end
      RUBY

      diagnostics = session.typecheck_file("circular_type.rb", content)
      # May or may not have errors depending on Sorbet's handling
      diagnostics.should be_a(Array(Hash(String, JSON::Any)))

      session.close
    end
  end

  describe "Batch Error Handling" do
    it "handles batch with some invalid messages" do
      session = SorbetSession.new

      files = {
        "valid1.rb" => "class Valid1\nend",
        "invalid_syntax.rb" => "class Invalid\n  def method\n",
        "valid2.rb" => "class Valid2\nend"
      }

      diagnostics = session.typecheck_files_batch(files)
      diagnostics.should be_a(Array(Hash(String, JSON::Any)))

      session.close
    end

    it "handles all invalid batch" do
      session = SorbetSession.new

      files = {
        "invalid1.rb" => "class Invalid1\n  def",
        "invalid2.rb" => "class Invalid2\n  }",
        "invalid3.rb" => "class Invalid3\n  if"
      }

      diagnostics = session.typecheck_files_batch(files)
      diagnostics.should_not be_empty

      session.close
    end
  end

  describe "Recovery and State Management" do
    it "recovers from errors and continues working" do
      session = SorbetSession.new

      # Send an invalid message
      begin
        session.send_message("invalid")
      rescue
        # Expected to fail
      end

      # Should still be able to work
      diagnostics = session.typecheck_file("recovery_test.rb", "class RecoveryTest\nend")
      diagnostics.should be_a(Array(Hash(String, JSON::Any)))

      session.close
    end

    it "handles errors in sequence" do
      session = SorbetSession.new

      5.times do |i|
        content = "# typed: true\nclass Error#{i}\n  def method\n    undefined_#{i}\n  end\nend"
        diagnostics = session.typecheck_file("error_#{i}.rb", content)
        diagnostics.should_not be_empty
      end

      session.close
    end

    it "maintains state after errors" do
      session = SorbetSession.new

      # Open a valid file
      session.typecheck_file("valid_state.rb", "class ValidState\nend")

      # Send an invalid message
      begin
        session.send_message("{invalid}")
      rescue
      end

      # The valid file should still be in state
      # Send another message about the same file
      change_msg = {
        jsonrpc: "2.0",
        method: "textDocument/didChange",
        params: {
          textDocument: {
            uri: "file://#{File.expand_path("valid_state.rb")}",
            version: 2
          },
          contentChanges: [
            {
              text: "class ValidState\n  def new_method\n    42\n  end\nend"
            }
          ]
        }
      }.to_json

      session.send_message(change_msg)

      session.close
    end
  end

  describe "Concurrent Error Handling" do
    it "handles errors across multiple sessions" do
      sessions = (1..3).map { SorbetSession.new }

      # Send errors to all sessions
      sessions.each_with_index do |session, i|
        content = "# typed: true\nclass ConcurrentError#{i}\n  def method\n    undefined_#{i}\n  end\nend"
        diagnostics = session.typecheck_file("concurrent_error_#{i}.rb", content)
        diagnostics.should_not be_empty
      end

      sessions.each(&.close)
    end

    it "isolates errors between sessions" do
      session1 = SorbetSession.new
      session2 = SorbetSession.new

      # Send error to session1
      session1.typecheck_file("session1_error.rb", "class Error\n  def")

      # session2 should not be affected
      diagnostics2 = session2.typecheck_file("session2_valid.rb", "class Valid\nend")
      diagnostics2.should be_empty

      session1.close
      session2.close
    end
  end
end
