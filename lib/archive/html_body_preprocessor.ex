defmodule Bonfire.PanDoRa.Archive.HtmlBodyPreprocessor do
  @moduledoc """
  Expands trusted embed markers in html_body to video preview markup.

  Markers are links `<a href="/archive/movies/{id}#t={in},{out}"></a>` that pass
  the HTML sanitizer. At render time, this module replaces them with trusted
  `<video>` markup generated server-side. See PIANO_VIDEO_PREVIEW_TRUSTED_EMBED.md.
  """

  alias PanDoRa.API.Client

  # Matches: <a href="/archive/movies/MOVIE_ID#t=IN,OUT">optional content</a>
  @marker_regex ~r|<a\s+href="/archive/movies/([^"#]+)#t=([\d.]+),([\d.]+)"([^>]*)>(.*?)</a>|s

  @doc """
  Replaces Pandora video preview markers with trusted video markup.

  Returns the html_body unchanged if nil, empty, or no markers found.
  """
  def expand_video_preview_links(nil), do: nil
  def expand_video_preview_links(""), do: ""

  def expand_video_preview_links(html_body) when is_binary(html_body) do
    # Regex.replace passes (full_match, cap1, cap2, cap3, ...) - each capture as separate arg
    Regex.replace(@marker_regex, html_body, &replace_marker/6)
  end

  defp replace_marker(_full_match, movie_id, in_s, out_s, _attrs, _content) do
    video_html = build_video_html(movie_id, in_s, out_s)
    movie_url = "/archive/movies/#{movie_id}"
    ~s(<a href="#{movie_url}">#{video_html}</a>)
  end

  defp build_video_html(movie_id, in_s, out_s) do
    video_base = Client.video_proxy_url(movie_id, "480p.mp4")
    video_src = "#{video_base}#t=#{in_s},#{out_s}"
    ~s(<video src="#{escape_attr(video_src)}" muted loop autoplay playsinline width="320" height="180" preload="metadata"></video>)
  end

  defp escape_attr(str), do: Plug.HTML.html_escape_to_iodata(str) |> IO.iodata_to_binary()
end
