require_relative 'circular_a'

class CircularB
  def self.method_b
    CircularA.method_a
  end
end