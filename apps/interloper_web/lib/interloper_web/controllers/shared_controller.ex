defmodule InterloperWeb.SharedController do
  use InterloperWeb, :controller

  # Custom error page for external service loading errors
  def render_loading_error(conn, reason, opts \\ []) do
    reason_str = get_reason_str(reason)
    loading =
      case Keyword.get(opts, :loading) do
        nil -> conn.request_path
        val -> val
      end
    conn
    |> put_view(InterloperWeb.SharedView)
    |> render("loading_error.html", reason: reason_str, loading: loading)
  end

  ## Private/internal

  defp get_reason_str(reason) when is_map(reason) do
    case Jason.encode(reason) do
      {:ok, reason_str} -> reason_str
      {:error, _reason} -> "Encoding error while parsing error message"
    end
  end
end
