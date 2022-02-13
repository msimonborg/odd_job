defmodule OddJob.WorkerTest do
  use ExUnit.Case

  @pool :worker_test

  test "workers can survive a queue restart and check-in to the new queue" do
    pid = OddJob.queue_name(@pool) |> GenServer.whereis()
    assert is_pid(pid)
    assert {^pid, %{workers: workers}} = OddJob.queue(@pool)
    Process.exit(pid, :shutdown)
    Process.sleep(1)
    {new_pid, %{workers: new_workers}} = OddJob.queue(@pool)
    assert is_pid(new_pid)
    assert pid != new_pid
    assert Enum.sort(workers) == Enum.sort(new_workers)
  end
end
