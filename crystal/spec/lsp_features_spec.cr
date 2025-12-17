require "spec"
require "./sorbet_spec"

describe "LSP Features" do
  describe "Hover Feature" do
    it "provides hover information for class names" do
      session = SorbetSession.new

      content = <<-RUBY
      class HoverTest
        def method
          42
        end
      end

      HoverTest.new
      RUBY

      session.typecheck_file("hover_class.rb", content)

      hover_msg = {
        jsonrpc: "2.0",
        id: 1,
        method: "textDocument/hover",
        params: {
          textDocument: {
            uri: "file://#{File.expand_path("hover_class.rb")}"
          },
          position: {
            line: 6,
            character: 0
          }
        }
      }.to_json

      response = session.send_message(hover_msg)
      response.should_not be_nil

      session.close
    end

    it "provides hover information for method names" do
      session = SorbetSession.new

      content = <<-RUBY
      class MethodHover
        def target_method
          "result"
        end

        def caller_method
          target_method
        end
      end
      RUBY

      session.typecheck_file("hover_method.rb", content)

      hover_msg = {
        jsonrpc: "2.0",
        id: 2,
        method: "textDocument/hover",
        params: {
          textDocument: {
            uri: "file://#{File.expand_path("hover_method.rb")}"
          },
          position: {
            line: 6,
            character: 4
          }
        }
      }.to_json

      response = session.send_message(hover_msg)
      response.should_not be_nil

      session.close
    end

    it "provides hover information for variables" do
      session = SorbetSession.new

      content = <<-RUBY
      class VariableHover
        def method
          local_var = 42
          local_var + 1
        end
      end
      RUBY

      session.typecheck_file("hover_variable.rb", content)

      hover_msg = {
        jsonrpc: "2.0",
        id: 3,
        method: "textDocument/hover",
        params: {
          textDocument: {
            uri: "file://#{File.expand_path("hover_variable.rb")}"
          },
          position: {
            line: 3,
            character: 4
          }
        }
      }.to_json

      response = session.send_message(hover_msg)
      response.should_not be_nil

      session.close
    end

    it "provides hover information for constants" do
      session = SorbetSession.new

      content = <<-RUBY
      class ConstantHover
        MY_CONSTANT = 42

        def use_constant
          MY_CONSTANT + 1
        end
      end
      RUBY

      session.typecheck_file("hover_constant.rb", content)

      hover_msg = {
        jsonrpc: "2.0",
        id: 4,
        method: "textDocument/hover",
        params: {
          textDocument: {
            uri: "file://#{File.expand_path("hover_constant.rb")}"
          },
          position: {
            line: 4,
            character: 4
          }
        }
      }.to_json

      response = session.send_message(hover_msg)
      response.should_not be_nil

      session.close
    end
  end

  describe "Go to Definition" do
    it "finds definition of method" do
      session = SorbetSession.new

      content = <<-RUBY
      class DefinitionTest
        def target_method
          42
        end

        def caller
          target_method
        end
      end
      RUBY

      session.typecheck_file("definition_test.rb", content)

      definition_msg = {
        jsonrpc: "2.0",
        id: 5,
        method: "textDocument/definition",
        params: {
          textDocument: {
            uri: "file://#{File.expand_path("definition_test.rb")}"
          },
          position: {
            line: 6,
            character: 6
          }
        }
      }.to_json

      response = session.send_message(definition_msg)
      response.should_not be_nil

      session.close
    end

    it "finds definition across files" do
      session = SorbetSession.new

      helper_content = <<-RUBY
      class HelperClass
        def helper_method
          "helper"
        end
      end
      RUBY

      main_content = <<-RUBY
      require_relative 'definition_helper'

      class MainClass
        def use_helper
          HelperClass.new.helper_method
        end
      end
      RUBY

      File.write("definition_helper.rb", helper_content)

      session.typecheck_file("definition_helper.rb", helper_content)
      session.typecheck_file("definition_main.rb", main_content)

      definition_msg = {
        jsonrpc: "2.0",
        id: 6,
        method: "textDocument/definition",
        params: {
          textDocument: {
            uri: "file://#{File.expand_path("definition_main.rb")}"
          },
          position: {
            line: 4,
            character: 22
          }
        }
      }.to_json

      response = session.send_message(definition_msg)
      response.should_not be_nil

      session.close
      TestHelper.cleanup_file("definition_helper.rb")
    end

    it "finds definition of class" do
      session = SorbetSession.new

      content = <<-RUBY
      class TargetClass
        def method
          1
        end
      end

      obj = TargetClass.new
      RUBY

      session.typecheck_file("class_definition.rb", content)

      definition_msg = {
        jsonrpc: "2.0",
        id: 7,
        method: "textDocument/definition",
        params: {
          textDocument: {
            uri: "file://#{File.expand_path("class_definition.rb")}"
          },
          position: {
            line: 6,
            character: 6
          }
        }
      }.to_json

      response = session.send_message(definition_msg)
      response.should_not be_nil

      session.close
    end
  end

  describe "Completion" do
    it "provides method completions" do
      session = SorbetSession.new

      content = <<-RUBY
      class CompletionClass
        def method_one
          1
        end

        def method_two
          2
        end

        def method_three
          3
        end

        def use_methods
          self.
        end
      end
      RUBY

      session.typecheck_file("completion_methods.rb", content)

      completion_msg = {
        jsonrpc: "2.0",
        id: 8,
        method: "textDocument/completion",
        params: {
          textDocument: {
            uri: "file://#{File.expand_path("completion_methods.rb")}"
          },
          position: {
            line: 14,
            character: 9
          }
        }
      }.to_json

      response = session.send_message(completion_msg)
      response.should_not be_nil

      session.close
    end

    it "provides constant completions" do
      session = SorbetSession.new

      content = <<-RUBY
      module MyModule
        CONSTANT_ONE = 1
        CONSTANT_TWO = 2
        CONSTANT_THREE = 3
      end

      x = MyModule::
      RUBY

      session.typecheck_file("completion_constants.rb", content)

      completion_msg = {
        jsonrpc: "2.0",
        id: 9,
        method: "textDocument/completion",
        params: {
          textDocument: {
            uri: "file://#{File.expand_path("completion_constants.rb")}"
          },
          position: {
            line: 6,
            character: 14
          }
        }
      }.to_json

      response = session.send_message(completion_msg)
      response.should_not be_nil

      session.close
    end

    it "provides class method completions" do
      session = SorbetSession.new

      content = <<-RUBY
      class StaticMethods
        def self.static_one
          1
        end

        def self.static_two
          2
        end
      end

      StaticMethods.
      RUBY

      session.typecheck_file("completion_static.rb", content)

      completion_msg = {
        jsonrpc: "2.0",
        id: 10,
        method: "textDocument/completion",
        params: {
          textDocument: {
            uri: "file://#{File.expand_path("completion_static.rb")}"
          },
          position: {
            line: 10,
            character: 14
          }
        }
      }.to_json

      response = session.send_message(completion_msg)
      response.should_not be_nil

      session.close
    end
  end

  describe "Find References" do
    it "finds all references to a method" do
      session = SorbetSession.new

      content = <<-RUBY
      class ReferenceFinder
        def target_method
          42
        end

        def caller_one
          target_method
        end

        def caller_two
          target_method
        end

        def caller_three
          target_method
        end
      end
      RUBY

      session.typecheck_file("references_test.rb", content)

      references_msg = {
        jsonrpc: "2.0",
        id: 11,
        method: "textDocument/references",
        params: {
          textDocument: {
            uri: "file://#{File.expand_path("references_test.rb")}"
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

    it "finds references to a class" do
      session = SorbetSession.new

      content = <<-RUBY
      class TargetClass
        def method
          1
        end
      end

      obj1 = TargetClass.new
      obj2 = TargetClass.new
      obj3 = TargetClass.new
      RUBY

      session.typecheck_file("class_references.rb", content)

      references_msg = {
        jsonrpc: "2.0",
        id: 12,
        method: "textDocument/references",
        params: {
          textDocument: {
            uri: "file://#{File.expand_path("class_references.rb")}"
          },
          position: {
            line: 0,
            character: 6
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
  end

  describe "Document Symbols" do
    it "lists all symbols in a document" do
      session = SorbetSession.new

      content = <<-RUBY
      class DocumentSymbolsTest
        CONSTANT = 42

        def method_one
          1
        end

        def method_two
          2
        end

        def self.class_method
          3
        end
      end

      module TestModule
        def module_method
          4
        end
      end
      RUBY

      session.typecheck_file("document_symbols.rb", content)

      symbols_msg = {
        jsonrpc: "2.0",
        id: 13,
        method: "textDocument/documentSymbol",
        params: {
          textDocument: {
            uri: "file://#{File.expand_path("document_symbols.rb")}"
          }
        }
      }.to_json

      response = session.send_message(symbols_msg)
      response.should_not be_nil

      session.close
    end

    it "handles nested class structures" do
      session = SorbetSession.new

      content = <<-RUBY
      class OuterClass
        class InnerClass
          def inner_method
            1
          end
        end

        def outer_method
          2
        end
      end
      RUBY

      session.typecheck_file("nested_symbols.rb", content)

      symbols_msg = {
        jsonrpc: "2.0",
        id: 14,
        method: "textDocument/documentSymbol",
        params: {
          textDocument: {
            uri: "file://#{File.expand_path("nested_symbols.rb")}"
          }
        }
      }.to_json

      response = session.send_message(symbols_msg)
      response.should_not be_nil

      session.close
    end
  end

  describe "Type Definition" do
    it "finds type definition for variables" do
      session = SorbetSession.new

      content = <<-RUBY
      class MyType
        def type_method
          1
        end
      end

      def get_instance
        MyType.new
      end

      var = get_instance
      RUBY

      session.typecheck_file("type_definition.rb", content)

      type_def_msg = {
        jsonrpc: "2.0",
        id: 15,
        method: "textDocument/typeDefinition",
        params: {
          textDocument: {
            uri: "file://#{File.expand_path("type_definition.rb")}"
          },
          position: {
            line: 10,
            character: 0
          }
        }
      }.to_json

      response = session.send_message(type_def_msg)
      response.should_not be_nil

      session.close
    end
  end

  describe "Signature Help" do
    it "provides signature help for method calls" do
      session = SorbetSession.new

      content = <<-RUBY
      class SignatureTest
        extend T::Sig

        sig {params(x: Integer, y: Integer, z: String).returns(String)}
        def complex_method(x, y, z)
          "\#{x + y}: \#{z}"
        end

        def caller
          complex_method(
        end
      end
      RUBY

      session.typecheck_file("signature_help.rb", content)

      signature_msg = {
        jsonrpc: "2.0",
        id: 16,
        method: "textDocument/signatureHelp",
        params: {
          textDocument: {
            uri: "file://#{File.expand_path("signature_help.rb")}"
          },
          position: {
            line: 9,
            character: 21
          }
        }
      }.to_json

      response = session.send_message(signature_msg)
      response.should_not be_nil

      session.close
    end
  end

  describe "Document Highlighting" do
    it "highlights all occurrences of a symbol" do
      session = SorbetSession.new

      content = <<-RUBY
      class HighlightTest
        def target_symbol
          local_var = 42
          local_var + local_var
        end
      end
      RUBY

      session.typecheck_file("highlight_test.rb", content)

      highlight_msg = {
        jsonrpc: "2.0",
        id: 17,
        method: "textDocument/documentHighlight",
        params: {
          textDocument: {
            uri: "file://#{File.expand_path("highlight_test.rb")}"
          },
          position: {
            line: 2,
            character: 4
          }
        }
      }.to_json

      response = session.send_message(highlight_msg)
      response.should_not be_nil

      session.close
    end
  end

  describe "Workspace Symbols" do
    it "searches for symbols across workspace" do
      session = SorbetSession.new

      content1 = <<-RUBY
      class WorkspaceClass1
        def method1
          1
        end
      end
      RUBY

      content2 = <<-RUBY
      class WorkspaceClass2
        def method2
          2
        end
      end
      RUBY

      session.typecheck_file("workspace1.rb", content1)
      session.typecheck_file("workspace2.rb", content2)

      workspace_symbols_msg = {
        jsonrpc: "2.0",
        id: 18,
        method: "workspace/symbol",
        params: {
          query: "Workspace"
        }
      }.to_json

      response = session.send_message(workspace_symbols_msg)
      response.should_not be_nil

      session.close
    end
  end

  describe "Code Actions" do
    it "requests code actions for a range" do
      session = SorbetSession.new

      content = <<-RUBY
      class CodeActionTest
        def method_with_issue
          undefined_variable
        end
      end
      RUBY

      session.typecheck_file("code_action.rb", content)

      code_action_msg = {
        jsonrpc: "2.0",
        id: 19,
        method: "textDocument/codeAction",
        params: {
          textDocument: {
            uri: "file://#{File.expand_path("code_action.rb")}"
          },
          range: {
            start: {line: 2, character: 4},
            end: {line: 2, character: 21}
          },
          context: {
            diagnostics: [] of String
          }
        }
      }.to_json

      response = session.send_message(code_action_msg)
      response.should_not be_nil

      session.close
    end
  end

  describe "Formatting" do
    it "requests document formatting" do
      session = SorbetSession.new

      content = <<-RUBY
      class FormattingTest
      def poorly_formatted
      x=1+2
      y=3+4
      x+y
      end
      end
      RUBY

      session.typecheck_file("formatting.rb", content)

      format_msg = {
        jsonrpc: "2.0",
        id: 20,
        method: "textDocument/formatting",
        params: {
          textDocument: {
            uri: "file://#{File.expand_path("formatting.rb")}"
          },
          options: {
            tabSize: 2,
            insertSpaces: true
          }
        }
      }.to_json

      response = session.send_message(format_msg)
      response.should_not be_nil

      session.close
    end
  end

  describe "Rename" do
    it "handles prepare rename request" do
      session = SorbetSession.new

      content = <<-RUBY
      class RenameTest
        def old_name
          42
        end

        def caller
          old_name
        end
      end
      RUBY

      session.typecheck_file("rename_test.rb", content)

      prepare_rename_msg = {
        jsonrpc: "2.0",
        id: 21,
        method: "textDocument/prepareRename",
        params: {
          textDocument: {
            uri: "file://#{File.expand_path("rename_test.rb")}"
          },
          position: {
            line: 1,
            character: 8
          }
        }
      }.to_json

      response = session.send_message(prepare_rename_msg)
      response.should_not be_nil

      session.close
    end

    it "handles rename request" do
      session = SorbetSession.new

      content = <<-RUBY
      class RenameTest
        def old_name
          42
        end

        def caller
          old_name
        end
      end
      RUBY

      session.typecheck_file("rename_full.rb", content)

      rename_msg = {
        jsonrpc: "2.0",
        id: 22,
        method: "textDocument/rename",
        params: {
          textDocument: {
            uri: "file://#{File.expand_path("rename_full.rb")}"
          },
          position: {
            line: 1,
            character: 8
          },
          newName: "new_name"
        }
      }.to_json

      response = session.send_message(rename_msg)
      response.should_not be_nil

      session.close
    end
  end
end
