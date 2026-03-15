defmodule Bonfire.PanDoRa.Web.Routes do
  use Bonfire.Common.Localise
  import Bonfire.Common.Modularity.DeclareHelpers
  import Bonfire.UI.Common.Modularity.DeclareHelpers

  @behaviour Bonfire.UI.Common.RoutesModule

  defmacro __using__(_) do
    quote do
      # Catch GET /post and GET /post/ (missing id) — redirect to home to prevent NoRouteError.
      # Must be before bonfire_ui_posts' live("/post/:id") so invalid paths are handled.
      scope "/", Bonfire.PanDoRa.Web do
        pipe_through(:browser)

        get("/post", RedirectController, :to_home)
        get("/post/", RedirectController, :to_home)
      end

      # Redirect /discussion/:id when id is a Pandora Media (movie annotation thread) to /archive/movies/:movie_id.
      # Must be before Social's discussion route so we match first.
      scope "/", Bonfire.PanDoRa.Web do
        pipe_through(:browser)

        live("/discussion/:id", DiscussionRedirectLive, as: Needle.Pointer)
        live("/discussion/:id/reply/:reply_id", DiscussionRedirectLive, as: Needle.Pointer)
        live("/discussion/:id/reply/:level/:reply_id", DiscussionRedirectLive, as: Needle.Pointer)
      end

      # pages anyone can view
      scope "/archive/", Bonfire.PanDoRa.Web do
        pipe_through(:browser)

        live("/", SearchViewLive)
      end

      # pages only guests can view
      scope "/archive/", Bonfire.PanDoRa.Web do
        pipe_through(:browser)
        pipe_through(:guest_only)
      end

      # pages you need an account to view
      scope "/archive/", Bonfire.PanDoRa.Web do
        pipe_through(:browser)
        pipe_through(:account_required)
      end

      # pages you need to view as a user
      scope "/archive/", Bonfire.PanDoRa.Web do
        pipe_through(:browser)
        pipe_through(:user_required)

        post("/connect", ConnectPandoraController, :create)
        live("/movies/:id", MovieLive)
        live("/my_lists/", MyListsLive)
        live("/featured_lists/", FeaturedListsLive)
        get("/lists", RedirectController, :to_my_lists)
        live("/lists/:id", ListLive)

        # Media proxy: forwards image and video requests to Pandora with auth
        get("/media/*path", ProxyController, :proxy_image)
        get("/video/*path", ProxyController, :proxy_video)
      end

      # pages only admins can view
      scope "/archive/admin", Bonfire.PanDoRa.Web do
        pipe_through(:browser)
        pipe_through(:admin_required)
      end
    end
  end
end
