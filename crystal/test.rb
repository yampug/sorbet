# typed: true
class Test
  extend T::Sig

  sig {returns(Integer)}
  def foo
    "not an integer"
  end
end
