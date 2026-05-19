defmodule LivebookTools.EPMD do
  defdelegate start_link(), to: :erl_epmd
  defdelegate stop(), to: :erl_epmd
  defdelegate names(host), to: :erl_epmd
  defdelegate register_node(name, port), to: :erl_epmd
  defdelegate register_node(name, port, family), to: :erl_epmd
  defdelegate address_please(name, host, family), to: :erl_epmd
  defdelegate listen_port_please(name, host), to: :erl_epmd

  def port_please(name, host), do: port_please(name, host, :infinity)

  def port_please(name, host, timeout) do
    case :erl_epmd.port_please(name, host, timeout) do
      :noport ->
        case find_livebook_dist_port() do
          {:ok, port} -> {:port, port, 6}
          :error -> :noport
        end

      result ->
        result
    end
  end

  # Called by discover_livebook_node/0 when LIVEBOOK_NODE is not set.
  def find_livebook_node() do
    case parse_runtime_process() do
      {node, _port} -> {:ok, node}
      nil -> :error
    end
  end

  defp find_livebook_dist_port() do
    case parse_runtime_process() do
      {_node, port} -> {:ok, port}
      nil -> :error
    end
  end

  # Reads parent_node / parent_port from the base64-encoded startup script
  # that Livebook embeds in each runtime process's command-line args.
  defp parse_runtime_process() do
    case System.cmd("ps", ["aux"], stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.split("\n")
        |> Enum.find_value(fn line ->
          if String.contains?(line, "Livebook.Runtime.EPMD") do
            b64 = line |> String.split() |> List.last()

            try do
              decoded = Base.decode64!(b64)

              with [_, node_str] <- Regex.run(~r/parent_node = :"([^"]+)"/, decoded),
                   [_, port_str] <- Regex.run(~r/parent_port = (\d+)/, decoded) do
                {:erlang.binary_to_atom(node_str, :utf8), String.to_integer(port_str)}
              end
            rescue
              _ -> nil
            end
          end
        end)

      _ ->
        nil
    end
  end
end
