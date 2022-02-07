defmodule OddJobTest do
  use ExUnit.Case, async: false
  use ExUnitReceiver, as: :stash
  import OddJob
  alias OddJob.Utils
  doctest OddJob

  setup do
    start_stash(fn -> [] end)
    # sleep to make sure all jobs from previous test are finished
    on_exit(fn -> Process.sleep(25) end)
    :ok
  end

  describe "child_spec/1" do
    test "returns a valid child spec for a pool supervision tree" do
      assert child_spec(:spec_test) == %{
               id: Utils.supervisor_name(:spec_test),
               start: {OddJob.Supervisor, :start_link, [:spec_test, []]},
               type: :supervisor
             }

      assert child_spec(name: :spec_test, pool_size: 10, max_restarts: 20) == %{
               id: Utils.supervisor_name(:spec_test),
               start:
                 {OddJob.Supervisor, :start_link, [:spec_test, [pool_size: 10, max_restarts: 20]]},
               type: :supervisor
             }
    end
  end

  describe "start_link/1" do
    test "dynamically starts an OddJob pool supervision tree" do
      {:ok, pid} = start_link(:start_link)
      assert pid == GenServer.whereis(Utils.supervisor_name(:start_link))
      caller = self()
      perform(:start_link, fn -> send(caller, "hello from start_link") end)

      greeting =
        receive do
          msg -> msg
        end

      assert greeting == "hello from start_link"
    end

    test "accepts options for config overrides" do
      {:ok, _} = start_link(:option_test, pool_size: 50)
      assert length(workers(:option_test)) == 50
    end
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
      # Sleep so the caller and proxy don't exit before the worker links and performs its job
      Process.sleep(10)
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

    test "raises an ArgumentError if the job is awaited on by a process that's not the caller" do
      job = async_perform(:work, fn -> 1 + 1 end)

      Task.start(fn ->
        assert_raise(ArgumentError, fn -> await(job) end)
      end)

      # Sleep so the caller and proxy don't exit before the worker links and performs its job
      Process.sleep(10)
    end
  end

  describe "async_perform_many/3 and await_many/2" do
    test "awaits on multiple async jobs and returns their results" do
      range = 0..20
      jobs = async_perform_many(:work, range, fn i -> i end)
      result = await_many(jobs)
      assert result == Enum.to_list(range)
    end

    test "accepts an optional timeout that will exit if the jobs take too long" do
      jobs = async_perform_many(:work, 1..5, fn _ -> Process.sleep(10) end)
      message = catch_exit(await_many(jobs, 5))
      assert {:timeout, {OddJob.Async, :await_many, [^jobs, 5]}} = message
      Process.sleep(10)
    end

    test "will timeout waiting for jobs that have already been waited on" do
      range = 1..20
      jobs = async_perform_many(:work, range, fn i -> i end)
      result = await_many(jobs)
      assert result == Enum.to_list(range)
      message = catch_exit(await_many(jobs, 10))
      assert {:timeout, {OddJob.Async, :await_many, [^jobs, 10]}} = message
    end

    test "exits if one of the awaited jobs sends an exit signal" do
      jobs = async_perform_many(:work, 1..5, fn _ -> :sucess end)
      jobs = jobs ++ [async_perform(:work, fn -> exit(:normal) end)]
      message = catch_exit(await_many(jobs))
      assert {:normal, {OddJob.Async, :await_many, [^jobs, 5000]}} = message
      Process.sleep(5)
    end

    test "raises an ArgumentError if any of the jobs are awaited on by a process that's not the caller" do
      job = async_perform(:work, fn -> 1 + 1 end)

      Task.start(fn ->
        jobs = async_perform_many(:job, 2..5, fn x -> x + x end) ++ [job]
        assert_raise(ArgumentError, fn -> await_many(jobs) end)
      end)

      # Sleep so the caller and proxy don't exit before the worker links and performs its job
      Process.sleep(10)
    end

    test "can perform a massive number of async jobs" do
      {:ok, pid} = OddJob.start_link(:massive_job, pool_size: 1000)

      result =
        :massive_job
        |> async_perform_many(1..100_000, fn x -> :math.log(x) end)
        |> await_many()

      assert length(result) == 100_000
      assert List.first(result) == 0.0
      assert List.last(result) == 11.512925464970229

      Supervisor.stop(pid)
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
      Process.sleep(9)
      assert get_stash() |> Enum.sort() == Enum.to_list(1..5)
      Process.sleep(10)
      assert get_stash() |> Enum.sort() == Enum.to_list(1..10)
      Process.sleep(10)
    end

    test "can instantly start, assign, and monitor a new worker when one fails" do
      perform_expensive_jobs(1..10)
      perform(:work, fn -> Process.exit(self(), :kill) end)
      perform_expensive_jobs(11..20)
      Process.sleep(9)
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
      assert diff >= 45
      assert diff <= 55
    end

    test "timed jobs can be canceled" do
      caller = self()
      timer_ref = perform_after(25, :work, fn -> send(caller, :delivered) end)
      OddJob.cancel_timer(timer_ref)

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
      assert Time.diff(t2, t1, :millisecond) <= 2
      assert results == :finished
    end

    test "can receive a DateTime as a parameter" do
      datetime = DateTime.add(DateTime.utc_now(), 1_000_000_000, :millisecond)
      timer_ref = perform_at(datetime, :work, fn -> :future end)
      timer = Process.read_timer(timer_ref)
      assert timer <= 1_000_000_000
      assert timer >= 999_999_950
      OddJob.cancel_timer(timer_ref)
    end

    test "scheduled jobs can be canceled" do
      caller = self()
      time = Time.add(Time.utc_now(), 25, :millisecond)
      timer_ref = perform_at(time, :work, fn -> send(caller, :delivered) end)
      OddJob.cancel_timer(timer_ref)

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

  describe "pool_supervisor/1" do
    test "returns the pool supervisor's pid" do
      pid = pool_supervisor(:work)
      supervisor_name = pool_supervisor_name(:work)
      assert is_pid(pid)
      assert pid == GenServer.whereis(supervisor_name)
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
     {OddJob.Async, _,
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
