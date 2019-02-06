defmodule InterloperWeb.SharedController do
  use InterloperWeb, :controller

  # Custom error page for external service loading errors
  def loading_error(conn, %{reason: reason} = params) do
    loading =
      case params[:loading] do
        nil -> conn.request_path
        val -> val
      end
    conn =
      case params[:put_view] do
        false -> conn
        nil -> put_view(conn, InterloperWeb.SharedView)
        module when is_atom(module) -> put_view(conn, module)
        other -> raise ArgumentError, "Invalid loading error view: #{inspect(other)}"
      end
    render(conn, "loading_error.html", reason: reason, loading: loading)
  end
end
