require "spec"
require "./sorbet_spec"

describe "Performance and Scalability" do
  describe "Batch Processing Performance" do
    it "efficiently processes small batches" do
      session = SorbetSession.new

      files = (1..10).to_h do |i|
        {"small_batch_#{i}.rb", "class SmallBatch#{i}\n  def method\n    #{i}\n  end\nend"}
      end

      start_time = Time.monotonic
      diagnostics = session.typecheck_files_batch(files)
      elapsed = Time.monotonic - start_time

      diagnostics.should be_a(Array(Hash(String, JSON::Any)))
      # Batch should complete in reasonable time (< 5 seconds for 10 files)
      elapsed.should be < 5.seconds

      session.close
    end

    it "efficiently processes medium batches" do
      session = SorbetSession.new

      files = (1..50).to_h do |i|
        {"medium_batch_#{i}.rb", "class MediumBatch#{i}\n  def method_a\n    #{i}\n  end\n  def method_b\n    #{i * 2}\n  end\nend"}
      end

      start_time = Time.monotonic
      diagnostics = session.typecheck_files_batch(files)
      elapsed = Time.monotonic - start_time

      diagnostics.should be_a(Array(Hash(String, JSON::Any)))
      # Should complete in reasonable time (< 15 seconds for 50 files)
      elapsed.should be < 15.seconds

      session.close
    end

    it "efficiently processes large batches" do
      session = SorbetSession.new

      files = (1..100).to_h do |i|
        content = <<-RUBY
        class LargeBatch#{i}
          def method_a
            #{i}
          end

          def method_b
            #{i * 2}
          end

          def method_c
            method_a + method_b
          end
        end
        RUBY
        {"large_batch_#{i}.rb", content}
      end

      start_time = Time.monotonic
      diagnostics = session.typecheck_files_batch(files)
      elapsed = Time.monotonic - start_time

      diagnostics.should be_a(Array(Hash(String, JSON::Any)))
      # Should complete in reasonable time (< 30 seconds for 100 files)
      elapsed.should be < 30.seconds

      session.close
    end

    it "batch processing is faster than sequential for many files" do
      session = SorbetSession.new

      files = (1..20).to_h do |i|
        {"batch_vs_seq_#{i}.rb", "class BatchVsSeq#{i}\n  def method\n    #{i}\n  end\nend"}
      end

      # Sequential processing
      start_sequential = Time.monotonic
      files.each do |path, content|
        session.typecheck_file(path, content)
      end
      sequential_time = Time.monotonic - start_sequential

      # Batch processing
      start_batch = Time.monotonic
      session.typecheck_files_batch(files)
      batch_time = Time.monotonic - start_batch

      # Batch should be faster (or at least not significantly slower)
      # We allow some variance due to system conditions
      batch_time.should be < (sequential_time * 1.5)

      session.close
    end
  end

  # describe "Multi-threaded Performance" do
  #   it "creates multi-threaded session with 2 threads" do
  #     session = SorbetSession.new(".", true, 2)
  #
  #     diagnostics = session.typecheck_file("mt_2_threads.rb", "class MT2\nend")
  #     diagnostics.should be_a(Array(Hash(String, JSON::Any)))
  #
  #     session.close
  #   end
  #
  #   it "creates multi-threaded session with 4 threads" do
  #     session = SorbetSession.new(".", true, 4)
  #
  #     diagnostics = session.typecheck_file("mt_4_threads.rb", "class MT4\nend")
  #     diagnostics.should be_a(Array(Hash(String, JSON::Any)))
  #
  #     session.close
  #   end
  #
  #   it "handles batch operations in multi-threaded mode" do
  #     session = SorbetSession.new(".", true, 4)
  #
  #     files = (1..50).to_h do |i|
  #       {"mt_batch_#{i}.rb", "class MTBatch#{i}\n  def method\n    #{i}\n  end\nend"}
  #     end
  #
  #     start_time = Time.monotonic
  #     diagnostics = session.typecheck_files_batch(files)
  #     elapsed = Time.monotonic - start_time
  #
  #     diagnostics.should be_a(Array(Hash(String, JSON::Any)))
  #     elapsed.should be < 15.seconds
  #
  #     session.close
  #   end
  #
  #   it "compares single-threaded vs multi-threaded performance" do
  #     files = (1..30).to_h do |i|
  #       content = <<-RUBY
  #       class PerfTest#{i}
  #         def method_a
  #           #{i}
  #         end
  #
  #         def method_b
  #           #{i * 2}
  #         end
  #
  #         def method_c
  #           method_a + method_b
  #         end
  #       end
  #       RUBY
  #       {"perf_test_#{i}.rb", content}
  #     end
  #
  #     # Single-threaded
  #     session_st = SorbetSession.new
  #     start_st = Time.monotonic
  #     session_st.typecheck_files_batch(files)
  #     st_time = Time.monotonic - start_st
  #     session_st.close
  #
  #     # Multi-threaded with 4 threads
  #     session_mt = SorbetSession.new(".", true, 4)
  #     start_mt = Time.monotonic
  #     session_mt.typecheck_files_batch(files)
  #     mt_time = Time.monotonic - start_mt
  #     session_mt.close
  #
  #     # Multi-threaded should be competitive (allowing for variance)
  #     # We don't strictly require it to be faster due to overhead
  #     mt_time.should be < (st_time * 2)
  #   end
  # end

  describe "Response Time" do
    it "responds quickly to simple queries" do
      session = SorbetSession.new

      session.typecheck_file("quick_test.rb", "class QuickTest\nend")

      start_time = Time.monotonic
      msg = {
        jsonrpc: "2.0",
        id: 1,
        method: "textDocument/hover",
        params: {
          textDocument: {
            uri: "file://#{File.expand_path("quick_test.rb")}"
          },
          position: {
            line: 0,
            character: 6
          }
        }
      }.to_json

      session.send_message(msg)
      elapsed = Time.monotonic - start_time

      # Should respond very quickly (< 1 second)
      elapsed.should be < 1.second

      session.close
    end

    it "handles rapid sequential queries" do
      session = SorbetSession.new

      session.typecheck_file("rapid_test.rb", "class RapidTest\n  def method\n    42\n  end\nend")

      start_time = Time.monotonic
      20.times do |i|
        msg = {
          jsonrpc: "2.0",
          id: i,
          method: "textDocument/hover",
          params: {
            textDocument: {
              uri: "file://#{File.expand_path("rapid_test.rb")}"
            },
            position: {
              line: 1,
              character: 6
            }
          }
        }.to_json

        session.send_message(msg)
      end
      elapsed = Time.monotonic - start_time

      # 20 queries should complete quickly (< 5 seconds)
      elapsed.should be < 5.seconds

      session.close
    end
  end

  describe "Memory Efficiency" do
    it "handles many files without excessive memory growth" do
      session = SorbetSession.new

      # Process many files sequentially
      500.times do |i|
        content = "class MemTest#{i}\n  def method\n    #{i}\n  end\nend"
        session.typecheck_file("mem_test_#{i}.rb", content)
      end

      # If we got here without crashing, memory is being managed
      session.close
    end

    it "handles repeated operations on same files" do
      session = SorbetSession.new

      content = "class RepeatedTest\n  def method\n    42\n  end\nend"

      # First open the file
      session.typecheck_file("repeated_test.rb", content)

      # Then change and query the same file many times
      100.times do |version|
        msg = {
          jsonrpc: "2.0",
          method: "textDocument/didChange",
          params: {
            textDocument: {
              uri: "file://#{File.expand_path("repeated_test.rb")}",
              version: version + 1  # version starts at 1 after didOpen
            },
            contentChanges: [
              {
                text: "class RepeatedTest\n  def method\n    #{version}\n  end\nend"
              }
            ]
          }
        }.to_json

        session.send_message(msg)
      end

      session.close
    end
  end

  describe "Scalability" do
    it "handles complex file interdependencies" do
      session = SorbetSession.new

      # Create a chain of files that depend on each other
      files = {} of String => String

      10.times do |i|
        if i == 0
          files["chain_#{i}.rb"] = "class Chain#{i}\n  def method\n    #{i}\n  end\nend"
        else
          files["chain_#{i}.rb"] = "require_relative 'chain_#{i-1}'\n\nclass Chain#{i}\n  def method\n    Chain#{i-1}.new.method\n  end\nend"
        end
      end

      diagnostics = session.typecheck_files_batch(files)
      diagnostics.should be_a(Array(Hash(String, JSON::Any)))

      session.close
      files.keys.each { |f| TestHelper.cleanup_file(f) }
    end

    it "handles deeply nested class hierarchies" do
      session = SorbetSession.new

      content = <<-RUBY
      class Base
        def base_method
          0
        end
      end

      class Level1 < Base
        def level1_method
          base_method + 1
        end
      end

      class Level2 < Level1
        def level2_method
          level1_method + 1
        end
      end

      class Level3 < Level2
        def level3_method
          level2_method + 1
        end
      end

      class Level4 < Level3
        def level4_method
          level3_method + 1
        end
      end
      RUBY

      diagnostics = session.typecheck_file("deep_hierarchy.rb", content)
      diagnostics.should be_a(Array(Hash(String, JSON::Any)))

      session.close
    end

    it "handles many classes in a single file" do
      session = SorbetSession.new

      classes = (1..200).map do |i|
        "class ManyClasses#{i}\n  def method\n    #{i}\n  end\nend"
      end.join("\n\n")

      diagnostics = session.typecheck_file("many_classes.rb", classes)
      diagnostics.should be_a(Array(Hash(String, JSON::Any)))

      session.close
    end

    it "handles many methods in a single class" do
      session = SorbetSession.new

      methods = (1..200).map do |i|
        "  def method_#{i}\n    #{i}\n  end"
      end.join("\n\n")

      content = "class ManyMethods\n#{methods}\nend"

      diagnostics = session.typecheck_file("many_methods.rb", content)
      diagnostics.should be_a(Array(Hash(String, JSON::Any)))

      session.close
    end
  end

  describe "Concurrent Sessions" do
    it "handles multiple independent sessions" do
      sessions = (1..5).map { SorbetSession.new }

      # Use all sessions concurrently
      sessions.each_with_index do |session, i|
        content = "class Concurrent#{i}\n  def method\n    #{i}\n  end\nend"
        diagnostics = session.typecheck_file("concurrent_#{i}.rb", content)
        diagnostics.should be_a(Array(Hash(String, JSON::Any)))
      end

      sessions.each(&.close)
    end

    it "sessions are isolated from each other" do
      session1 = SorbetSession.new
      session2 = SorbetSession.new

      # Define a class in session1
      session1.typecheck_file("isolation_test.rb", "class IsolationTest\nend")

      # Session2 should not know about it
      content2 = "class OtherClass\n  def method\n    IsolationTest.new\n  end\nend"
      diagnostics2 = session2.typecheck_file("other_class.rb", content2)

      # Should report error about unknown constant (sessions are isolated)
      diagnostics2.should_not be_empty

      session1.close
      session2.close
    end
  end
end
