defmodule LivebookTools.Watcher do
  use GenServer
  require Logger

  # Check every 100ms
  @check_interval 100

  def start_link(file_path, callback) do
    GenServer.start_link(__MODULE__, {file_path, callback})
  end

  def init({file_path, callback}) do
    # Get initial file info
    initial_info = get_file_info(file_path)

    # Schedule the first check
    schedule_check()

    {:ok,
     %{
       file_path: file_path,
       callback: callback,
       last_info: initial_info
     }}
  end

  def handle_info(:check_file, state) do
    %{file_path: file_path, callback: callback, last_info: last_info} = state

    current_info = get_file_info(file_path)

    # If the file has changed, call the callback
    if file_changed?(last_info, current_info) do
      try do
        callback.(file_path)
      rescue
        error -> Logger.error(Exception.format(:error, error, __STACKTRACE__))
      end
    end

    # Schedule the next check
    schedule_check()

    # Keep the last known content while the file is missing or empty
    # (e.g. mid-write), so the next complete write is detected
    {:noreply, %{state | last_info: current_info || last_info}}
  end

  # mtime has a one second resolution, so two writes of the same size
  # within one second would go unnoticed. Hashing the content is cheap
  # for notebook-sized files and catches every change.
  defp get_file_info(file_path) do
    case File.read(file_path) do
      {:ok, ""} -> nil
      {:ok, content} -> :erlang.md5(content)
      {:error, _reason} -> nil
    end
  end

  defp file_changed?(_last_info, nil), do: false
  defp file_changed?(last_info, current_info), do: last_info != current_info

  defp schedule_check do
    Process.send_after(self(), :check_file, @check_interval)
  end
end
