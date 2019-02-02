defmodule InterloperWeb.SharedView do
  use InterloperWeb, :view

  ## Date formatting
  # TODO: move to own lib?

  def render_date_format(dt) do
    dt_str = date_format(dt)
    content_tag(:span, dt_str, class: "green")
  end

  # TODO: spec & doc
  # Currently only allow ISO datetimes
  def date_format(dt) when is_binary(dt) do
    case DateTime.from_iso8601(dt) do
      {:ok, datetime, 0} -> date_format(datetime)
      _ -> dt
    end
  end

  def date_format(%NaiveDateTime{} = dt) do
    case DateTime.from_naive(dt) do
      {:ok, datetime, 0} -> date_format(datetime)
      _ -> NaiveDateTime.to_string(dt)
    end
  end

  # Process once converted
  def date_format(%DateTime{calendar: Calendar.ISO} = dt) do
    [
      Calendar.ISO.date_to_string(dt.year, dt.month, dt.day),
      Calendar.ISO.time_to_string(dt.hour, dt.minute, dt.second, {0, 0}),
      dt.zone_abbr
    ]
    |> Enum.join(" ")
  end
end