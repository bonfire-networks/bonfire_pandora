# lib/web/components/annotation_timestamp_badge/annotation_timestamp_badge_live.ex
defmodule Bonfire.PanDoRa.Web.AnnotationTimestampBadgeLive do
  @moduledoc """
  Renders a clickable timestamp badge for video annotations when showing_within=:annotations.
  The badge shows in/out timestamps and seeks the video when clicked (via movie_live.hooks.js).
  Renders nothing when not in annotations context or when object has no timestamps.
  """
  use Bonfire.UI.Common.Web, :stateless_component
  use Bonfire.Common.Utils

  prop object, :map, required: true
  prop showing_within, :atom, default: :thread

  def render(assigns) do
    ~F"""
    <span
      :if={@showing_within == :annotations and timestamps?(@object)}
      data-role="annotation-checkpoint"
      data-in={in_seconds(@object)}
      data-out={out_seconds(@object)}
      class="btn btn-soft btn-accent btn-xs cursor-pointer"
    >
      From {Bonfire.Common.DatesTimes.format_duration(in_seconds(@object))} to {Bonfire.Common.DatesTimes.format_duration(out_seconds(@object))}
    </span>
    """
  end

  defp timestamps?(object) do
    ts = get_timestamps(object)
    ts != nil and (Map.get(ts, :in) != nil or Map.get(ts, "in") != nil)
  end

  defp in_seconds(object) do
    ts = get_timestamps(object)
    (ts && (Map.get(ts, :in) || Map.get(ts, "in"))) || 0.0
  end

  defp out_seconds(object) do
    ts = get_timestamps(object)
    (ts && (Map.get(ts, :out) || Map.get(ts, "out"))) || in_seconds(object)
  end

  defp get_timestamps(object) do
    e(object, :extra_info, :info, :timestamps, nil) ||
      e(object, :extra_info, :info, "timestamps", nil)
  end
end
