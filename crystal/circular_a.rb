require_relative 'circular_b'

class CircularA
  def self.method_a
    CircularB.method_b
  end
end