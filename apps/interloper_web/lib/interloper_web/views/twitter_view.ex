defmodule InterloperWeb.TwitterView do
  use InterloperWeb, :view

  alias InterloperWeb.SharedView

  @link_attrs [class: "blue selector", target: "_blank"]

  ## HTML

  # TODO: use a file template instead?
  def render("user_link.html", %{user: user}) do
    screen_name = user["screen_name"] || ""
    attrs = [href: "https://twitter.com/" <> screen_name, data: [user_id_str: user[:id_str]]]
    content_tag(:a, "@" <> screen_name, attrs ++ @link_attrs)
  end

  # TODO: use a file template instead?
  def render("entity_link.html", %{url: url, entities: _entities}) do
    # TODO: extract display url text
    text = url
    # TODO: extract actual url href
    attrs = [href: url]
    content_tag(:a, text, attrs ++ @link_attrs)
  end

  def render("tweet_text.html", %{text: text, entities: entities}) when is_list(entities) do
    # TODO: fancy parsing
    text
  end

  def render("tweet_text.html", %{text: text} = context) do
    case Map.get(context, :entities) do
      entities when is_map(entities) ->
        render("tweet_text.html", %{text: text, entities: entity_list(entities)})
      _ ->
        text
    end
  end

  ## JSON

  def render("recent.json", %{recent: recent}) do
    # These are all the returned fields, but /shrug
    %{
      as_of: recent["as_of"],
      user: recent["user"],
      others: recent["others"],
      tweets: recent["tweets"],
    }
  end


  ## Internal/private

  defp entity_list(entity_map) do
    # TODO: extract indicies
    Enum.flat_map(entity_map, fn {_, entities} -> entities end)
  end
end
