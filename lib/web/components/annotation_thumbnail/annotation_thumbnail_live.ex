# lib/web/components/annotation_thumbnail/annotation_thumbnail_live.ex
defmodule Bonfire.PanDoRa.Web.AnnotationThumbnailLive do
  @moduledoc """
  Renders a clickable thumbnail for video annotations when showing_within is :feed or :thread.
  Links to the movie page. Uses Pandora proxy URL for the thumbnail (icon128.jpg).
  Renders nothing when not in feed context or when no thumbnail is available.
  """
  use Bonfire.UI.Common.Web, :stateless_component
  use Bonfire.Common.Utils

  require Logger

  prop activity, :map, required: true
  prop object, :map, required: true
  prop showing_within, :atom, default: :thread

  def render(assigns) do
    # DEBUG: log inputs to trace why thumbnail may not render
    _log_annotation_thumbnail_debug(assigns)

    ~F"""
    <a
      :if={@showing_within in [:feed, :thread] and annotation?(@activity, @object) and thumbnail_src(@activity, @object)}
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
      nil ->
        case pandora_movie_id(object) do
          nil -> lazy_thumbnail_url(object)
          id -> PanDoRa.API.Client.media_proxy_url(String.trim(id), "icon128.jpg")
        end
      media ->
        thumbnail_from_media(media)
    end
  end

  defp lazy_thumbnail_url(object) do
    id = e(object, :id, nil)
    if is_binary(id) and id != "", do: "/archive/posts/#{id}/thumbnail", else: nil
  end

  defp pandora_movie_id(object) do
    id =
      e(object, :extra_info, :info, :pandora_movie_id, nil) ||
        e(object, :extra_info, :info, "pandora_movie_id", nil)

    if is_binary(id) and id != "", do: String.trim(id), else: nil
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

  defp _log_annotation_thumbnail_debug(assigns) do
    activity = assigns.activity
    object = assigns.object
    showing_within = assigns.showing_within

    # Log ALWAYS (use info so it shows) to verify component is invoked at all
    is_annot = annotation?(activity, object)
    verb_ok = verb_annotate?(activity)
    ts_ok = timestamps?(object)
    media = first_media(activity, object)
    thumb = thumbnail_src(activity, object)

    Logger.info(
      "[AnnotationThumbnail] showing_within=#{inspect(showing_within)} " <>
        "annotation?=#{is_annot} (verb?=#{verb_ok} ts?=#{ts_ok}) " <>
        "media=#{if media, do: "ok", else: "nil"} thumb=#{if thumb, do: "ok", else: "nil"}"
    )

    if showing_within in [:feed, :thread] and (not is_annot or not thumb) do
      act_media = e(activity, :media, nil)
      obj_media = e(object, :media, nil)
      media_summary = fn
        nil -> "nil"
        [] -> "[]"
        [h | _] when is_map(h) -> "list[keys=#{inspect(Map.keys(h))}]"
        other -> inspect(other)
      end

      Logger.info(
        "[AnnotationThumbnail] FEED+no_thumb: activity.keys=#{inspect(Map.keys(activity || %{}))} " <>
          "verb=#{inspect(e(activity, :verb, nil))} verb_id=#{inspect(e(activity, :verb_id, nil))} " <>
          "activity.media=#{media_summary.(act_media)} object.media=#{media_summary.(obj_media)} " <>
          "object.extra_info=#{inspect(e(object, :extra_info, nil))}"
      )
    end
  end

  defp movie_path(activity, object) do
    case first_media(activity, object) do
      nil ->
        case pandora_movie_id(object) do
          nil ->
            case e(activity, :replied, :reply_to, :object, nil) do
              %{metadata: %{"canonical_media" => path}} when is_binary(path) -> path
              %{metadata: %{canonical_media: path}} when is_binary(path) -> path
              _ -> lazy_movie_redirect_path(object)
            end

          id ->
            "/archive/movies/#{id}"
        end

      media ->
        e(media, :metadata, "canonical_media", nil) || e(media, :metadata, :canonical_media, nil) || "/"
    end
  end

  defp lazy_movie_redirect_path(object) do
    id = e(object, :id, nil)
    if is_binary(id) and id != "", do: "/archive/posts/#{id}/movie_redirect", else: "/"
  end
end
