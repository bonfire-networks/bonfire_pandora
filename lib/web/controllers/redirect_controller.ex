defmodule Bonfire.PanDoRa.Web.RedirectController do
  @moduledoc """
  Simple redirects for legacy or alternate URLs.
  """
  use Bonfire.UI.Common.Web, :controller
  use Bonfire.Common.Repo

  def to_my_lists(conn, _params) do
    redirect(conn, to: "/archive/my_lists")
  end

  @doc "Redirect GET /post and GET /post/ (missing id) to home. Prevents NoRouteError."
  def to_home(conn, _params) do
    redirect(conn, to: "/")
  end

  @doc """
  Lazy-load thumbnail for annotation posts. Fetches ExtraInfo by post id, redirects to Pandora proxy.
  Used when object.extra_info and activity.media are not preloaded.
  """
  def annotation_thumbnail(conn, %{"id" => id}) when is_binary(id) and id != "" do
    case repo().get(Bonfire.Data.Identity.ExtraInfo, id) do
      %{info: %{"pandora_movie_id" => movie_id}} when is_binary(movie_id) ->
        url = PanDoRa.API.Client.media_proxy_url(String.trim(movie_id), "icon128.jpg")
        redirect(conn, to: url)

      %{info: %{pandora_movie_id: movie_id}} when is_binary(movie_id) ->
        url = PanDoRa.API.Client.media_proxy_url(String.trim(movie_id), "icon128.jpg")
        redirect(conn, to: url)

      _ ->
        conn
        |> put_status(404)
        |> put_view(Bonfire.UI.Common.ErrorView)
        |> render(:"404")
    end
  end

  def annotation_thumbnail(conn, _params), do: redirect(conn, to: "/")

  @doc """
  Lazy-load movie redirect for annotation posts. Fetches ExtraInfo by post id, redirects to movie page.
  """
  def annotation_movie_redirect(conn, %{"id" => id}) when is_binary(id) and id != "" do
    case repo().get(Bonfire.Data.Identity.ExtraInfo, id) do
      %{info: %{"pandora_movie_id" => movie_id}} when is_binary(movie_id) ->
        redirect(conn, to: "/archive/movies/#{String.trim(movie_id)}")

      %{info: %{pandora_movie_id: movie_id}} when is_binary(movie_id) ->
        redirect(conn, to: "/archive/movies/#{String.trim(movie_id)}")

      _ ->
        redirect(conn, to: "/")
    end
  end

  def annotation_movie_redirect(conn, _params), do: redirect(conn, to: "/")
end
