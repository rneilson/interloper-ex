defmodule InterloperWeb.ErrorView do
  use InterloperWeb, :view

  alias InterloperWeb.SharedView

  def render("404.html", assigns) do
    render("err_page.html", put_error_status(assigns, 404))
  end

  def render("500.html", assigns) do
    render("err_page.html", put_error_status(assigns, 500))
  end

  # By default, Phoenix returns the status message from
  # the template name. For example, "404.html" becomes
  # "Not Found".
  def template_not_found(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end

  ## Internal

  # Helper to add status code/text to assigns
  defp put_error_status(assigns, status_code) do
    assigns
    |> Map.put_new(:status_code, status_code)
    |> Map.put_new(:status_text, Plug.Conn.Status.reason_phrase(status_code))
  end
end
