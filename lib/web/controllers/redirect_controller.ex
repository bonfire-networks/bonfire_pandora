defmodule Bonfire.PanDoRa.Web.RedirectController do
  @moduledoc """
  Simple redirects for legacy or alternate URLs.
  """
  use Bonfire.UI.Common.Web, :controller

  def to_my_lists(conn, _params) do
    redirect(conn, to: "/archive/my_lists")
  end

  @doc "Redirect GET /post and GET /post/ (missing id) to home. Prevents NoRouteError."
  def to_home(conn, _params) do
    redirect(conn, to: "/")
  end
end
