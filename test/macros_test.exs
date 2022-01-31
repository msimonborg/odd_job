defmodule MacrosTest do
  use ExUnit.Case, async: false
  use OddJob

  describe "perform_this/2" do
    test "performs a fire and forget job" do
      caller = self()
      t1 = Time.utc_now()

      perform_this :work do
        Process.sleep(10)
        send(caller, :hello)
      end

      t2 = Time.utc_now()
      assert Time.diff(t2, t1, :millisecond) < 10

      result =
        receive do
          msg -> msg
        end

      assert result == :hello
    end
  end

  describe "perform_this/3 async" do
    test "performs an async job that can be awaited on" do
      value = 100.0

      job =
        perform_this :work, :async do
          :math.exp(value)
          |> :math.log()
        end

      assert await(job) == value
    end
  end
end
