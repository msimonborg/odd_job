defmodule OddJobTest do
  use ExUnit.Case, async: false
  use ExUnitReceiver, as: :stash
  import OddJob
  doctest OddJob

  setup do
    start_stash(fn -> [] end)
    :ok
  end

  describe "perform" do
    test "can perform concurrent fire and forget jobs" do
      parent = self()
      perform(:test, fn -> Process.send_after(parent, :hello, 10) end)

      result =
        receive do
          msg -> msg
        after
          5 -> :nothing
        end

      assert result == :nothing

      result =
        receive do
          msg -> msg
        after
          10 -> :nothing
        end

      assert result == :hello
    end

    test "can queue up and perform many jobs" do
      perform_expensive_jobs(1..10)
      Process.sleep(5)
      assert get_stash() |> Enum.sort() == Enum.to_list(1..5)
      Process.sleep(5)
      assert get_stash() |> Enum.sort() == Enum.to_list(1..10)
      Process.sleep(5)
    end

    test "can instantly start, assign, and monitor a new worker when one fails" do
      perform_expensive_jobs(1..10)
      perform(:test, fn -> Process.exit(self(), :kill) end)
      perform_expensive_jobs(11..20)
      Process.sleep(5)
      assert get_stash() |> Enum.sort() == Enum.to_list(1..5)
      Process.sleep(10)
      assert get_stash() |> Enum.sort() == Enum.to_list(1..10)
      Process.sleep(10)
      assert get_stash() |> Enum.sort() == Enum.to_list(1..15)
      Process.sleep(10)
      assert get_stash() |> Enum.sort() == Enum.to_list(1..20)
      Process.sleep(10)
    end
  end

  defp perform_expensive_jobs(range) do
    for i <- range do
      perform(:test, fn ->
        update_stash(fn x -> x ++ [i] end)
        Process.sleep(10)
      end)
    end
  end
end
