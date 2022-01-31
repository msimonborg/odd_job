defmodule OddJobTest do
  use ExUnit.Case, async: false
  use ExUnitReceiver, as: :stash
  import OddJob
  doctest OddJob

  setup do
    start_stash(fn -> [] end)
    # sleep to make sure all jobs from previous test are finished
    on_exit(fn -> Process.sleep(25) end)
    :ok
  end

  describe "async_perform/2" do
    test "returns a Job struct with appropriate fields" do
      %OddJob.Job{
        async: async,
        owner: owner,
        proxy: proxy,
        function: function,
        ref: ref,
        results: nil
      } = async_perform(:work, fn -> 1 + 1 end)

      assert is_function(function)
      assert async == true
      assert owner == self()
      assert proxy != self()
      assert is_pid(proxy)
      assert is_reference(ref)
    end

    test "does not block the caller" do
      t1 = Time.utc_now()

      job =
        async_perform(:work, fn ->
          Process.sleep(10)
          :finished
        end)

      t2 = Time.utc_now()
      assert Time.diff(t2, t1, :millisecond) < 10
      assert await(job) == :finished
    end
  end

  describe "await/2" do
    test "awaits on and returns the results of an async job" do
      job = async_perform(:work, fn -> 1 + 1 end)
      assert await(job) == 2
    end

    test "accepts an optional timeout that will exit if the job takes too long" do
      job = async_perform(:work, fn -> Process.sleep(10) end)
      message = catch_exit(await(job, 5))
      assert {reason, fun, owner, proxy, ref, timeout} = match_exit_message(message)
      assert reason == :timeout
      assert fun == job.function
      assert owner == job.owner
      assert proxy == job.proxy
      assert ref == job.ref
      assert timeout == 5
      Process.sleep(5)
    end

    test "will timeout waiting for jobs that have already been awaited on" do
      job = async_perform(:work, fn -> 1 + 1 end)
      assert await(job, 5) == 2
      message = catch_exit(await(job, 5))
      assert {reason, fun, owner, proxy, ref, timeout} = match_exit_message(message)
      assert reason == :timeout
      assert fun == job.function
      assert owner == job.owner
      assert proxy == job.proxy
      assert ref == job.ref
      assert timeout == 5
    end

    test "when the job exits, the caller receives the same exit signal" do
      job = async_perform(:work, fn -> exit(:normal) end)
      message = catch_exit(await(job))
      assert {reason, fun, owner, proxy, ref, timeout} = match_exit_message(message)
      assert reason == :normal
      assert fun == job.function
      assert owner == job.owner
      assert proxy == job.proxy
      assert ref == job.ref
      assert timeout == 5000
    end
  end

  describe "perform/2" do
    test "can perform concurrent fire and forget jobs" do
      parent = self()
      :ok = perform(:work, fn -> Process.send_after(parent, :hello, 10) end)

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
      perform(:work, fn -> Process.exit(self(), :kill) end)
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

  describe "perform_after/3" do
    test "starts a job after the specified time" do
      caller = self()
      timer_ref = perform_after(50, :work, fn -> send(caller, :finished) end)
      t1 = Time.utc_now()
      assert Process.read_timer(timer_ref) > 0

      result =
        receive do
          msg -> msg
        end

      assert Process.read_timer(timer_ref) == false
      t2 = Time.utc_now()
      diff = Time.diff(t2, t1, :millisecond)

      assert result == :finished
      assert diff >= 49
      assert diff <= 51
    end

    test "timed jobs can be canceled" do
      caller = self()
      timer_ref = perform_after(25, :work, fn -> send(caller, :delivered) end)
      Process.cancel_timer(timer_ref)

      result =
        receive do
          msg -> msg
        after
          50 -> :not_delivered
        end

      assert result == :not_delivered
    end
  end

  describe "perform_at/3" do
    test "schedules a job at the specified time" do
      caller = self()
      t1 = Time.add(Time.utc_now(), 100, :millisecond)
      timer_ref = perform_at(t1, :work, fn -> send(caller, :finished) end)
      assert Process.read_timer(timer_ref) <= 100

      results =
        receive do
          msg -> msg
        end

      t2 = Time.utc_now()
      assert Process.read_timer(timer_ref) == false
      assert Time.diff(t2, t1, :millisecond) <= 1
      assert results == :finished
    end

    test "can receive a DateTime as a parameter" do
      datetime = DateTime.add(DateTime.utc_now(), 1_000_000_000, :millisecond)
      timer_ref = perform_at(datetime, :work, fn -> :future end)
      timer = Process.read_timer(timer_ref)
      assert timer <= 1_000_000_000
      assert timer >= 999_999_990
      Process.cancel_timer(timer_ref)
    end

    test "scheduled jobs can be canceled" do
      caller = self()
      time = Time.add(Time.utc_now(), 25, :millisecond)
      timer_ref = perform_at(time, :work, fn -> send(caller, :delivered) end)
      Process.cancel_timer(timer_ref)

      result =
        receive do
          msg -> msg
        after
          50 -> :not_delivered
        end

      assert result == :not_delivered
    end
  end

  describe "workers/1" do
    test "returns a list of worker pids" do
      workers = workers(:work)
      assert length(workers) == 5

      for worker <- workers do
        assert is_pid(worker)
      end
    end
  end

  describe "supervisor/1" do
    test "returns the pool supervisor's pid" do
      pid = supervisor(:work)
      supervisor_id = supervisor_id(:work)
      assert is_pid(pid)
      assert pid == GenServer.whereis(supervisor_id)
    end
  end

  defp perform_expensive_jobs(range) do
    for i <- range do
      perform(:work, fn ->
        update_stash(fn x -> x ++ [i] end)
        Process.sleep(10)
      end)
    end
  end

  defp match_exit_message(msg) do
    {reason,
     {OddJob.Async, :await,
      [
        %OddJob.Job{
          async: true,
          function: fun,
          owner: owner,
          proxy: proxy,
          ref: ref,
          results: nil
        },
        timeout
      ]}} = msg

    {reason, fun, owner, proxy, ref, timeout}
  end
end
