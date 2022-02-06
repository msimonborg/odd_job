defmodule OddJob.Utils do
  @moduledoc false
  @moduledoc since: "0.4.0"

  @spec link_and_monitor(pid) :: {pid, reference}
  def link_and_monitor(pid) do
    Process.link(pid)
    {pid, Process.monitor(pid)}
  end

  @spec extract_pid({:ok, pid}) :: pid
  def extract_pid({:ok, pid}), do: pid
end
