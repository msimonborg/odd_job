defmodule OddJobTest do
  use ExUnit.Case, async: false
  use ExUnitReceiver, as: :stash

  import OddJob
  import OddJob.Guards

  doctest OddJob

  @pool :odd_job_test

  describe "is_enumerable/1" do
    test "guards against arguments that are not lists or maps" do
      assert is_enumerable([]) == true
      assert is_enumerable(%{}) == true
      assert is_enumerable(1..5) == true
      assert is_enumerable({:hello, :world}) == false
      assert is_enumerable("hello world") == false
    end
  end

  describe "is_timer/1" do
    test "guards against arguments that are not a non_neg_integer" do
      assert is_timer(10) == true
      assert is_timer(0) == true
      assert is_timer(-10) == false
      assert is_timer(:atom) == false
      assert is_timer(DateTime.utc_now()) == false
    end
  end

  describe "child_spec/1" do
    test "returns a valid child spec for a pool supervision tree" do
      assert child_spec(name: :spec_test) == %{
               id: :spec_test,
               start: {OddJob.Pool, :start_link, [[name: :spec_test]]},
               type: :supervisor
             }

      assert child_spec(name: :spec_test, pool_size: 10, max_restarts: 20) == %{
               id: :spec_test,
               start:
                 {OddJob.Pool, :start_link, [[name: :spec_test, pool_size: 10, max_restarts: 20]]},
               type: :supervisor
             }
    end

    test "raises an exception when the name is not an atom" do
      e = assert_raise ArgumentError, fn -> OddJob.child_spec(name: "Will raise") end
      assert String.contains?(e.message, "Expected `name` to be an atom.")
    end
  end

  describe "start_link/1" do
    test "dynamically starts an OddJob pool supervision tree" do
      {:ok, pid} = start_link(name: :start_link)
      assert pid == GenServer.whereis(:start_link)
      caller = self()
      perform(:start_link, fn -> send(caller, "hello from start_link") end)

      greeting =
        receive do
          msg -> msg
        end

      assert greeting == "hello from start_link"
      Supervisor.stop(:start_link)
    end

    test "accepts options for config overrides" do
      {:ok, _} = start_link(name: :option_test, pool_size: 50)
      assert length(workers(:option_test)) == 50
      Supervisor.stop(:option_test)
    end

    test "raises an exception when the name is not an atom" do
      e = assert_raise ArgumentError, fn -> OddJob.start_link(name: "Will raise") end
      assert String.contains?(e.message, "Expected `name` to be an atom.")
    end
  end

  describe "perform/2" do
    test "can perform concurrent fire and forget jobs" do
      parent = self()
      :ok = perform(@pool, fn -> Process.send_after(parent, :hello, 10) end)

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
      start_stash(fn -> [] end)
      perform_expensive_jobs(1..10)
      Process.sleep(9)
      assert get_stash() |> Enum.sort() == Enum.to_list(1..5)
      Process.sleep(10)
      assert get_stash() |> Enum.sort() == Enum.to_list(1..10)
      Process.sleep(10)
    end

    defp perform_expensive_jobs(range) do
      for i <- range do
        perform(@pool, fn ->
          update_stash(fn x -> x ++ [i] end)
          Process.sleep(10)
        end)
      end
    end

    test "can instantly start, assign, and monitor a new worker when one fails" do
      old_workers = OddJob.workers(@pool) |> Enum.sort()

      for i <- 1..20 do
        perform(@pool, fn ->
          if rem(i, 6) == 0 do
            Process.exit(self(), :kill)
          else
            Process.sleep(1)
          end
        end)
      end

      Process.sleep(25)
      new_workers = OddJob.workers(@pool) |> Enum.sort()
      assert new_workers != old_workers
      assert length(new_workers) == length(old_workers)
    end
  end

  describe "workers/1" do
    test "returns a list of worker pids" do
      workers = workers(@pool)
      assert length(workers) == 5

      for worker <- workers do
        assert is_pid(worker)
      end
    end
  end

  describe "pool_supervisor/1" do
    test "returns the pool supervisor's pid" do
      pid = pool_supervisor(@pool)
      {:ok, supervisor_name} = pool_supervisor_name(@pool)
      assert is_pid(pid)
      assert pid == GenServer.whereis(supervisor_name)
    end

    test "returns `not_found` message when the supervisor doesn't exist" do
      assert pool_supervisor(:not_found) == {:error, :not_found}
    end
  end
end
