# lib/pandora/archives.ex
defmodule Bonfire.PanDoRa.Archives do
  import Ecto.Query

  alias PanDoRa.API.Client
  alias Bonfire.PanDoRa.PaginationContext
  use Bonfire.Common.Utils
  use Bonfire.Common.Repo

  @behaviour Bonfire.Common.ContextModule
  def verb_context_module, do: :annotate

  # @default_per_page 20
  # @filter_per_page 10
  # @default_keys ~w(title id item_id public_id director sezione edizione featuring duration)

  # def search_items(conditions, opts) do
  #   page = Keyword.get(opts, :page, 0)
  #   per_page = Keyword.get(opts, :per_page, @default_per_page)

  #   Client.find(opts ++ [
  #     conditions: conditions,
  #     range: [page * per_page, per_page],
  #     keys: @default_keys,
  #     total: true
  #   ])
  # end

  # def fetch_metadata(conditions, opts) do
  #   field = Keyword.get(opts, :field)
  #   page = Keyword.get(opts, :page, 0)
  #   per_page = Keyword.get(opts, :per_page, @filter_per_page)

  #   client_opts = [per_page: per_page]
  #   client_opts = if field, do: [{:field, field}, {:page, page} | client_opts], else: client_opts

  #   Client.fetch_grouped_metadata(conditions, opts ++ client_opts)
  # end

  # def build_search_query(term, filters) do
  #   filter_conditions = build_filter_conditions(filters)

  #   case {term, filter_conditions} do
  #     {nil, []} ->
  #       []

  #     {term, []} when is_binary(term) and term != "" ->
  #       [%{key: "*", operator: "=", value: term}]

  #     {nil, [single]} ->
  #       [single]

  #     {nil, multiple} when length(multiple) > 0 ->
  #       [%{conditions: multiple, operator: "&"}]

  #     {term, filters} when is_binary(term) and term != "" ->
  #       [%{conditions: [%{key: "*", operator: "=", value: term} | filters], operator: "&"}]
  #   end
  # end

  # defp build_filter_conditions(filters) do
  #   filters
  #   |> Enum.reject(fn {_type, values} -> values == [] end)
  #   |> Enum.map(fn
  #     {type, [value]} ->
  #       %{key: type, operator: "==", value: value}

  #     {type, values} when length(values) > 0 ->
  #       %{
  #         conditions: Enum.map(values, &%{key: type, operator: "==", value: &1}),
  #         operator: "|"
  #       }
  #   end)
  # end

  def add_annotation(%{"id" => _movie_id} = movie, note, in_timestamp, out_timestamp, opts) do
    # Video preview is rendered by AnnotationVideoPreviewLive in the feed; no media in html_body
    html_body = note || ""

    with current_user = current_user(opts),
         out_timestamp = out_timestamp || in_timestamp,
         # Pandora first: get pandora_id before creating Post (source of truth)
         {:ok, %{"id" => pandora_id} = annotation} <-
           Client.add_annotation(
             %{
               item: movie["id"],
               layer: "publicnotes",
               in: in_timestamp || 0.0,
               out: out_timestamp || 0.0,
               value: note
             },
             opts
           ),
         # resolve media for metadata (media_id, movie_id)
         {:ok, %{id: media_id} = media} <- resolve_media_for_annotation(current_user, movie, opts),
         # publish standalone Post for feed; uploaded_media enables thumbnail in feed
         {:ok, %{id: post_id} = _post} <-
           maybe_apply(Bonfire.Posts, :publish, [
             [
               current_user: current_user,
               verb: :annotate,
               post_attrs: %{
                 # reply_to_id: media_id, # do we reference the media in reply to
                 #  or as a linked media
                 post_content: %{html_body: html_body},
                 uploaded_media: [media]
               },
               boundary: "public"
             ]
           ]),
         # save ExtraInfo with pandora_id, media_id, movie_id, timestamps
         {:ok, extra_info} <-
           Bonfire.Data.Identity.ExtraInfo.changeset(%{
             id: post_id,
             info: %{
               pandora_id: pandora_id,
               media_id: media_id,
               pandora_movie_id: movie["id"],
               timestamps: %{in: in_timestamp, out: out_timestamp}
             }
           })
           |> repo().insert() do
      {:ok, annotation |> Map.put(:extra_info, extra_info)}
    end
  end

  defp to_absolute_url("http" <> _ = url), do: url
  defp to_absolute_url("https" <> _ = url), do: url
  defp to_absolute_url("/" <> rest) when is_binary(rest) do
    Bonfire.Common.URIs.based_url("/" <> rest, nil)
  end
  defp to_absolute_url(url) when is_binary(url), do: url

  defp media_fragment_url(base, in_ts, out_ts) do
    in_s = to_seconds(in_ts)
    out_s = to_seconds(out_ts)

    cond do
      in_s != nil and out_s != nil and out_s > in_s ->
        "#{base}#t=#{Float.to_string(in_s, decimals: 1)},#{Float.to_string(out_s, decimals: 1)}"

      in_s != nil ->
        "#{base}#t=#{Float.to_string(in_s, decimals: 1)}"

      true ->
        base
    end
  end

  defp to_seconds(n) when is_number(n) and n >= 0, do: n * 1.0
  defp to_seconds(s) when is_binary(s), do: parse_timestamp_to_seconds(s)
  defp to_seconds(_), do: nil

  defp parse_timestamp_to_seconds(s) when is_binary(s) do
    if String.contains?(s, ":") do
      # HH:MM:SS or MM:SS
      parts = String.split(s, ":", parts: 3)
      case Enum.map(parts, &String.to_float/1) do
        [{h, _}, {m, _}, {s, _}] -> h * 3600 + m * 60 + s
        [{m, _}, {s, _}] -> m * 60 + s
        [{s, _}] -> s
        _ -> nil
      end
    else
      case Float.parse(s) do
        {n, ""} when n >= 0 -> n
        _ -> nil
      end
    end
  end

  defp parse_timestamp_to_seconds(_), do: nil

  @doc """
  Get or create the Bonfire Media for a movie. Use when the thread (ThreadLive) must exist,
  e.g. on the movie playback page so annotations can be shown.
  """
  def movie_get_or_create_media(current_user, movie, opts \\ []) do
    movie_id = Keyword.get(opts, :movie_id) || e(movie, "id", nil)
    movie = if movie_id, do: Map.put(movie, "id", movie_id), else: movie
    movie_get_or_save_media(current_user, movie, opts)
  end

  def movie_get_media(movie_id, opts \\ [])

  def movie_get_media(movie_id, _opts) when is_binary(movie_id) do
    url = "#{Client.get_pandora_url()}/#{movie_id}"
    case Bonfire.Files.Media.get_by_path(url) do
      {:ok, media} -> {:ok, media}
      # path is nil for Pandora URLs (remote_url returns http; Media avoids storing presigned URLs)
      {:error, :not_found} -> movie_get_media_by_canonical(movie_id)
    end
  end

  def movie_get_media(%{"id" => movie_id} = _movie, opts) do
    movie_get_media(movie_id, opts)
  end

  defp movie_get_media_by_canonical(movie_id) when is_binary(movie_id) do
    canonical = "/archive/movies/#{movie_id}"
    from(m in Bonfire.Files.Media, where: fragment("metadata->>'canonical_media' = ?", ^canonical), limit: 1, order_by: [desc: m.id])
    |> repo().single()
  end

  @doc """
  If the given id is a Pandora Media (thread for movie annotations) with canonical_media
  in metadata, returns the canonical path (e.g. "/archive/movies/FZV") to redirect to.
  Otherwise returns nil.
  Used when /discussion/:id is visited with a Media thread id - redirect to the movie page.
  """
  def pandora_media_canonical_path(id) when is_binary(id) do
    case Bonfire.Files.Media.one(id: id) do
      {:ok, media} ->
        e(media, :metadata, "canonical_media", nil) || e(media, :metadata, :canonical_media, nil)

      _ ->
        nil
    end
  end

  def pandora_media_canonical_path(_), do: nil

  defp resolve_media_for_annotation(current_user, movie, opts) do
    case Keyword.get(opts, :media) do
      %{id: _} = media -> {:ok, media}
      _ ->
        movie_id = Keyword.get(opts, :movie_id) || e(movie, "id", nil)
        movie = if movie_id, do: Map.put(movie, "id", movie_id), else: movie
        movie_get_or_save_media(current_user, movie, opts)
    end
  end

  defp movie_get_or_save_media(current_user, %{"id" => movie_id} = movie, opts) do
    url = "#{Client.get_pandora_url()}/#{movie_id}"
    file_attrs = %{media_type: "video/film", size: 0}
    # Use proxy URLs for icon/image so preview works in feed without auth (MediaLive.preview_img reads metadata.icon)
    attrs = %{
      metadata:
        Map.merge(movie, %{
          canonical_media: "/archive/movies/#{movie_id}",
          icon: Client.media_proxy_url(movie_id, "icon128.jpg"),
          image: Client.media_proxy_url(movie_id, "icon512.jpg")
        })
    }

    with {:error, :not_found} <- movie_get_media(movie_id, opts) do
      with {:ok, media} <-
             Bonfire.Files.Media.insert(
               current_user,
               url,
               file_attrs,
               attrs
             ),
           # TODO: add to search index
           _ <-
             Bonfire.Social.Objects.set_boundaries(
               current_user,
               media,
               #  TODO
               [boundary: "public"],
               __MODULE__
             ) do
        {:ok, media}
      end
    else
      {:ok, media} ->
        # already exists
        if opts[:update_existing] == :force do
          Bonfire.Files.Media.insert(
            current_user,
            url,
            file_attrs,
            attrs
          )
        else
          {:ok, media}
        end

      e ->
        error(e)
    end
  end

  # Handle submitting the edit
  def edit_post_content(post, opts) do
    post = repo().maybe_preload(post, :extra_info)

    with pandora_id when is_binary(pandora_id) <-
           e(post, :extra_info, :info, "pandora_id", :no_pandora_ref),
         text when is_binary(text) <- e(post, :post_content, :html_body, :no_text),
         edit_data = %{
           id: pandora_id,
           value: text
         },
         {:ok, updated_annotation} <-
           Client.edit_annotation(edit_data, current_user: current_user(opts)) do
      {:ok, updated_annotation}
    end
  end

  def delete_activity(post, opts) do
    post = repo().maybe_preload(post, :extra_info)
    pandora_id = e(post, :extra_info, :info, "pandora_id", :no_pandora_ref)

    case pandora_id && Client.remove_annotation(pandora_id, current_user: current_user(opts)) do
      {:ok, response} ->
        {:ok, response}

      :no_pandora_ref ->
        :no_pandora_ref

      error ->
        msg = "Error deleting annotation"
        error(error, msg)
        raise msg
    end
  end
end
