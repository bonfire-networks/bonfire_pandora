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

  @doc """
  Replaces Pandora video preview markers with trusted video markup.

  Uses direct Pandora URL with token when available (like SearchLive/lists),
  otherwise falls back to proxy. Pass opts with :current_user for user-specific token.

  Returns the html_body unchanged if nil, empty, or no markers found.
  """
  def expand_video_preview_links(nil, _opts \\ []), do: nil
  def expand_video_preview_links("", _opts \\ []), do: ""

  def expand_video_preview_links(html_body, opts \\ []) when is_binary(html_body) do
    opts = Utils.to_options(opts)
    # Regex.replace with arity-2 fn passes (full_match, first_capture); extract all via run
    replace_fn = fn full_match, _first_capture ->
      [movie_id, in_s, out_s | _] = Regex.run(@marker_regex, full_match, capture: :all_but_first)
      replace_marker(movie_id, in_s, out_s, opts)
    end
    Regex.replace(@marker_regex, html_body, replace_fn)
  end

  defp replace_marker(movie_id, in_s, out_s, opts) do
    video_html = build_video_html(movie_id, in_s, out_s, opts)
    movie_url = "/archive/movies/#{movie_id}"
    ~s(<a href="#{movie_url}">#{video_html}</a>)
  end

  defp build_video_html(movie_id, in_s, out_s, opts) do
    video_base = Client.video_url(movie_id, "480p.mp4", opts)
    video_src = "#{video_base}#t=#{in_s},#{out_s}"
    # preload="none" to avoid many parallel requests on feed load
    ~s(<video src="#{escape_attr(video_src)}" muted loop autoplay playsinline width="320" height="180" preload="none"></video>)
  end

  defp escape_attr(str), do: Plug.HTML.html_escape_to_iodata(str) |> IO.iodata_to_binary()
end
