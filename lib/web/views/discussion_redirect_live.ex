# lib/web/views/discussion_redirect_live.ex
defmodule Bonfire.PanDoRa.Web.DiscussionRedirectLive do
  @moduledoc """
  Wrapper for /discussion/:id that redirects Pandora Media (movie annotation threads)
  to the canonical movie page (/archive/movies/:movie_id).
  When the id is not a Pandora Media, delegates to load_object_assigns and renders
  the default ObjectThreadLive.
  """
  use Bonfire.UI.Common.Web, :surface_live_view

  on_mount {LivePlugs, [Bonfire.UI.Me.LivePlugs.LoadCurrentUser]}

  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: l("Discussion"),
       thread_title: "Discussion",
       page: "discussion",
       showing_within: :thread,
       no_mobile_header: true,
       participants: nil,
       activity: nil,
       post: nil,
       object: nil,
       object_id: nil,
       post_id: nil,
       reply_id: nil,
       thread_id: nil,
       back: true,
       page_info: nil,
       replies: nil,
       threaded_replies: nil,
       include_path_ids: nil,
       thread_mode:
         maybe_to_atom(e(params, "mode", nil)) ||
           Bonfire.Common.Settings.get(
             [Bonfire.UI.Social.ThreadLive, :thread_mode],
             nil,
             assigns(socket)[:__context__]
           ) || :nested,
       search_placeholder: nil,
       loading: false
     )}
  end

  def handle_params(%{"id" => "comment_" <> _} = params, _url, socket) do
    delegate_to_discussion(socket, params)
  end

  def handle_params(%{"id" => id, "skip_pandora" => "1"} = params, _url, socket)
      when is_binary(id) do
    delegate_to_discussion(socket, params)
  end

  def handle_params(%{"id" => id} = params, _url, socket) when is_binary(id) do
    case Bonfire.PanDoRa.Archives.pandora_media_canonical_path(id) do
      path when is_binary(path) ->
        {:noreply,
         socket
         |> Phoenix.LiveView.push_navigate(to: path)}

      _ ->
        reply_id = e(params, "reply_id", nil)
        level = e(params, "level", nil)
        base = "/discussion/#{id}"

        path =
          cond do
            reply_id && level -> "#{base}/reply/#{level}/#{reply_id}?skip_pandora=1"
            reply_id -> "#{base}/reply/#{reply_id}?skip_pandora=1"
            true -> "#{base}?skip_pandora=1"
          end

        {:noreply,
         socket
         |> Phoenix.LiveView.push_navigate(to: path)}
    end
  end

  def handle_params(params, _url, socket) do
    delegate_to_discussion(socket, params)
  end

  defp delegate_to_discussion(socket, params) do
    id = params["id"]
    reply_id = e(params, "reply_id", nil)

    socket =
      socket
      |> assign(
        params: params,
        object_id: id,
        thread_id: id,
        reply_id: reply_id,
        include_path_ids:
          Bonfire.Social.Threads.LiveHandler.maybe_include_path_ids(
            reply_id,
            e(params, "level", nil),
            e(assigns(socket), :__context__, nil) || assigns(socket)
          )
      )

    case Bonfire.Social.Objects.LiveHandler.load_object_assigns(socket) do
      %Phoenix.LiveView.Socket{} = socket ->
        {:noreply, socket}

      {:error, e} ->
        {:noreply, assign_error(socket, e)}

      other ->
        require Untangle
        Untangle.error(other)
        {:noreply, socket}
    end
  end
end
