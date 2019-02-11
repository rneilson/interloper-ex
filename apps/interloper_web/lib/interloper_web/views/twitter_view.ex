defmodule InterloperWeb.TwitterView do
  use InterloperWeb, :view

  # alias InterloperWeb.SharedView

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

  def render("image_links.html", %{images: images}) do
    img_size =
      case images do
        [_img_list] -> "small"
        _ -> "thumb"
      end
    # TODO: move lambda into named fn
    Enum.map(images, fn ent ->
      img_src = ent["media_url_https"] <> ":" <> img_size
      img_src_full = ent["media_url_https"] <> ":large"
      # s_attrs =
      #   case ent["sizes"][img_size] do
      #     %{"h" => height, "w" => width} -> [height: height, width: width]
      #     _ -> []
      #   end
      # TODO: split into named fns
      cond do
        ent["type"] == "video" and ent["video_info"]["variants"] ->
          # Get, filter, and sort video variants
          bitrater = fn v -> v["bitrate"] end
          videos =
            ent["video_info"]["variants"]
            |> Enum.filter(bitrater)
            |> Enum.sort_by(bitrater)
          # Use highest bitrate for video
          vid = List.last(videos)
          vid_type = vid["content_type"]
          vid_src_full = vid["url"]
          # Use <video> tag instead
          v_attrs = [controls: true, poster: img_src, data: [vid_src_full: vid_src_full]]
          content_tag(:video, tag(:source, src: vid_src_full, type: vid_type), v_attrs)
        true ->
          # TODO: do lightbox modal in JS instead?
          # a_attrs = [href: ent["expanded_url"], data: [img_src_full: img_src_full]]
          a_attrs = [href: img_src_full, data: [img_src_full: img_src_full]]
          # TODO: figure out cheap way to keep img sizes in line with CSS
          content_tag(:a, img_tag(img_src), a_attrs ++ @link_attrs)
      end
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


  ## Internal/private

  defp entity_list(nil), do: []

  defp entity_list(entity_map) do
    # TODO: extract indicies
    entity_map
    |> Map.take(["urls", "media", "user_mentions"])
    |> Enum.flat_map(fn {_, entities} -> entities end)
    |> Enum.sort_by(fn entity -> hd(entity["indices"]) end)
  end

  defp find_user(tweet, users) do
    users[tweet["user"]["id_str"]]
  end

  # Split text by lines, interspersing <br> elements
  defp break_lines(text) do
    String.split(text, "\n")
    |> Stream.map(&Phoenix.HTML.raw/1)
    |> Enum.intersperse(tag(:br))
  end

  defp get_tweet_href(id_str, screen_name) when is_binary(id_str) and is_binary(screen_name) do
    "https://twitter.com/#{screen_name}/status/#{id_str}"
  end

  defp get_tweet_href(tweet, user) do
    get_tweet_href(tweet["id_str"], user["screen_name"])
  end

  defp get_reply_href(tweet) do
    get_tweet_href(tweet["in_reply_to_status_id_str"], tweet["in_reply_to_screen_name"])
  end
end
