defmodule OddJob.WorkerTest do
  use ExUnit.Case

  test "workers can survive a pool restart and check-in to the new pool" do
    pid = OddJob.pool_name(:work) |> GenServer.whereis()
    assert is_pid(pid)
    assert {^pid, %{workers: workers}} = OddJob.pool(:work)
    Process.exit(pid, :shutdown)
    Process.sleep(1)
    {new_pid, %{workers: new_workers}} = OddJob.pool(:work)
    assert is_pid(new_pid)
    assert pid != new_pid
    assert Enum.sort(workers) == Enum.sort(new_workers)
  end
end
