defmodule MacrosTest do
  use ExUnit.Case, async: false
  import OddJob

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

    test "can receive a keyword list instead of a do block" do
      job = perform_this(:work, :async, do: :finally)
      :do_something_else
      result = await(job)
      assert result == :finally
    end
  end

  describe "perform_this/3 at" do
    test "performs a job at the desired time" do
      caller = self()
      time = DateTime.add(DateTime.utc_now(), 10, :millisecond)

      perform_this :work, at: time do
        send(caller, DateTime.utc_now())
      end

      result =
        receive do
          x -> x
        end

      assert DateTime.diff(result, time) <= 1
    end

    test "can receive a keyword list instead of a do block" do
      caller = self()
      time = DateTime.add(DateTime.utc_now(), 10, :millisecond)

      perform_this(:work, at: time, do: send(caller, DateTime.utc_now()))

      result =
        receive do
          x -> x
        end

      assert DateTime.diff(result, time) <= 1
    end
  end

  describe "perform_this/3 after" do
    test "performs a job after the timer has elapsed" do
      caller = self()
      time = Time.add(Time.utc_now(), 10, :millisecond)

      perform_this :work, after: 10 do
        send(caller, Time.utc_now())
      end

      result =
        receive do
          x -> x
        end

      assert Time.diff(result, time) <= 1
    end

    test "can receive a keyword list instead of a do block" do
      caller = self()
      time = Time.add(Time.utc_now(), 10, :millisecond)

      perform_this(:work, after: 10, do: send(caller, Time.utc_now()))

      result =
        receive do
          x -> x
        end

      assert Time.diff(result, time) <= 1
    end
  end
end
