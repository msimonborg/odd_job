defmodule OddJob.RegistryTest do
  use ExUnit.Case
  import OddJob.Registry

  describe "via/2" do
    test "returns a name suitable for use in :via registration" do
      assert via(:job, "pool sup") == {:via, Registry, {OddJob.Registry, {:job, "pool sup"}}}
    end
  end
end
