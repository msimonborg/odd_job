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

  @spec to_snakecase(atom) :: atom
  def to_snakecase(name) do
    name
    |> Atom.to_string()
    |> String.split(~r{(?<=[\w])(?=[A-Z])})
    |> Enum.flat_map(&String.split(&1, "."))
    |> Enum.map_join("_", &String.downcase(&1))
    |> String.trim("elixir_")
    |> String.to_atom()
  end

  @spec supervisor_name(atom) :: atom
  def supervisor_name(name) do
    :"#{to_snakecase(name)}_sup"
  end

  @spec scheduler_sup_name(atom) :: atom
  def scheduler_sup_name(name) do
    :"#{to_snakecase(name)}_scheduler_sup"
  end

  @spec pool_name(atom) :: atom
  def pool_name(name) when is_atom(name) or is_binary(name) do
    :"#{to_snakecase(name)}_pool"
  end

  @spec pool_supervisor_name(atom) :: atom
  def pool_supervisor_name(name) when is_atom(name) do
    :"#{to_snakecase(name)}_pool_worker_sup"
  end

  @spec pool_worker_name(atom, integer) :: atom
  def pool_worker_name(name, num) when is_atom(name) do
    :"#{to_snakecase(name)}_pool_worker_#{num}"
  end

  @spec proxy_sup_name(atom) :: atom
  def proxy_sup_name(name) do
    :"#{to_snakecase(name)}_pool_proxy_sup"
  end
end
