defmodule LivebookTools.WatcherTest do
  use ExUnit.Case, async: true

  @moduletag :tmp_dir

  test "syncs a burst of writes once, after the file settles", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "notebook.livemd")
    File.write!(path, "v0")
    test_pid = self()

    {:ok, _pid} =
      LivebookTools.Watcher.start_link(path, fn path ->
        send(test_pid, {:synced, File.read!(path)})
      end)

    # Writes closer together than the settle time, like an agent making
    # several edits in a row. Syncing in between lets Livebook's
    # post-sync autosave overwrite the later writes.
    for content <- ["v1", "v2", "v3"] do
      File.write!(path, content)
      Process.sleep(150)
    end

    assert_receive {:synced, "v3"}, 2_000
    refute_received {:synced, _}
  end

  test "ignores a change that is reverted before it settles", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "notebook.livemd")
    File.write!(path, "v0")
    test_pid = self()

    {:ok, _pid} =
      LivebookTools.Watcher.start_link(path, fn path ->
        send(test_pid, {:synced, File.read!(path)})
      end)

    File.write!(path, "v1")
    Process.sleep(150)
    File.write!(path, "v0")

    refute_receive {:synced, _}, 1_500
  end
end
