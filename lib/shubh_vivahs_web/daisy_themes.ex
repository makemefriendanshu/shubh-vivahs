defmodule ShubhVivahsWeb.DaisyThemes do
  @moduledoc """
  Names of every daisyUI theme enabled via `themes: all;` in app.css
  (built-in preset order, with our bespoke "light"/"dark" overrides first).
  """

  @themes ~w(
    light dark cupcake bumblebee emerald corporate synthwave retro cyberpunk
    valentine halloween garden forest aqua lofi pastel fantasy wireframe
    black luxury dracula cmyk autumn business acid lemonade night coffee
    winter dim nord sunset caramellatte abyss silk
  )

  def themes, do: @themes
end
