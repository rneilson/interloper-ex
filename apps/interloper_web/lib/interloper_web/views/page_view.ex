defmodule InterloperWeb.PageView do
  use InterloperWeb, :view

  def get_version do
      Application.spec(:interloper_web, :vsn)
  end
end
