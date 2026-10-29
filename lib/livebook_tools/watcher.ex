defmodule LivebookTools.Watcher do
  use GenServer
  require Logger

  # Check every 100ms
  @check_interval 100

  # A change is synced only once the file stays the same for this long.
  # After a sync, Livebook autosaves the notebook as it read it, so a
  # write landing in between (e.g. an agent's next edit) is overwritten
  # and lost. Agents tend to edit in quick bursts, so waiting for the
  # burst to finish avoids syncing in the middle of it.
  @settle_time 500

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
       last_info: initial_info,
       pending: nil
     }}
  end

  def handle_info(:check_file, state) do
    %{file_path: file_path, callback: callback, last_info: last_info, pending: pending} = state

    current_info = get_file_info(file_path)
    now = System.monotonic_time(:millisecond)

    state =
      cond do
        # Keep the last known content while the file is missing or empty
        # (e.g. mid-write), so the next complete write is detected
        current_info == nil ->
          state

        current_info == last_info ->
          %{state | pending: nil}

        match?({^current_info, _}, pending) and now - elem(pending, 1) >= @settle_time ->
          try do
            callback.(file_path)
          rescue
            error -> Logger.error(Exception.format(:error, error, __STACKTRACE__))
          end

          %{state | last_info: current_info, pending: nil}

        match?({^current_info, _}, pending) ->
          state

        true ->
          %{state | pending: {current_info, now}}
      end

    # Schedule the next check
    schedule_check()

    {:noreply, state}
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

  defp schedule_check do
    Process.send_after(self(), :check_file, @check_interval)
  end
end
