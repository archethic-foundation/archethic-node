defmodule Uniris.Governance.GitTest do
  use ExUnit.Case

  alias Uniris.Governance.Git

  alias Uniris.Transaction
  alias Uniris.TransactionData

  @tag infrastructure: true
  test "remove_branch/1 should return :ok when the branch is deleted" do
    {_, 0} = System.cmd("git", ["checkout", "-b", "fake_branch"])
    {_, 0} = System.cmd("git", ["checkout", "master"])
    assert :ok = Git.remove_branch("fake_branch")
  end

  @tag infrastructure: true
  test "new_branch/1 should return :ok when the branch is created" do
    assert :ok = Git.new_branch("fake_branch")
    {_, 0} = System.cmd("git", ["checkout", "master"])
    {_, 0} = System.cmd("git", ["branch", "-D", "fake_branch"])
  end

  @tag infrastructure: true
  test "apply_patch/1 should return :ok when the patch is applied to the branch" do
    {_, 0} = System.cmd("git", ["checkout", "-b", "fake_branch"])

    patch = ~S"""
    diff --git a/lib/uniris/self_repair.ex b/lib/uniris/self_repair.ex
    index 124088f..c3add90 100755
    --- a/lib/uniris/self_repair.ex
    +++ b/lib/uniris/self_repair.ex
    @@ -91,7 +91,7 @@ defmodule Uniris.SelfRepair do
               node_patch: node_patch
             }
           ) do
    -    Logger.info("Self-repair synchronization started from #{inspect(last_sync_date)}")
    +    Logger.info("Self-repair synchronization started at #{inspect(last_sync_date)}")
         synchronize(last_sync_date, node_patch)
         schedule_sync(Utils.time_offset(interval))
         {:noreply, Map.put(state, :last_sync_date, update_last_sync_date())}

    """

    File.write!("fake.patch", patch)

    assert :ok = Git.apply_patch("fake.patch")

    {_, 0} = System.cmd("git", ["apply", "-R", "fake.patch"])
    File.rm!("fake.patch")
    {_, 0} = System.cmd("git", ["checkout", "master"])
    {_, 0} = System.cmd("git", ["branch", "-D", "fake_branch"])
  end

  @tag infrastructure: true
  test "revert_patch/1 should return :ok when the patch applied is reverted" do
    {_, 0} = System.cmd("git", ["checkout", "-b", "fake_branch"])

    patch = ~S"""
    diff --git a/lib/uniris/self_repair.ex b/lib/uniris/self_repair.ex
    index 124088f..c3add90 100755
    --- a/lib/uniris/self_repair.ex
    +++ b/lib/uniris/self_repair.ex
    @@ -91,7 +91,7 @@ defmodule Uniris.SelfRepair do
               node_patch: node_patch
             }
           ) do
    -    Logger.info("Self-repair synchronization started from #{inspect(last_sync_date)}")
    +    Logger.info("Self-repair synchronization started at #{inspect(last_sync_date)}")
         synchronize(last_sync_date, node_patch)
         schedule_sync(Utils.time_offset(interval))
         {:noreply, Map.put(state, :last_sync_date, update_last_sync_date())}

    """

    File.write!("fake.patch", patch)

    assert :ok = Git.apply_patch("fake.patch")
    assert :ok = Git.revert_patch("fake.patch")

    File.rm!("fake.patch")
    {_, 0} = System.cmd("git", ["checkout", "master"])
    {_, 0} = System.cmd("git", ["branch", "-D", "fake_branch"])
  end

  @tag infrastructure: true
  test "add_files/1 should return :ok when the patch applied is reverted" do
    {_, 0} = System.cmd("git", ["checkout", "-b", "fake_branch"])
    {_, 0} = System.cmd("touch", ["fake.txt"])

    Git.add_files(["fake.txt"])

    {_, 0} = System.cmd("git", ["reset", "fake.txt"])
    {_, 0} = System.cmd("rm", ["fake.txt"])
    {_, 0} = System.cmd("git", ["checkout", "master"])
    {_, 0} = System.cmd("git", ["branch", "-D", "fake_branch"])
  end

  @tag infrastructure: true
  test "commit_changes/1 should return :ok when changes are committed" do
    {_, 0} = System.cmd("git", ["checkout", "-b", "fake_branch"])
    {_, 0} = System.cmd("touch", ["fake.txt"])
    {_, 0} = System.cmd("git", ["add", "fake.txt"])

    assert :ok = Git.commit_changes("Add fake.txt")
    {_, 0} = System.cmd("git", ["checkout", "master"])
    {_, 0} = System.cmd("git", ["branch", "-D", "fake_branch"])
  end

  @tag infrastructure: true
  test "fork_proposal/1 should fork the proposal changes and apply the changes" do
    changes = ~S"""
    diff --git a/lib/uniris/self_repair.ex b/lib/uniris/self_repair.ex
    index 124088f..c3add90 100755
    --- a/lib/uniris/self_repair.ex
    +++ b/lib/uniris/self_repair.ex
    @@ -91,7 +91,7 @@ defmodule Uniris.SelfRepair do
               node_patch: node_patch
             }
           ) do
    -    Logger.info("Self-repair synchronization started from #{inspect(last_sync_date)}")
    +    Logger.info("Self-repair synchronization started at #{inspect(last_sync_date)}")
         synchronize(last_sync_date, node_patch)
         schedule_sync(Utils.time_offset(interval))
         {:noreply, Map.put(state, :last_sync_date, update_last_sync_date())}

    """

    tx = %Transaction{
      address: "@CodeChanges1",
      type: :code_proposal,
      timestamp: DateTime.utc_now(),
      data: %TransactionData{
        content: """
        Description: My new change
        Changes:
        #{changes}
        """
      }
    }

    assert :ok = Git.fork_proposal(tx)
    assert :ok = Git.clean(tx.address)
  end
end
