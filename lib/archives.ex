# lib/pandora/archives.ex
defmodule Bonfire.PanDoRa.Archives do
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

  def add_annotation(%{"id" => movie_id} = movie, note, in_timestamp, out_timestamp, opts) do
    with current_user = current_user(opts),
         out_timestamp = out_timestamp || in_timestamp,
         # first check if Media exists for the movie and otherwise create it
         {:ok, %{id: media_id} = media} <- movie_get_or_save_media(current_user, movie, opts),
         # create Post first so text is checked by anti-spam
         {:ok, %{id: post_id} = post} <-
           maybe_apply(Bonfire.Posts, :publish, [
             [
               current_user: current_user,
               verb: :annotate,
               post_attrs: %{
                 thread_id: media_id,
                 # reply_to_id: media_id, # do we reference the media in reply to
                 #  or as a linked media
                 uploaded_media: [media],
                 post_content: %{
                   html_body: note
                 }
               },
               # TODO
               boundary: "public"
             ]
           ]),
         # next send it to Pandora
         {:ok, %{"id" => pandora_id} = annotation} <-
           Client.add_annotation(
             %{
               item: movie_id,
               # assuming this is your layer ID for public notes - TODO: based on boundary?
               layer: "publicnotes",
               in: in_timestamp || 0.0,
               out: out_timestamp || 0.0,
               value: note
             },
             opts
           ),
         # then save ExtraInfo on the Post with the timestamps and reference to the note on Pandora
         {:ok, extra_info} <-
           Bonfire.Data.Identity.ExtraInfo.changeset(%{
             id: post_id,
             info: %{pandora_id: pandora_id, timestamps: %{in: in_timestamp, out: out_timestamp}}
           })
           |> debug("cssss")
           |> repo().insert() do
      {:ok, Map.put(annotation, :extra_info, extra_info)}
    end
  end

  def movie_get_media(movie_id, opts \\ [])

  def movie_get_media(movie_id, _opts) when is_binary(movie_id) do
    url = "#{Client.get_pandora_url()}/#{movie_id}"
    Bonfire.Files.Media.get_by_path(url)
  end

  def movie_get_media(%{"id" => movie_id} = _movie, opts) do
    movie_get_media(movie_id, opts)
  end

  defp movie_get_or_save_media(current_user, %{"id" => movie_id} = movie, opts) do
    url = "#{Client.get_pandora_url()}/#{movie_id}"
    file_attrs = %{media_type: "video/film", size: 0}
    #  TODO: should we also add the video & image URLs etc?
    attrs = %{
      metadata:
        Map.merge(movie, %{
          canonical_media: "/archive/movies/#{movie_id}",
          icon: "#{url}/icon128.jpg",
          image: "#{url}/icon512.jpg"
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
