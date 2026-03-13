defmodule Bonfire.PanDoRa.Web.RedirectController do
  @moduledoc """
  Simple redirects for legacy or alternate URLs.
  """
  use Bonfire.UI.Common.Web, :controller

  def to_my_lists(conn, _params) do
    redirect(conn, to: "/archive/my_lists")
  end
end
