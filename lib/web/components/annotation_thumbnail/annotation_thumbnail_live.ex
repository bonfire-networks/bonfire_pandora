# lib/web/components/annotation_thumbnail/annotation_thumbnail_live.ex
defmodule Bonfire.PanDoRa.Web.AnnotationThumbnailLive do
  @moduledoc """
  Renders a clickable thumbnail for video annotations when showing_within=:feed.
  Links to the movie page. Uses Pandora proxy URL for the thumbnail (icon128.jpg).
  Renders nothing when not in feed context or when no thumbnail is available.
  """
  use Bonfire.UI.Common.Web, :stateless_component
  use Bonfire.Common.Utils

  prop activity, :map, required: true
  prop object, :map, required: true
  prop showing_within, :atom, default: :thread

  def render(assigns) do
    ~F"""
    <a
      :if={@showing_within == :feed and annotation?(@activity, @object) and thumbnail_src(@activity, @object)}
      href={movie_path(@activity, @object)}
      class="block my-2 rounded-lg overflow-hidden border border-base-content/10 aspect-video max-w-xs"
    >
      <img
        src={thumbnail_src(@activity, @object)}
        alt=""
        class="w-full h-full object-cover"
      />
    </a>
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
    ts = e(object, :extra_info, :info, :timestamps, nil) || e(object, :extra_info, :info, "timestamps", nil)
    ts != nil and (Map.get(ts || %{}, :in) != nil or Map.get(ts || %{}, "in") != nil)
  end

  defp thumbnail_src(activity, object) do
    case first_media(activity, object) do
      nil -> nil
      media -> thumbnail_from_media(media)
    end
  end

  defp first_media(activity, object) do
    list = e(activity, :media, nil) || e(activity, :files, nil) || e(object, :media, nil) || e(object, :files, nil)
    case List.wrap(list) do
      [%{} = m | _] -> m
      _ -> nil
    end
  end

  defp thumbnail_from_media(media) do
    # Prefer proxy URL from metadata (set when Media is created)
    e(media, :metadata, "icon", nil) ||
      e(media, :metadata, :icon, nil) ||
      # Fallback: build from canonical_media path /archive/movies/FZV -> FZV
      (case e(media, :metadata, "canonical_media", nil) || e(media, :metadata, :canonical_media, nil) do
         "/archive/movies/" <> movie_id when movie_id != "" ->
           PanDoRa.API.Client.media_proxy_url(String.trim(movie_id), "icon128.jpg")

         _ ->
           nil
       end)
  end

  defp movie_path(activity, object) do
    case first_media(activity, object) do
      nil ->
        e(activity, :replied, :reply_to, :object, nil)
        |> case do
          %{metadata: %{"canonical_media" => path}} when is_binary(path) -> path
          %{metadata: %{canonical_media: path}} when is_binary(path) -> path
          _ -> "/"
        end

      media ->
        e(media, :metadata, "canonical_media", nil) || e(media, :metadata, :canonical_media, nil) || "/"
    end
  end
end
