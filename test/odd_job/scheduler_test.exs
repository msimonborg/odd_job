defmodule OddJob.SchedulerTest do
  use ExUnit.Case, async: false

  alias OddJob.{Scheduler, Utils}

  import OddJob,
    only: [
      perform_at: 3,
      perform_after: 3,
      perform_many_at: 4,
      perform_many_after: 4,
      cancel_timer: 1
    ]

  @pool :scheduler_test

  describe "perform_after/3" do
    test "starts a job after the specified time" do
      caller = self()
      timer_ref = perform_after(25, @pool, fn -> send(caller, :finished) end)
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
      assert diff >= 20 and diff <= 30
    end

    test "timed jobs can be canceled" do
      caller = self()
      timer_ref = perform_after(25, @pool, fn -> send(caller, :delivered) end)
      remaining = cancel_timer(timer_ref)
      assert remaining > 0 and remaining <= 25

      result =
        receive do
          msg -> msg
        after
          30 -> :not_delivered
        end

      assert result == :not_delivered
    end
  end

  describe "perform_many_after/4" do
    test "starts a batch of jobs after the specified time" do
      caller = self()
      timer_ref = perform_many_after(25, @pool, 1..5, fn i -> send(caller, i) end)
      t1 = Time.utc_now()
      remaining = Process.read_timer(timer_ref)
      assert remaining > 0 and remaining <= 25

      results =
        for i <- 1..5 do
          receive do
            ^i -> i
          end
        end

      assert Process.read_timer(timer_ref) == false
      t2 = Time.utc_now()
      diff = Time.diff(t2, t1, :millisecond)

      assert results == Enum.to_list(1..5)
      assert diff >= 20 and diff <= 30
    end

    test "timed jobs can be canceled" do
      caller = self()
      timer_ref = perform_many_after(25, @pool, 1..5, fn i -> send(caller, i) end)
      remaining = cancel_timer(timer_ref)
      assert remaining > 0 and remaining <= 25
      Process.sleep(remaining)

      results =
        for i <- 1..5 do
          receive do
            ^i -> i
          after
            1 ->
              :not_delivered
          end
        end

      assert results == Enum.map(1..5, fn _ -> :not_delivered end)
    end
  end

  describe "perform_at/3" do
    test "schedules a job at the specified time" do
      caller = self()
      t1 = DateTime.add(DateTime.utc_now(), 25, :millisecond)
      timer_ref = perform_at(t1, @pool, fn -> send(caller, :finished) end)
      assert Process.read_timer(timer_ref) <= 25

      results =
        receive do
          msg -> msg
        end

      t2 = DateTime.utc_now()
      assert Process.read_timer(timer_ref) == false
      assert DateTime.diff(t2, t1, :millisecond) <= 2
      assert results == :finished
    end

    test "can receive a DateTime as a parameter" do
      datetime = DateTime.add(DateTime.utc_now(), 1_000_000_000, :millisecond)
      timer_ref = perform_at(datetime, @pool, fn -> :future end)
      timer = Process.read_timer(timer_ref)
      assert timer <= 1_000_000_000
      assert timer >= 999_999_950
      cancel_timer(timer_ref)
    end

    test "scheduled jobs can be canceled" do
      caller = self()
      time = DateTime.add(DateTime.utc_now(), 25, :millisecond)
      timer_ref = perform_at(time, @pool, fn -> send(caller, :delivered) end)
      cancel_timer(timer_ref)

      result =
        receive do
          msg -> msg
        after
          50 -> :not_delivered
        end

      assert result == :not_delivered
    end

    test "raises an ArgumentError when a DateTime in the past is given" do
      now = DateTime.utc_now()
      Process.sleep(1)
      e = assert_raise(ArgumentError, fn -> perform_at(now, @pool, fn -> :fails end) end)
      assert String.contains?(e.message, "invalid DateTime:")
    end
  end

  describe "perform_many_at/4" do
    test "schedules a batch of jobs at the specified time" do
      caller = self()
      t1 = DateTime.add(DateTime.utc_now(), 25, :millisecond)
      timer_ref = perform_many_at(t1, @pool, 1..5, fn i -> send(caller, i) end)
      assert Process.read_timer(timer_ref) <= 25

      results =
        for i <- 1..5 do
          receive do
            ^i -> i
          end
        end

      t2 = DateTime.utc_now()
      assert Process.read_timer(timer_ref) == false
      assert DateTime.diff(t2, t1, :millisecond) <= 2
      assert results == Enum.to_list(1..5)
    end

    test "can receive a DateTime as a parameter" do
      datetime = DateTime.add(DateTime.utc_now(), 1_000_000_000, :millisecond)
      timer_ref = perform_many_at(datetime, @pool, 1..5, fn i -> i end)
      timer = Process.read_timer(timer_ref)
      assert timer <= 1_000_000_000
      assert timer >= 999_999_950
      cancel_timer(timer_ref)
    end

    test "scheduled jobs can be canceled" do
      caller = self()
      time = DateTime.add(DateTime.utc_now(), 25, :millisecond)
      timer_ref = perform_many_at(time, @pool, 1..5, fn i -> send(caller, i) end)
      remaining = cancel_timer(timer_ref)
      assert remaining > 0 and remaining <= 25
      Process.sleep(remaining)

      results =
        for i <- 1..5 do
          receive do
            ^i -> i
          after
            1 ->
              :not_delivered
          end
        end

      assert results == Enum.map(1..5, fn _ -> :not_delivered end)
    end

    test "raises an ArgumentError when a DateTime in the past is given" do
      now = DateTime.utc_now()
      Process.sleep(1)

      e =
        assert_raise(ArgumentError, fn ->
          perform_many_at(now, @pool, 1..5, fn _ -> :fails end)
        end)

      assert String.contains?(e.message, "invalid DateTime:")
    end
  end

  describe "timeout" do
    test "shuts down the scheduler when the timer expires" do
      scheduler_sup = Utils.scheduler_sup_name(@pool)
      timer_ref = perform_after(10, @pool, fn -> :canceled end)
      [{:undefined, pid, :worker, [Scheduler]}] = Supervisor.which_children(scheduler_sup)
      remaining = Process.cancel_timer(timer_ref)
      assert remaining >= 0 and remaining <= 10
      Process.sleep(remaining + 10)
      assert Supervisor.which_children(scheduler_sup) == []
      assert Process.alive?(pid) == false
    end
  end
end
