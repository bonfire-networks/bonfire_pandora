defmodule Bonfire.PanDoRa.Archive.HtmlBodyPreprocessor do
  @moduledoc """
  Expands trusted embed markers in html_body to video preview markup.

  Markers are links `<a href="/archive/movies/{id}#t={in},{out}"></a>` that pass
  the HTML sanitizer. At render time, this module replaces them with trusted
  `<video>` markup generated server-side. See PIANO_VIDEO_PREVIEW_TRUSTED_EMBED.md.
  """

  alias PanDoRa.API.Client
  alias Bonfire.Common.Utils

  # Matches: <a href="/archive/movies/MOVIE_ID#t=IN,OUT">optional content</a>
  @marker_regex ~r|<a\s+href="/archive/movies/([^"#]+)#t=([\d.]+),([\d.]+)"([^>]*)>(.*?)</a>|s

  # :clip_query — `480p.mp4?…&t=in,out` (server-generated clip; heavy on Pandora)
  # :full_mp4_fragment — full `480p.mp4?token=…#t=in,out` (Media Fragment; no ?t= on server)
  @pandora_marker_video_src_mode :full_mp4_fragment

  @doc """
  Replaces Pandora video preview markers with trusted video markup.

  Uses direct Pandora URL with token when available (like SearchLive/lists),
  otherwise falls back to proxy. Pass opts with :current_user for user-specific token.

  Returns the html_body unchanged if nil, empty, or no markers found.
  """
  def expand_video_preview_links(html_body, opts \\ [])

  def expand_video_preview_links(nil, _opts), do: nil
  def expand_video_preview_links("", _opts), do: ""

  def expand_video_preview_links(html_body, opts) when is_binary(html_body) do
    opts = Utils.to_options(opts)
    # Regex.replace with arity-2 fn passes (full_match, first_capture); extract all via run
    replace_fn = fn full_match, _first_capture ->
      [movie_id, in_s, out_s | _] = Regex.run(@marker_regex, full_match, capture: :all_but_first)
      replace_marker(movie_id, in_s, out_s, opts)
    end
    Regex.replace(@marker_regex, html_body, replace_fn)
  end

  defp replace_marker(movie_id, in_s, out_s, opts) do
    build_poster_html(movie_id, in_s, out_s, opts)
  end

  # Wrapped in div so PreviewActivity ignores clicks (see shouldHandlePreviewClick: .pandora-video-preview-wrapper).
  # `data-pandora-selection-url` = Pandora "link selection" path `/{id}/{in},{out}` (viewer page, not mp4).
  defp build_poster_html(movie_id, in_s, out_s, opts) do
    selection_url = Client.selection_timeline_url(movie_id, in_s, out_s, opts)

    video_src =
      case @pandora_marker_video_src_mode do
        :full_mp4_fragment ->
          base_src = Client.video_url(movie_id, "480p.mp4", opts)
          "#{base_src}#t=#{in_s},#{out_s}"

        :clip_query ->
          clip_t = "#{in_s},#{out_s}"
          Client.video_url(movie_id, "480p.mp4", Keyword.put(opts, :clip_t, clip_t))
      end

    video_tag =
      ~s(<video class="pandora-video-preview plyr rounded" src="#{escape_attr(video_src)}" preload="none" width="320" height="180" playsinline controls></video>)

    # Archives.build_annotation_html_body already adds "View full movie" link after the marker - do not duplicate
    ~s(<div class="pandora-video-preview-wrapper" data-pandora-selection-url="#{escape_attr(selection_url)}">#{video_tag}</div>)
  end

  defp escape_attr(str), do: Plug.HTML.html_escape_to_iodata(str) |> IO.iodata_to_binary()
end
