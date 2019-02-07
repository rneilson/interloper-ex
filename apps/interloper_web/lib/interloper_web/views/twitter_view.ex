defmodule InterloperWeb.TwitterView do
  use InterloperWeb, :view

  alias InterloperWeb.SharedView

  def render("recent.json", %{recent: recent}) do
    # These are all the returned fields, but /shrug
    %{
      as_of: recent["as_of"],
      user: recent["user"],
      others: recent["others"],
      tweets: recent["tweets"],
    }
  end
end
