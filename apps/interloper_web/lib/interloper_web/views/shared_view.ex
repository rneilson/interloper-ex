defmodule InterloperWeb.SharedView do
  use InterloperWeb, :view

  ## Date formatting
  # TODO: move to own lib?

  # Nicely(ish) format given datetime
  # TODO: fancy it up with proper day/month strings
  # TODO: spec & doc
  def date_format(%DateTime{calendar: Calendar.ISO} = dt) do
    [
      Calendar.ISO.date_to_string(dt.year, dt.month, dt.day),
      Calendar.ISO.time_to_string(dt.hour, dt.minute, dt.second, {0, 0}),
      dt.zone_abbr
    ]
    |> Enum.join(" ")
  end

  # Assume integer datetimes in millisecond unix epoch
  def date_format(dt) do
    case convert_datetime(dt) do
      nil -> nil
      datetime -> date_format(datetime)
    end
  end


  ## Private/internal

  defp convert_datetime(dt) when is_integer(dt) do
    case DateTime.from_unix(dt, :millisecond) do
      {:ok, datetime} -> datetime
      _ -> nil
    end
  end

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
