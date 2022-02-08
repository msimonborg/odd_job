defmodule OddJob.Utils do
  @moduledoc false
  @moduledoc since: "0.4.0"

  import OddJob.Registry, only: [via: 2]
  @type name :: OddJob.Registry.name()

  @spec link_and_monitor(pid) :: {pid, reference}
  def link_and_monitor(pid) do
    Process.link(pid)
    {pid, Process.monitor(pid)}
  end

  @spec extract_pid({:ok, pid}) :: pid
  def extract_pid({:ok, pid}), do: pid

  @spec supervisor_name(atom) :: name
  def supervisor_name(name), do: via(name, "sup")

  @spec scheduler_sup_name(atom) :: name
  def scheduler_sup_name(name), do: via(name, "scheduler_sup")

  @spec pool_name(atom) :: name
  def pool_name(name), do: via(name, "pool")

  @spec pool_supervisor_name(atom) :: name
  def pool_supervisor_name(name), do: via(name, "pool_sup")

  @spec proxy_sup_name(atom) :: name
  def proxy_sup_name(name), do: via(name, "proxy_sup")
end
