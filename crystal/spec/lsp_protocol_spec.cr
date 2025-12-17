require "spec"
require "./sorbet_spec"

describe "LSP Protocol Compliance" do
  describe "Session Lifecycle" do
    it "initializes with default arguments" do
      session = SorbetSession.new
      session.close
    end

    it "initializes with custom root directory" do
      session = SorbetSession.new(Dir.current)
      session.close
    end

    it "handles initialize request properly" do
      session = SorbetSession.new
      # Initialization happens in constructor
      # Verify session is ready by sending a message
      response = session.send_message({
        jsonrpc: "2.0",
        method: "textDocument/didOpen",
        params: {
          textDocument: {
            uri: "file://#{Dir.current}/test.rb",
            languageId: "ruby",
            version: 1,
            text: "class Test; end"
          }
        }
      }.to_json)

      response.should_not be_nil
      session.close
    end

    it "handles shutdown request" do
      session = SorbetSession.new

      shutdown_msg = {
        jsonrpc: "2.0",
        id: 100,
        method: "shutdown"
      }.to_json

      response = session.send_message(shutdown_msg)
      session.close
    end

    it "supports multiple sequential sessions" do
      3.times do
        session = SorbetSession.new
        session.close
      end
    end
  end

  describe "LSP Notifications" do
    it "handles textDocument/didOpen notification" do
      session = SorbetSession.new

      msg = {
        jsonrpc: "2.0",
        method: "textDocument/didOpen",
        params: {
          textDocument: {
            uri: "file://#{Dir.current}/test_open.rb",
            languageId: "ruby",
            version: 1,
            text: "class TestOpen\nend"
          }
        }
      }.to_json

      diagnostics = session.typecheck_file("test_open.rb", "class TestOpen\nend")
      diagnostics.should be_a(Array(Hash(String, JSON::Any)))

      session.close
    end

    it "handles textDocument/didChange notification" do
      session = SorbetSession.new

      # First open the document
      session.typecheck_file("test_change.rb", "class Original\nend")

      # Then change it
      change_msg = {
        jsonrpc: "2.0",
        method: "textDocument/didChange",
        params: {
          textDocument: {
            uri: "file://#{File.expand_path("test_change.rb")}",
            version: 2
          },
          contentChanges: [
            {
              text: "class Changed\n  def method\n    42\n  end\nend"
            }
          ]
        }
      }.to_json

      session.send_message(change_msg)
      session.close
    end

    it "handles textDocument/didSave notification" do
      session = SorbetSession.new

      session.typecheck_file("test_save.rb", "class TestSave\nend")

      save_msg = {
        jsonrpc: "2.0",
        method: "textDocument/didSave",
        params: {
          textDocument: {
            uri: "file://#{File.expand_path("test_save.rb")}"
          }
        }
      }.to_json

      session.send_message(save_msg)
      session.close
    end

    it "handles textDocument/didClose notification" do
      session = SorbetSession.new

      session.typecheck_file("test_close.rb", "class TestClose\nend")

      close_msg = {
        jsonrpc: "2.0",
        method: "textDocument/didClose",
        params: {
          textDocument: {
            uri: "file://#{File.expand_path("test_close.rb")}"
          }
        }
      }.to_json

      session.send_message(close_msg)
      session.close
    end

    it "handles workspace/didChangeConfiguration notification" do
      session = SorbetSession.new

      config_msg = {
        jsonrpc: "2.0",
        method: "workspace/didChangeConfiguration",
        params: {
          settings: {} of String => String
        }
      }.to_json

      session.send_message(config_msg)
      session.close
    end
  end

  describe "LSP Requests" do
    it "handles textDocument/hover request" do
      session = SorbetSession.new

      # Open a file with content
      session.typecheck_file("test_hover.rb", "class TestHover\n  def method\n    42\n  end\nend")

      hover_msg = {
        jsonrpc: "2.0",
        id: 1,
        method: "textDocument/hover",
        params: {
          textDocument: {
            uri: "file://#{File.expand_path("test_hover.rb")}"
          },
          position: {
            line: 1,
            character: 6
          }
        }
      }.to_json

      response = session.send_message(hover_msg)
      response.should_not be_nil

      session.close
    end

    it "handles textDocument/definition request" do
      session = SorbetSession.new

      content = <<-RUBY
      class MyClass
        def my_method
          42
        end
      end

      MyClass.new.my_method
      RUBY

      session.typecheck_file("test_definition.rb", content)

      definition_msg = {
        jsonrpc: "2.0",
        id: 2,
        method: "textDocument/definition",
        params: {
          textDocument: {
            uri: "file://#{File.expand_path("test_definition.rb")}"
          },
          position: {
            line: 6,
            character: 15
          }
        }
      }.to_json

      response = session.send_message(definition_msg)
      response.should_not be_nil

      session.close
    end

    it "handles textDocument/completion request" do
      session = SorbetSession.new

      content = <<-RUBY
      class CompletionTest
        def method_one
          1
        end

        def method_two
          2
        end
      end

      obj = CompletionTest.new
      obj.
      RUBY

      session.typecheck_file("test_completion.rb", content)

      completion_msg = {
        jsonrpc: "2.0",
        id: 3,
        method: "textDocument/completion",
        params: {
          textDocument: {
            uri: "file://#{File.expand_path("test_completion.rb")}"
          },
          position: {
            line: 11,
            character: 4
          }
        }
      }.to_json

      response = session.send_message(completion_msg)
      response.should_not be_nil

      session.close
    end

    it "handles textDocument/references request" do
      session = SorbetSession.new

      content = <<-RUBY
      class ReferencesTest
        def target_method
          42
        end

        def caller
          target_method
        end
      end
      RUBY

      session.typecheck_file("test_references.rb", content)

      references_msg = {
        jsonrpc: "2.0",
        id: 4,
        method: "textDocument/references",
        params: {
          textDocument: {
            uri: "file://#{File.expand_path("test_references.rb")}"
          },
          position: {
            line: 1,
            character: 8
          },
          context: {
            includeDeclaration: true
          }
        }
      }.to_json

      response = session.send_message(references_msg)
      response.should_not be_nil

      session.close
    end

    it "handles textDocument/documentSymbol request" do
      session = SorbetSession.new

      content = <<-RUBY
      class SymbolTest
        def method_one
          1
        end

        def method_two
          2
        end
      end
      RUBY

      session.typecheck_file("test_symbols.rb", content)

      symbols_msg = {
        jsonrpc: "2.0",
        id: 5,
        method: "textDocument/documentSymbol",
        params: {
          textDocument: {
            uri: "file://#{File.expand_path("test_symbols.rb")}"
          }
        }
      }.to_json

      response = session.send_message(symbols_msg)
      response.should_not be_nil

      session.close
    end
  end

  describe "publishDiagnostics Notification" do
    it "receives diagnostics for code with type errors" do
      session = SorbetSession.new

      content = <<-RUBY
      # typed: strict
      class TypedTest
        extend T::Sig

        sig {returns(Integer)}
        def get_number
          "not a number"  # Type error
        end
      end
      RUBY

      diagnostics = session.typecheck_file("test_diagnostics.rb", content)
      diagnostics.should_not be_empty

      session.close
    end

    it "receives empty diagnostics for valid code" do
      session = SorbetSession.new

      content = <<-RUBY
      class ValidCode
        def valid_method
          42
        end
      end
      RUBY

      diagnostics = session.typecheck_file("test_valid.rb", content)
      diagnostics.should be_empty

      session.close
    end
  end

  describe "JSON-RPC Protocol" do
    it "handles requests with id field" do
      session = SorbetSession.new

      msg_with_id = {
        jsonrpc: "2.0",
        id: 999,
        method: "textDocument/hover",
        params: {
          textDocument: {
            uri: "file://#{Dir.current}/test.rb"
          },
          position: {
            line: 0,
            character: 0
          }
        }
      }.to_json

      session.send_message(msg_with_id)
      session.close
    end

    it "handles notifications without id field" do
      session = SorbetSession.new

      msg_without_id = {
        jsonrpc: "2.0",
        method: "textDocument/didOpen",
        params: {
          textDocument: {
            uri: "file://#{Dir.current}/test.rb",
            languageId: "ruby",
            version: 1,
            text: "class Test; end"
          }
        }
      }.to_json

      session.send_message(msg_without_id)
      session.close
    end
  end
end
