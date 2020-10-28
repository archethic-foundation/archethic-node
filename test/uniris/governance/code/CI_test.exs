defmodule Uniris.Governance.Code.CITest do
  use ExUnit.Case

  alias Uniris.Governance.Code.CI
  alias Uniris.Governance.Code.Proposal

  @tag CI: true
  test "run/0 should return the first node boostrap" do
    diff = """
    diff --git a/LICENSE b/LICENSE
    index 0ad25db..095d836 100644
    --- a/LICENSE
    +++ b/LICENSE
    @@ -1,5 +1,5 @@
                         GNU AFFERO GENERAL PUBLIC LICENSE
    -                       Version 3, 19 November 2007
    +                       Version 3, 19 November 2012

      Copyright (C) 2007 Free Software Foundation, Inc. <https://fsf.org/>
      Everyone is permitted to copy and distribute verbatim copies
    """

    prop = %Proposal{
      address: "@CodeChanges1",
      timestamp: DateTime.utc_now(),
      description: "My new change",
      changes: diff
    }

    CI.run(prop)
  end
end
