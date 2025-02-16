defmodule Bonfire.PanDoRa.Components.MoviePreviewLive do
  use Bonfire.UI.Common.Web, :stateless_component
  alias PanDoRa.API.Client

  prop movie_id, :string, required: true
  prop movie, :map, required: true

  def format_duration(duration) when is_binary(duration) do
    case Float.parse(duration) do
      {seconds, _} -> format_duration(seconds)
      :error -> duration
    end
  end

  def format_duration(seconds) when is_float(seconds) do
    total_minutes = trunc(seconds / 60)
    hours = div(total_minutes, 60)
    minutes = rem(total_minutes, 60)

    cond do
      hours > 0 -> "#{hours}h #{minutes}min"
      minutes > 0 -> "#{minutes}min"
      true -> "< 1min"
    end
  end
end
