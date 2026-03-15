# lib/web/components/annotation_video_preview/annotation_video_preview_live.ex
defmodule Bonfire.PanDoRa.Web.AnnotationVideoPreviewLive do
  @moduledoc """
  Renders a video preview for Pandora annotations in the feed.
  Uses poster (icon128) and video stream (480p.mp4) via proxy URLs.
  Renders nothing when not in feed context or when not a Pandora annotation.
  """
  use Bonfire.UI.Common.Web, :stateless_component
  use Bonfire.Common.Utils

  alias PanDoRa.API.Client

  prop activity, :map, required: true
  prop object, :map, required: true
  prop showing_within, :atom, default: :thread

  def render(assigns) do
    ~F"""
    <div
      :if={@showing_within == :feed and annotation?(@activity, @object) and movie_id(@object)}
      class="block my-2 rounded-lg overflow-hidden border border-base-content/10 aspect-video max-w-xs"
    >
      <video
        poster={poster_url(@object)}
        src={video_url(@object)}
        controls
        muted
        playsinline
        preload="metadata"
        class="w-full h-full object-cover"
      >
        Your browser does not support the video tag.
      </video>
      <a href={movie_path(@object)} class="block text-xs mt-1 text-primary/80 hover:underline">
        View full movie
      </a>
    </div>
    """
  end

  defp annotation?(activity, object) do
    verb_annotate?(activity) or timestamps?(object)
  end

  defp verb_annotate?(activity) do
    verb = e(activity, :verb, nil) || e(activity, :verb_id, nil)
    verb == :annotate or verb == "annotate"
  end

  defp timestamps?(object) do
    ts =
      e(object, :extra_info, :info, :timestamps, nil) ||
        e(object, :extra_info, :info, "timestamps", nil)

    ts != nil and (Map.get(ts || %{}, :in) != nil or Map.get(ts || %{}, "in") != nil)
  end

  defp movie_id(object) do
    id =
      e(object, :extra_info, :info, :pandora_movie_id, nil) ||
        e(object, :extra_info, :info, "pandora_movie_id", nil)

    if is_binary(id) and id != "", do: String.trim(id), else: nil
  end

  defp poster_url(object) do
    case movie_id(object) do
      nil -> nil
      id -> Client.media_proxy_url(id, "icon128.jpg")
    end
  end

  defp video_url(object) do
    case movie_id(object) do
      nil -> nil
      id -> Client.video_proxy_url(id, "480p.mp4")
    end
  end

  defp movie_path(object) do
    case movie_id(object) do
      nil -> "/"
      id -> "/archive/movies/#{id}"
    end
  end
end
