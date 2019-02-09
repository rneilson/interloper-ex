defmodule InterloperWeb.SharedView do
  use InterloperWeb, :view

  ## Misc formatting
  # TODO: move to own lib?

  # Ensure stringified
  # TODO: better way to ensure stringified for non-maps?
  # TODO: spec & doc
  def ensure_string(source, opts \\ [])

  # TODO: lists too?
  def ensure_string(source, opts) when is_map(source) or is_list(source) do
    case Jason.encode_to_iodata(source, opts) do
      {:ok, source_str} -> source_str
      {:error, _reason} -> "Error parsing message"
    end
  end

  def ensure_string(source, _opts) when is_binary(source), do: source

  def ensure_string(source, _opts), do: to_string(source)

  # Nicely(ish) format given datetime
  # TODO: fancy it up with proper day/month strings
  # TODO: spec & doc
  def date_format(dt)

  def date_format(%DateTime{calendar: Calendar.ISO} = dt) do
    [
      Calendar.ISO.date_to_string(dt.year, dt.month, dt.day),
      Calendar.ISO.time_to_string(dt.hour, dt.minute, dt.second, {0, 0}),
      dt.zone_abbr
    ]
    |> Enum.join(" ")
  end

  def date_format(dt) do
    case convert_datetime(dt) do
      nil -> nil
      datetime -> date_format(datetime)
    end
  end


  ## Private/internal

  # Assume integer datetimes in millisecond unix epoch
  defp convert_datetime(dt) when is_integer(dt) do
    case DateTime.from_unix(dt, :millisecond) do
      {:ok, datetime} -> datetime
      _ -> nil
    end
  end

  # Assumes ISO string, assumes UTC if offset unspecified
  defp convert_datetime(dt) when is_binary(dt) do
    case DateTime.from_iso8601(dt) do
      {:ok, datetime, _} -> datetime
      {:error, :missing_offset} -> convert_datetime(dt <> "Z")
      {:error, :invalid_format} ->
        case Integer.parse(dt) do
          {dt_int, _remainder} -> convert_datetime(dt_int)
          _ -> nil
        end
      _ -> nil
    end
  end

  defp convert_datetime(%NaiveDateTime{} = dt) do
    case DateTime.from_naive(dt, "Etc/UTC") do
      {:ok, datetime, _} -> datetime
      _ -> nil
    end
  end

  defp convert_datetime(%DateTime{} = dt), do: dt

  defp convert_datetime(_), do: nil
end
