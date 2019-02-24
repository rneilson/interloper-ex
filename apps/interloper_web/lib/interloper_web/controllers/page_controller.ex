defmodule InterloperWeb.PageController do
  use InterloperWeb, :controller

  def index(conn, _params) do
    render(conn, "index.html")
  end

  def games(conn, _params) do
    render(conn, "games.html")
  end

  def rampant(conn, _params) do
    put_layout(conn, false)
    |> render("rampant.html")
  end
end
