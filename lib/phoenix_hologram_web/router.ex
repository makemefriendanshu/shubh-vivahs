defmodule PhoenixHologramWeb.Router do
  use PhoenixHologramWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PhoenixHologramWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :require_superuser do
    plug PhoenixHologramWeb.Plugs.RequireSuperuser
  end

  scope "/", PhoenixHologramWeb do
    pipe_through :browser

    get "/premiere/videos/:id", VideoController, :show
    get "/premiere/videos/:id/thumbnail", MovieThumbnailController, :show
    get "/premiere/videos/:id/download", VideoController, :download
    get "/premiere/videos/:id/download/:part", VideoController, :download_chunk
    get "/premiere/videos/:id/play/:part", VideoController, :play_chunk
  end

  scope "/", PhoenixHologramWeb do
    pipe_through [:browser, :require_superuser]

    get "/admin/faces/:id/thumbnail", FaceThumbnailController, :show
    get "/admin/analytics/export.csv", AdminAnalyticsCsvController, :export
  end

  # Other scopes may use custom stacks.
  # scope "/api", PhoenixHologramWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:phoenix_hologram, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: PhoenixHologramWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
