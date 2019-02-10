defmodule InterloperWeb.TwitterView do
  use InterloperWeb, :view

  alias InterloperWeb.SharedView

  @link_attrs [class: "blue selector", target: "_blank"]

  ## HTML

  def render_tweets(tweets, users, user) do
    render_tweets(tweets, Map.put_new(users, user["id_str"], user))
  end

  def render_tweets(tweets, users) do
    # TODO: any reordering/reply refs/something else?
    Enum.map(tweets, &render_tweet(&1, users))
  end

  def render_tweet(tweet, users) do
    user = find_user(tweet, users)
    # Extract retweet
    assigns =
      case tweet["retweeted_status"] do
        nil ->
          %{tweet: tweet, user: user, retweeted: nil}
        retweet ->
          %{tweet: retweet, user: find_user(retweet, users), retweeted: user}
      end
    # Extract quote tweet
    quoted =
      case assigns[:tweet]["quoted_status"] do
        nil -> nil
        quote_tweet -> %{tweet: quote_tweet, user: find_user(quote_tweet, users), retweeted: nil}
      end
    render("tweet.html", Map.put(assigns, :quoted, quoted))
  end

  def render_tweet_text(tweet) when is_map(tweet) do
    # Extract text (ignore text start index, btw)
    text =
      case tweet["display_text_range"] do
        [_from_idx, to_idx] -> String.slice(tweet["text"], 0, to_idx)
        _ -> tweet["text"]
      end
    # Pre-extract entities
    # TODO: any bounds checking?
    entities = entity_list(tweet["entities"])
    # Forward
    render_tweet_text(text, entities)
  end

  def render_tweet_text(text) when is_binary(text) do
    # TODO: any other checking/normalization?
    break_lines(text)
  end

  def render_tweet_text(text, []) do
    render_tweet_text(text)
  end

  def render_tweet_text(text, nil) do
    render_tweet_text(text, [])
  end

  def render_tweet_text(text, entities) when is_list(entities) do
    max_len = String.length(text)
    {strings, final_idx} = Enum.flat_map_reduce(entities, 0, fn ent, idx ->
      case ent["indices"] do
        [from_idx, to_idx] when from_idx < max_len ->
          segment = String.slice(text, idx, from_idx - idx) |> break_lines()
          ent_html =
            cond do
              ent["screen_name"] -> render("user_link.html", %{user: ent})
              ent["url"] -> render("entity_link.html", %{url: ent["url"], entities: [ent]})
              ent["text"] -> ent["text"]
              true -> []
            end
          {[segment, ent_html], to_idx}
        _ ->
          {:halt, idx}
      end
    end)
    # Return last segment as well
    strings ++ [String.slice(text, final_idx, max_len - final_idx) |> break_lines()]
  end

  def render_tweet_text(text, entities) when is_map(entities) do
    render_tweet_text(text, entity_list(entities))
  end

  # TODO: use a file template instead?
  def render("user_link.html", %{user: user}) do
    screen_name = user["screen_name"] || ""
    attrs = [href: "https://twitter.com/" <> screen_name, data: [user_id_str: user["id_str"]]]
    content_tag(:a, "@" <> screen_name, attrs ++ @link_attrs)
  end

  # TODO: use a file template instead?
  def render("tweet_link.html", %{user: user, tweet: tweet} = assigns) do
    id_str = tweet["id_str"]
    screen_name = user["screen_name"] || ""
    href = "https://twitter.com/#{screen_name}/status/#{id_str}"
    attrs = [href: href, data: [tweet_id_str: id_str]]
    text = assigns[:text] || "View on Twitter"
    content_tag(:a, text, attrs ++ @link_attrs)
  end

  # TODO: use a file template instead?
  def render("entity_link.html", %{url: url, entities: entities}) when is_list(entities) do
    {text, href} =
      case Enum.find(entities, fn e -> e["url"] == url end) do
        nil -> {url, url}
        entity -> {entity["display_url"], entity["expanded_url"]}
      end
    attrs = [href: href]
    content_tag(:a, text, attrs ++ @link_attrs)
  end

  def render("entity_link.html", %{url: url, entities: entities}) do
    render("entity_link.html", %{url: url, entities: entity_list(entities)})
  end

  def render("image_link.html", %{media: media}) do
    img_size =
      case media do
        [_img_list] -> "small"
        _ -> "thumb"
      end
    Enum.map(media, fn ent ->
      img_src = ent["media_url_https"]
      img_src_full = img_src <> ":large"
      # TODO: do lightbox modal in JS instead?
      # a_attrs = [href: ent["expanded_url"], data: [img_src_full: img_src_full]]
      a_attrs = [href: img_src_full, target: "_blank", data: [img_src_full: img_src_full]]
      # # TODO: figure out cheap way to keep img sizes in line with CSS
      # i_attrs =
      #   case ent["sizes"][img_size] do
      #     %{"h" => height, "w" => width} -> [height: height, width: width]
      #     _ -> []
      #   end
      i_attrs = []
      content_tag(:a, img_tag(img_src <> ":" <> img_size, i_attrs), a_attrs ++ @link_attrs)
    end)
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


  ## Public helpers

  def entity_list(nil), do: []

  def entity_list(entity_map) do
    # TODO: extract indicies
    entity_map
    |> Map.take(["urls", "media", "user_mentions"])
    |> Enum.flat_map(fn {_, entities} -> entities end)
    |> Enum.sort_by(fn entity -> hd(entity["indices"]) end)
  end

  def find_user(tweet, users) do
    users[tweet["user"]["id_str"]]
  end

  # Split text by lines, interspersing <br> elements
  def break_lines(text) do
    String.split(text, "\n")
    |> Enum.intersperse(tag(:br))
  end
end
