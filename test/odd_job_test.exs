defmodule OddJobTest do
  use ExUnit.Case
  doctest OddJob

  test "greets the world" do
    assert OddJob.hello() == :world
  end
end
