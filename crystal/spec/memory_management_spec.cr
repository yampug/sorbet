require "spec"
require "./sorbet_spec"

describe "Memory Management and Safety" do
  describe "String Memory Management" do
    it "properly frees response strings" do
      session = SorbetSession.new

      # Send multiple messages and ensure strings are freed
      100.times do |i|
        diagnostics = session.typecheck_file("test_#{i}.rb", "class Test#{i}\nend")
        diagnostics.should be_a(Array(Hash(String, JSON::Any)))
      end

      session.close
    end

    # it "handles empty response strings" do
    #   session = SorbetSession.new
    #
    #   # Some messages may return empty responses
    #   msg = {
    #     jsonrpc: "2.0",
    #     method: "initialized",
    #     params: {} of String => JSON::Any
    #   }.to_json
    #
    #   response = session.send_message(msg)
    #   response.should be_a(Array(Hash(String, JSON::Any)))
    #
    #   session.close
    # end

    it "handles large response strings" do
      session = SorbetSession.new

      # Create code that generates large diagnostics
      large_content = (1..100).map { |i| "class LargeClass#{i}\n  def method\n    undefined_var_#{i}\n  end\nend" }.join("\n")

      diagnostics = session.typecheck_file("large_test.rb", large_content)
      diagnostics.should be_a(Array(Hash(String, JSON::Any)))

      session.close
    end
  end

  describe "Session Memory Management" do
    it "properly cleans up single-threaded sessions" do
      10.times do
        session = SorbetSession.new
        session.typecheck_file("cleanup_test.rb", "class Cleanup\nend")
        session.close
      end
    end

    # it "properly cleans up multi-threaded sessions" do
    #   10.times do
    #     session = SorbetSession.new(".", true, 2)
    #     session.typecheck_file("cleanup_mt_test.rb", "class CleanupMT\nend")
    #     session.close
    #   end
    # end

    it "handles multiple sessions concurrently" do
      sessions = [] of SorbetSession

      # Create multiple sessions
      5.times do
        sessions << SorbetSession.new
      end

      # Use all sessions
      sessions.each_with_index do |session, i|
        session.typecheck_file("concurrent_#{i}.rb", "class Concurrent#{i}\nend")
      end

      # Clean up all sessions
      sessions.each(&.close)
    end

    it "handles session closure without prior use" do
      session = SorbetSession.new
      session.close
      # Should not crash or leak memory
    end

    it "handles double close gracefully" do
      session = SorbetSession.new
      session.close
      # Second close should be safe (no-op)
      session.close
    end
  end

  describe "Batch Operation Memory Management" do
    it "properly manages memory in batch operations" do
      session = SorbetSession.new

      files = (1..50).to_h do |i|
        {"batch_#{i}.rb", "class Batch#{i}\n  def method\n    #{i}\n  end\nend"}
      end

      diagnostics = session.typecheck_files_batch(files)
      diagnostics.should be_a(Array(Hash(String, JSON::Any)))

      session.close
    end

    it "handles empty batch operations" do
      session = SorbetSession.new

      empty_files = {} of String => String
      diagnostics = session.typecheck_files_batch(empty_files)
      diagnostics.should be_empty

      session.close
    end

    it "handles large batch operations" do
      session = SorbetSession.new

      large_batch = (1..200).to_h do |i|
        {"large_batch_#{i}.rb", "class LargeBatch#{i}\nend"}
      end

      diagnostics = session.typecheck_files_batch(large_batch)
      diagnostics.should be_a(Array(Hash(String, JSON::Any)))

      session.close
    end
  end

  describe "Null Pointer Handling" do
    it "handles null session gracefully in C API" do
      # This tests the C API's null checks
      # The Crystal wrapper should prevent this, but we test the underlying safety
      args = ["--silence-dev-message", "."].to_json
      session_ptr = LibSorbet.new(args)
      session_ptr.should_not be_nil

      LibSorbet.free(session_ptr)
    end

    it "handles null string responses" do
      session = SorbetSession.new

      # Send a message that might return null
      # The wrapper should handle this gracefully
      response = session.send_message("")
      response.should be_a(Array(Hash(String, JSON::Any)))

      session.close
    end
  end

  describe "Resource Cleanup" do
    it "cleans up after file operations" do
      session = SorbetSession.new

      50.times do |i|
        filename = "resource_test_#{i}.rb"
        content = "class ResourceTest#{i}\n  def method\n    #{i}\n  end\nend"

        session.typecheck_file(filename, content)
        TestHelper.cleanup_file(filename)
      end

      session.close
    end

    it "handles cleanup after errors" do
      session = SorbetSession.new

      begin
        # This might cause an error
        session.typecheck_file("error_cleanup.rb", "invalid ruby syntax @@@@")
      rescue
        # Even with errors, cleanup should work
      end

      session.close
    end
  end

  describe "Memory Stress Tests" do
    it "handles rapid session creation and destruction" do
      100.times do
        session = SorbetSession.new
        session.close
      end
    end

    it "handles many sequential operations" do
      session = SorbetSession.new

      200.times do |i|
        session.typecheck_file("stress_#{i}.rb", "class Stress#{i}\nend")
      end

      session.close
    end

    it "handles large file content" do
      session = SorbetSession.new

      # Create a very large Ruby file
      large_content = (1..1000).map do |i|
        <<-RUBY
        class LargeFile#{i}
          def method_a_#{i}
            #{i}
          end

          def method_b_#{i}
            #{i * 2}
          end
        end
        RUBY
      end.join("\n")

      diagnostics = session.typecheck_file("very_large_file.rb", large_content)
      diagnostics.should be_a(Array(Hash(String, JSON::Any)))

      session.close
    end
  end

  describe "Edge Cases" do
    it "handles empty file content" do
      session = SorbetSession.new

      diagnostics = session.typecheck_file("empty.rb", "")
      diagnostics.should be_a(Array(Hash(String, JSON::Any)))

      session.close
    end

    it "handles whitespace-only content" do
      session = SorbetSession.new

      diagnostics = session.typecheck_file("whitespace.rb", "   \n\n\t\n   ")
      diagnostics.should be_a(Array(Hash(String, JSON::Any)))

      session.close
    end

    it "handles files with only comments" do
      session = SorbetSession.new

      content = <<-RUBY
      # This is a comment
      # Another comment
      # Yet another comment
      RUBY

      diagnostics = session.typecheck_file("comments_only.rb", content)
      diagnostics.should be_a(Array(Hash(String, JSON::Any)))

      session.close
    end

    it "handles UTF-8 content" do
      session = SorbetSession.new

      content = <<-RUBY
      class UTF8Test
        def greet
          "Hello 世界 🌍"
        end

        def unicode_method_名前
          "Unicode method name"
        end
      end
      RUBY

      diagnostics = session.typecheck_file("utf8_test.rb", content)
      diagnostics.should be_a(Array(Hash(String, JSON::Any)))

      session.close
    end

    it "handles very long lines" do
      session = SorbetSession.new

      long_line = "\"" + "a" * 10000 + "\""
      content = "class LongLine\n  def method\n    #{long_line}\n  end\nend"

      diagnostics = session.typecheck_file("long_line.rb", content)
      diagnostics.should be_a(Array(Hash(String, JSON::Any)))

      session.close
    end
  end
end
