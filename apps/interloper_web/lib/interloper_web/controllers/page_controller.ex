defmodule InterloperWeb.PageController do
  use InterloperWeb, :controller

  def index(conn, _params) do
    render(conn, "index.html")
  end
end
