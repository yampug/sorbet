require "./sorbet_spec"

describe "SorbetSession Require Resolution" do
  it "handles require_relative correctly" do
    session = SorbetSession.new
    
    # Create helper file
    helper_filename = "require_helper.rb"
    helper_content = <<-RUBY
class RequireHelper
  def self.helper_method
    "Helper response"
  end
end
RUBY
    File.write(helper_filename, helper_content)
    
    # Create main file that requires the helper
    main_filename = "require_main.rb"
    main_content = <<-RUBY
require_relative 'require_helper'

class MainClass
  def self.run
    RequireHelper.helper_method
  end
end

MainClass.run
RUBY
    
    # Typecheck both files
    helper_diagnostics = session.typecheck_file(helper_filename, helper_content)
    main_diagnostics = session.typecheck_file(main_filename, main_content)
    
    # Both should have no errors
    helper_diagnostics.should be_empty
    main_diagnostics.should be_empty
    
    session.close
    TestHelper.cleanup_file(helper_filename)
    TestHelper.cleanup_file(main_filename)
  end

  it "handles nested require_relative statements" do
    session = SorbetSession.new
    
    # Create base helper
    base_helper_filename = "base_helper.rb"
    base_helper_content = <<-RUBY
class BaseHelper
  def self.base_method
    "Base"
  end
end
RUBY
    File.write(base_helper_filename, base_helper_content)
    
    # Create intermediate helper that requires base
    intermediate_filename = "intermediate_helper.rb"
    intermediate_content = <<-RUBY
require_relative 'base_helper'

class IntermediateHelper
  def self.intermediate_method
    BaseHelper.base_method
  end
end
RUBY
    File.write(intermediate_filename, intermediate_content)
    
    # Create main file that requires intermediate
    main_filename = "nested_main.rb"
    main_content = <<-RUBY
require_relative 'intermediate_helper'

class NestedMain
  def self.run
    IntermediateHelper.intermediate_method
  end
end

NestedMain.run
RUBY
    
    # Typecheck all files in order
    session.typecheck_file(base_helper_filename, base_helper_content)
    session.typecheck_file(intermediate_filename, intermediate_content)
    main_diagnostics = session.typecheck_file(main_filename, main_content)
    
    # Should have no errors
    main_diagnostics.should be_empty
    
    session.close
    TestHelper.cleanup_file(base_helper_filename)
    TestHelper.cleanup_file(intermediate_filename)
    TestHelper.cleanup_file(main_filename)
  end

  it "handles require with standard library classes" do
    session = SorbetSession.new
    
    filename = "std_lib_test.rb"
    content = <<-RUBY
require 'json'

class JsonTest
  def self.run
    JSON.parse('{"test": "value"}')
  end
end

JsonTest.run
RUBY
    
    diagnostics = session.typecheck_file(filename, content)
    
    # Should handle standard library requires (may have some warnings but not errors)
    # The exact behavior depends on Sorbet's RBI files
    diagnostics.should be_empty
    
    session.close
    TestHelper.cleanup_file(filename)
  end

  it "handles missing required files gracefully" do
    session = SorbetSession.new
    
    filename = "missing_require.rb"
    content = <<-RUBY
require_relative 'non_existent_file'

class TestClass
  def self.run
    # Some code
  end
end
RUBY
    
    diagnostics = session.typecheck_file(filename, content)
    
    # Should report an error about the missing file
    diagnostics.should_not be_empty
    diagnostics.any? { |d| 
      d["message"].to_s.includes?("non_existent_file") || 
      d["message"].to_s.includes?("Cannot find")
    }.should be_true
    
    session.close
    TestHelper.cleanup_file(filename)
  end

  it "handles circular requires" do
    session = SorbetSession.new
    
    # Create file A that requires B
    file_a = "circular_a.rb"
    content_a = <<-RUBY
require_relative 'circular_b'

class CircularA
  def self.method_a
    CircularB.method_b
  end
end
RUBY
    File.write(file_a, content_a)
    
    # Create file B that requires A
    file_b = "circular_b.rb"
    content_b = <<-RUBY
require_relative 'circular_a'

class CircularB
  def self.method_b
    CircularA.method_a
  end
end
RUBY
    File.write(file_b, content_b)
    
    # Typecheck both files
    diagnostics_a = session.typecheck_file(file_a, content_a)
    diagnostics_b = session.typecheck_file(file_b, content_b)
    
    # Sorbet should handle circular requires (may have some warnings)
    # The exact behavior depends on Sorbet's handling
    (diagnostics_a + diagnostics_b).should be_empty
    
    session.close
    TestHelper.cleanup_file(file_a)
    TestHelper.cleanup_file(file_b)
  end
end