require "spec"
require "./sorbet_spec"

describe SorbetSession do
  it "initializes and closes properly" do
    session = SorbetSession.new
    session.close
    # Should not raise
  end

  it "handles simple Ruby code without errors" do
    session = SorbetSession.new
    
    filename = "test_simple.rb"
    content = TestHelper.simple_ruby_code
    
    diagnostics = session.typecheck_file(filename, content)
    
    diagnostics.should be_empty
    
    session.close
    TestHelper.cleanup_file(filename)
  end

  it "detects errors in Ruby code" do
    session = SorbetSession.new
    
    filename = "test_error.rb"
    content = TestHelper.code_with_error
    
    diagnostics = session.typecheck_file(filename, content)
    
    diagnostics.should_not be_empty
    diagnostics.any? { |d| d["message"].to_s.includes?("undefined_method_call") }.should be_true
    
    session.close
    TestHelper.cleanup_file(filename)
  end

  it "handles file with require statements" do
    session = SorbetSession.new
    
    # Create helper file
    helper_filename = "helper_test.rb"
    helper_content = TestHelper.helper_code
    File.write(helper_filename, helper_content)
    
    # Create main file
    main_filename = "main_test.rb"
    main_content = TestHelper.code_with_require
    
    # Typecheck both files
    session.typecheck_file(helper_filename, helper_content)
    diagnostics = session.typecheck_file(main_filename, main_content)
    
    # Should have no errors if helper is available
    diagnostics.should be_empty
    
    session.close
    TestHelper.cleanup_file(helper_filename)
    TestHelper.cleanup_file(main_filename)
  end

  it "handles batch processing" do
    session = SorbetSession.new
    
    files = {
      "file1.rb" => TestHelper.simple_ruby_code,
      "file2.rb" => TestHelper.simple_ruby_code
    }
    
    diagnostics = session.typecheck_files_batch(files)
    
    diagnostics.should be_empty
    
    session.close
    files.keys.each { |filename| TestHelper.cleanup_file(filename) }
  end

  it "handles multi-threaded session" do
    session = SorbetSession.new(".", true, 2)
    
    filename = "test_mt.rb"
    content = TestHelper.simple_ruby_code
    
    diagnostics = session.typecheck_file(filename, content)
    
    diagnostics.should be_empty
    
    session.close
    TestHelper.cleanup_file(filename)
  end
end