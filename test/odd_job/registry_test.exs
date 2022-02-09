defmodule OddJob.RegistryTest do
  use ExUnit.Case
  import OddJob.Registry
  doctest OddJob.Registry

  describe "via/2" do
    test "returns a name suitable for use in :via registration" do
      assert via(:job, :pool_sup) == {:via, Registry, {OddJob.Registry, {:job, :pool_sup}}}
    end
  end
end
