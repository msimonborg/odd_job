defmodule OddJob.AsyncTest do
  use ExUnit.Case, async: false

  import OddJob,
    only: [
      async_perform: 2,
      async_perform_many: 3,
      await: 1,
      await: 2,
      await_many: 1,
      await_many: 2
    ]

  @pool :async_test

  describe "async_perform/2" do
    test "returns a Job struct with appropriate fields" do
      job = async_perform(@pool, fn -> 1 + 1 end)

      %OddJob.Job{
        async: async,
        owner: owner,
        proxy: proxy,
        function: function,
        ref: ref,
        results: nil
      } = job

      assert is_function(function)
      assert async == true
      assert owner == self()
      assert proxy != self()
      assert is_pid(proxy)
      assert is_reference(ref)
      await(job)
    end

    test "does not block the caller" do
      t1 = Time.utc_now()

      job =
        async_perform(@pool, fn ->
          Process.sleep(10)
          Time.utc_now()
        end)

      t2 = Time.utc_now()
      assert Time.diff(t2, t1, :millisecond) < 10
      t3 = await(job)
      assert Time.diff(t3, t1, :millisecond) >= 10
    end
  end

  describe "await/2" do
    test "awaits on and returns the results of an async job" do
      job = async_perform(@pool, fn -> 1 + 1 end)
      assert await(job) == 2
    end

    test "accepts an optional timeout that will exit if the job takes too long" do
      job = async_perform(@pool, fn -> Process.sleep(5) end)
      message = catch_exit(await(job, 2))
      assert {reason, fun, owner, proxy, ref, timeout} = match_exit_message(message)
      assert reason == :timeout
      assert fun == job.function
      assert owner == job.owner
      assert proxy == job.proxy
      assert ref == job.ref
      assert timeout == 2
      Process.sleep(3)
    end

    test "will timeout waiting for jobs that have already been awaited on" do
      job = async_perform(@pool, fn -> 1 + 1 end)
      assert await(job) == 2
      message = catch_exit(await(job, 2))
      assert {reason, fun, owner, proxy, ref, timeout} = match_exit_message(message)
      assert reason == :timeout
      assert fun == job.function
      assert owner == job.owner
      assert proxy == job.proxy
      assert ref == job.ref
      assert timeout == 2
    end

    test "when the job exits, the caller receives the same exit signal" do
      job = async_perform(@pool, fn -> exit(:normal) end)
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
      job = async_perform(@pool, fn -> 1 + 1 end)

      Task.start(fn ->
        assert_raise(ArgumentError, fn -> await(job) end)
      end)

      await(job)
    end
  end

  describe "async_perform_many/3 and await_many/2" do
    test "awaits on multiple async jobs and returns their results" do
      range = 0..20
      jobs = async_perform_many(@pool, range, fn i -> i end)
      result = await_many(jobs)
      assert result == Enum.to_list(range)
    end

    test "accepts an optional timeout that will exit if the jobs take too long" do
      jobs = async_perform_many(@pool, 1..5, fn _ -> Process.sleep(5) end)
      message = catch_exit(await_many(jobs, 2))
      assert {:timeout, {OddJob.Async, :await_many, [^jobs, 2]}} = message
      assert await_many(jobs) == Enum.map(1..5, fn _ -> :ok end)
    end

    test "will timeout waiting for jobs that have already been waited on" do
      range = 1..20
      jobs = async_perform_many(@pool, range, fn i -> i end)
      result = await_many(jobs)
      assert result == Enum.to_list(range)
      message = catch_exit(await_many(jobs, 5))
      assert {:timeout, {OddJob.Async, :await_many, [^jobs, 5]}} = message
    end

    test "exits if one of the awaited jobs sends an exit signal" do
      jobs = async_perform_many(@pool, 1..5, fn _ -> :sucess end)
      jobs_with_exit = jobs ++ [async_perform(@pool, fn -> exit(:normal) end)]
      message = catch_exit(await_many(jobs_with_exit))
      assert {:normal, {OddJob.Async, :await_many, [^jobs_with_exit, 5000]}} = message

      # Sleep to wait for clean up
      Process.sleep(5)
    end

    test "raises an ArgumentError if any of the jobs are awaited on by a process that's not the caller" do
      job = async_perform(@pool, fn -> 1 + 1 end)

      Task.start(fn ->
        jobs = async_perform_many(@pool, 2..5, fn x -> x + x end) ++ [job]
        assert_raise(ArgumentError, fn -> await_many(jobs) end)
      end)

      await(job)
    end

    test "can perform a massive number of async jobs" do
      {:ok, pid} = OddJob.start_link(name: :massive_job, pool_size: System.schedulers_online())

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
