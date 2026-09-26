defmodule PhoenixHologramWeb.Hologram.Pages.UpgradePage do
  @moduledoc """
  Explains what upgrading to Premium unlocks — Admin View — using the
  same `@admin_steps` copy and numbered-card layout as HowItWorksPage's
  "The Admin View" column (duplicated here rather than shared, matching
  how `@engine_steps` is already duplicated between HowItWorksPage and
  PremierExperiencePage in this codebase). A different pricing model
  from PricingPage's video/storage/hours bands, aimed at the "Get
  Premium" upsell from DashboardPage rather than the initial
  video-count band choice.

  This does carry a real UPI QR code + VPA supplied by the site owner for
  manual collection — the amount-tier buttons update the displayed
  amount and the `upi://pay` deep link's `am` param; the QR image itself
  is a static photo of the owner's real UPI QR (it does not encode a
  live amount, since it's not generated from the VPA at request time),
  so a scan opens the payer's UPI app pointed at the right account
  without a pre-filled amount.

  There is now a semi-automated confirmation path alongside the manual
  "message us on WhatsApp" one: a companion Android app reads incoming
  bank SMS notifications, extracts the paid amount, and forwards it to
  `PhoenixHologramWeb.PaymentChannel` over `PaymentSocket`, which
  rebroadcasts it through `Hologram.Realtime.broadcast_action/3` to every
  page subscribed on `{:payment_received, amount}` — see `init/3` below.
  This page subscribes to all four tiers up front (subscriptions can
  only be set up server-side, in `init/3` or a command, not from the
  client-side `:select_amount` action that changes which tier is
  showing) and shows the "paid" state only when a confirmed amount
  matches whatever `@selected_amount` currently is. Matching is
  amount-only, not per-visitor (there's no account system to scope it
  to) — two people paying the same tier at once would both see
  confirmation. Accepted as a known gap for now.

  The "Know the founder personally?" free-access form no longer grants
  anything on submission — it creates a `"pending"` row in
  `PhoenixHologram.PromoRequests` (see the `:generate_promo_code`
  command) and opens a WhatsApp message so the owner knows to review it.
  Approving a request on `PromoRequestsPage` is
  what actually grants the tier, through the exact same PaymentStore +
  realtime broadcast path a real UPI payment uses, so an approved
  request is indistinguishable from a payment to the logic above.

  A logged-in superuser (`Accounts.premium?/1`) is treated as already
  unlocked for every tier, same as a confirmed payment or an approved
  promo request — see `@premium?` in `init/3` and `already_unlocked?/4`.
  This page stays reachable while logged out (no
  `RequireAuthenticatedUser` middleware), so the current user is looked
  up directly from `server.user_id` rather than via that middleware's
  stash, and is simply `nil` for an anonymous visitor.
  """

  use Hologram.Page
  use Hologram.JS

  alias Hologram.UI.Link
  alias PhoenixHologram.Accounts
  alias PhoenixHologramWeb.Hologram.Pages.AdminMoviesPage
  alias PhoenixHologramWeb.Hologram.Pages.DashboardPage
  alias PhoenixHologramWeb.Hologram.Pages.HowItWorksPage

  @upi_vpa "anshumannie-2@okhdfcbank"
  # Pre-encoded ("anshu man" with the space as %20) rather than calling
  # URI.encode_www_form/1 at render time — that module isn't confirmed
  # supported by Hologram's client-side Elixir-to-JS compiler yet, and
  # this is a fixed, known string anyway.
  @upi_payee_name_encoded "anshu%20man"

  @amount_tiers [501, 1501, 3501, 6001]

  # Same band names/video counts as PricingPage's @bands (duplicated
  # rather than shared, matching this file's other duplicated copy) —
  # shown inline here so a visitor sees what each amount tier is called
  # without navigating away to /pricing.
  @band_plans [
    %{amount: 501, name: "Standard", videos: "5 videos"},
    %{amount: 1501, name: "Silver", videos: "20 videos"},
    %{amount: 3501, name: "Gold", videos: "50 videos"},
    %{amount: 6001, name: "Platinum", videos: "100 videos"}
  ]

  # Same copy as HowItWorksPage's @admin_steps — see this module's doc.
  @admin_steps [
    %{
      icon: "hero-key",
      title: "Open Admin View",
      body: "Switch to Admin View on any film to see the full scene-by-scene breakdown."
    },
    %{
      icon: "hero-pencil-square",
      title: "Edit Event Details",
      body: "Rename the film and set its description, event date, and location."
    },
    %{
      icon: "hero-users",
      title: "Manage Recognised Faces",
      body: "Review every unique face the AI clustered, with its own thumbnail and timestamps."
    },
    %{
      icon: "hero-adjustments-horizontal",
      title: "Watch The Votes Live",
      body: "Follow viewer votes update in real time as the leading face for each scene shifts."
    }
  ]

  route "/upgrade"

  layout PhoenixHologramWeb.Hologram.Layouts.DefaultLayout

  @doc "Exposes the valid amount tiers so PaymentChannel can validate against the same list, rather than duplicating it."
  def amount_tiers, do: @amount_tiers

  def init(_params, component, server) do
    user = server.user_id && Accounts.get_user(server.user_id)

    component =
      component
      |> put_state(:premium?, Accounts.premium?(user))
      |> put_state(:admin_steps, @admin_steps)
      |> put_state(:amount_tiers, @amount_tiers)
      |> put_state(:band_plans, @band_plans)
      |> put_state(:selected_amount, List.first(@amount_tiers))
      |> put_state(:paid_amount, nil)
      |> put_state(:checking_payment?, false)
      |> put_state(:checked_amount, nil)
      |> put_state(:promo_description, "")
      |> put_state(:promo_error?, false)
      |> put_state(:promo_code, nil)
      |> put_state(:promo_status, nil)
      |> put_state(:status_check_code, "")
      |> put_state(:status_check_error?, false)
      |> put_state(:checking_code?, false)

    server = Enum.reduce(@amount_tiers, server, &put_subscription(&2, {:payment_received, &1}))

    {component, server}
  end

  def action(:select_amount, params, component) do
    put_state(component, :selected_amount, params.amount)
  end

  # Dispatched via Hologram.Realtime.broadcast_action/3 from PaymentChannel
  # when the companion Android app reports a matching UPI payment. Expands
  # the (closed-by-default) "Pay With UPI" accordion so a visitor who
  # already paid and navigated away from it actually sees the confirmation.
  def action(:payment_confirmed, params, component) do
    JS.exec("""
    const details = document.getElementById('pay');
    if (details) { details.open = true; }
    """)

    put_state(component, :paid_amount, params.amount)
  end

  # "Confirm Payment" button — an explicit, on-demand check alongside the
  # passive live push above, for a visitor who paid before opening this
  # page, missed the live push, or just wants to be sure.
  def action(:confirm_payment_clicked, params, component) do
    component
    |> put_state(:checking_payment?, true)
    |> put_state(:checked_amount, nil)
    |> put_command(:check_payment_status,
      amount: params.amount,
      promo_code: component.state.promo_code
    )
  end

  def action(:payment_check_result, params, component) do
    component = put_state(component, :checking_payment?, false)
    component = put_state(component, :checked_amount, params.amount)

    component =
      if params.promo_status do
        put_state(component, :promo_status, params.promo_status)
      else
        component
      end

    if params.paid? do
      put_state(component, :paid_amount, params.amount)
    else
      component
    end
  end

  def action(:update_promo_description, params, component) do
    put_state(component, :promo_description, params.event.value)
  end

  # "Free acquaintance privilege" — someone who knows the site owner
  # personally describes their relation (e.g. "cousin", "college
  # roommate, roll no. 42") instead of paying. This no longer grants
  # anything by itself: it creates a "pending" PromoRequest (see
  # PhoenixHologram.PromoRequests) and opens a pre-filled WhatsApp
  # message to the owner so they know to go review it. Only an explicit
  # approval on PromoRequestsPage actually
  # grants the tier, via the same PaymentStore + realtime broadcast path
  # a real UPI payment uses — see PromoRequests.approve_promo_request/1.
  def action(:generate_promo_code_clicked, params, component) do
    if String.trim(component.state.promo_description) == "" do
      put_state(component, :promo_error?, true)
    else
      component
      |> put_state(:promo_error?, false)
      |> put_command(:generate_promo_code,
        description: component.state.promo_description,
        amount: params.amount
      )
    end
  end

  def action(:promo_code_generated, params, component) do
    JS.exec("""
    const details = document.getElementById('pay');
    if (details) { details.open = true; }
    window.open(#{inspect(params.whatsapp_url)}, '_blank');
    """)

    component
    |> put_state(:promo_status, "pending")
    |> put_state(:promo_code, params.code)
  end

  # Dispatched via Hologram.Realtime.broadcast_action/3 from
  # PromoRequests.approve_promo_request/1 or reject_promo_request/1, on
  # the {:promo_status, code} channel this page subscribed to when the
  # code was generated (see command(:generate_promo_code, ...) below).
  # Expands the accordion so a rejection is actually seen, not just
  # silently updated in state.
  def action(:promo_status_updated, params, component) do
    JS.exec("""
    const details = document.getElementById('pay');
    if (details) { details.open = true; }
    """)

    put_state(component, :promo_status, params.status)
  end

  def action(:update_status_check_code, params, component) do
    put_state(component, :status_check_code, params.event.value)
  end

  # "Have a code already?" lookup — the only client-side state tying a
  # visitor to their submitted request is `@promo_code`/`@promo_status`,
  # which reset to nil on every fresh page load (nothing is persisted
  # client-side, e.g. in localStorage). Re-entering the code recovers
  # both the current status and, since command(:check_code_status, ...)
  # re-subscribes on {:promo_status, code}, future live updates for it
  # in this new page session too.
  def action(:check_code_status_clicked, _params, component) do
    code = String.trim(component.state.status_check_code)

    if code == "" do
      put_state(component, :status_check_error?, true)
    else
      component
      |> put_state(:checking_code?, true)
      |> put_state(:status_check_error?, false)
      |> put_command(:check_code_status, code: code)
    end
  end

  def action(:code_status_result, params, component) do
    component = put_state(component, :checking_code?, false)

    if params.found? do
      component
      |> put_state(:promo_code, params.code)
      |> put_state(:promo_status, params.status)
      |> put_state(:status_check_error?, false)
      |> put_state(:selected_amount, params.amount)
      |> maybe_mark_paid(params.status, params.amount)
    else
      put_state(component, :status_check_error?, true)
    end
  end

  defp maybe_mark_paid(component, "approved", amount), do: put_state(component, :paid_amount, amount)
  defp maybe_mark_paid(component, _status, _amount), do: component

  def command(:check_code_status, %{code: code}, server) do
    case PhoenixHologram.PromoRequests.get_by_code(code) do
      nil ->
        put_action(server, :code_status_result, code: code, found?: false)

      request ->
        server = put_subscription(server, {:promo_status, code})

        put_action(server,
          :code_status_result,
          code: code,
          found?: true,
          status: request.status,
          amount: request.amount
        )
    end
  end

  def command(:check_payment_status, %{amount: amount, promo_code: promo_code}, server) do
    paid? = PhoenixHologram.PaymentStore.recently_paid?(amount)

    promo_status =
      if promo_code, do: PhoenixHologram.PromoRequests.get_status_by_code(promo_code)

    put_action(server,
      :payment_check_result,
      amount: amount,
      paid?: paid?,
      promo_status: promo_status
    )
  end

  def command(:generate_promo_code, %{description: description, amount: amount}, server) do
    code = generate_code()

    PhoenixHologram.PromoRequests.create_promo_request(%{
      description: description,
      amount: amount,
      code: code
    })

    # Lets this specific submission be notified of its own approval or
    # rejection live (see action(:promo_status_updated, ...)), scoped by
    # the unique generated code rather than the shared amount-tier
    # channel — the only per-visitor-ish identity available without a
    # real account system.
    server = put_subscription(server, {:promo_status, code})

    message =
      "Free access request (pending review)\nRelation: #{description}\nAmount tier: Rs.#{amount}\nCode: #{code}"

    whatsapp_url = "https://wa.me/919880538028?text=#{URI.encode_www_form(message)}"

    put_action(server, :promo_code_generated, code: code, amount: amount, whatsapp_url: whatsapp_url)
  end

  defp generate_code do
    "FC-" <> (:crypto.strong_rand_bytes(3) |> Base.encode16())
  end

  # Plain lookup rather than a regex-based thousands-separator formatter —
  # Hologram's client-side Elixir-to-JS compiler only has partial Regex
  # support so far, and @amount_tiers is a short fixed list anyway.
  defp format_amount(501), do: "501"
  defp format_amount(1501), do: "1,501"
  defp format_amount(3501), do: "3,501"
  defp format_amount(6001), do: "6,001"
  defp format_amount(amount), do: Integer.to_string(amount)

  defp upi_link(amount) do
    "upi://pay?pa=#{@upi_vpa}&pn=#{@upi_payee_name_encoded}&am=#{amount}&cu=INR"
  end

  # True once the currently selected tier is unlocked by any means — a
  # superuser account, an approved promo request, or a confirmed payment
  # (real UPI or a promo request approved while a different tier was
  # selected, which also sets @paid_amount). Disables "Know the founder
  # personally?" so a visitor who already has this tier isn't prompted
  # to request it again.
  defp already_unlocked?(_promo_status, _paid_amount, _selected_amount, true = _premium?), do: true

  defp already_unlocked?(promo_status, paid_amount, selected_amount, false = _premium?) do
    promo_status == "approved" or paid_amount == selected_amount
  end

  def template do
    ~HOLO"""
    <div class="min-h-screen p-6">
      <div class="max-w-3xl mx-auto">
        <div class="flex items-center justify-center gap-3 mb-1">
          <svg viewBox="0 0 24 40" class="w-4 h-8 text-primary/70" fill="none" stroke="currentColor" stroke-width="1.2">
            <path d="M12 2c-6 6-6 20 0 36" />
            <circle cx="10" cy="10" r="2.5" fill="currentColor" stroke="none" opacity="0.55" />
          </svg>
          <h1 class="font-display text-xl sm:text-3xl text-center">
            Upgrade To Premium &amp; Unlock Your Legacy
          </h1>
          <svg viewBox="0 0 24 40" class="w-4 h-8 text-primary/70 -scale-x-100" fill="none" stroke="currentColor" stroke-width="1.2">
            <path d="M12 2c-6 6-6 20 0 36" />
            <circle cx="10" cy="10" r="2.5" fill="currentColor" stroke="none" opacity="0.55" />
          </svg>
        </div>
        <p class="text-center text-sm text-base-content/60 mb-6">
          Upgrading unlocks Admin View on your film — here's what that gives you.
        </p>

        {%if @premium?}
          <div class="text-center mb-8">
            <span class="badge badge-success badge-lg gap-1">
              <span class="hero-check-badge w-4 h-4"></span>
              Premium Unlocked — Superuser Account
            </span>
          </div>
        {%else}
          <div class="text-center mb-8">
            <a href="#pay" class="btn btn-primary gap-2">
              <span class="hero-lock-open w-4 h-4"></span>
              Unlock Legacy Features Now
            </a>
          </div>
        {/if}

        <h2 class="font-display text-lg text-center mb-4 badge badge-lg bg-secondary text-secondary-content border-secondary px-6 py-4 w-full">
          The Admin View
        </h2>
        <div class="flex flex-col gap-4">
          {%for {step, index} <- Enum.with_index(@admin_steps, 1)}
            <div class="card card-stock shadow-xl">
              <div class="card-body flex-row items-center gap-4 py-4">
                <div class="relative shrink-0">
                  <div class="w-14 h-14 rounded-box bg-secondary/10 border-2 border-secondary/40 flex items-center justify-center">
                    <span class={"#{step.icon} w-7 h-7 text-secondary"}></span>
                  </div>
                  <span class="absolute -top-2 -left-2 w-6 h-6 rounded-full bg-secondary text-secondary-content font-display text-xs flex items-center justify-center shadow ring-2 ring-base-100">
                    {index}
                  </span>
                </div>
                <div>
                  <p class="font-display text-sm uppercase tracking-wide">{step.title}</p>
                  <p class="text-sm text-base-content/70 mt-1">{step.body}</p>
                </div>
              </div>
            </div>
          {/for}
        </div>
        <div class="text-center mt-4">
          <Link to={AdminMoviesPage} class="btn btn-secondary btn-sm">Open Admin View</Link>
        </div>

        <details id="pay" class="mt-10 collapse collapse-arrow card-stock shadow-xl scroll-mt-6">
          <summary class="collapse-title font-display text-lg text-center">Pay With UPI</summary>
          <div class="collapse-content flex flex-col items-center text-center">
            <p class="text-sm text-base-content/50">Looking for a plan by video count instead?</p>
            <div class="flex flex-wrap justify-center gap-2 mt-2">
              {%for plan <- @band_plans}
                <span class="badge badge-outline badge-sm">
                  {plan.name} &#8377;{format_amount(plan.amount)} &middot; {plan.videos}
                </span>
              {/for}
            </div>

            <p class="text-sm text-base-content/60 mt-3 mb-2">Choose an amount, then scan or tap to pay</p>

            <div class="join">
              {%for tier <- @amount_tiers}
                <button
                  $click={:select_amount, amount: tier}
                  class={
                    if tier == @selected_amount do
                      "join-item btn btn-sm btn-primary"
                    else
                      "join-item btn btn-sm btn-outline"
                    end
                  }
                >
                  &#8377;{format_amount(tier)}
                </button>
              {/for}
            </div>

            <p class="font-display text-2xl mt-4">
              &#8377;{format_amount(@selected_amount)}
            </p>

            {%if @paid_amount == @selected_amount}
              <div class="alert alert-success mt-3 max-w-xs">
                <span class="hero-check-circle w-5 h-5"></span>
                {%if @promo_code}
                  <span>Free access granted (code {@promo_code}) — your Premium access is being activated.</span>
                {%else}
                  <span>Payment received — your Premium access is being activated.</span>
                {/if}
              </div>
            {/if}

            <img
              src="/images/upi-qr.jpeg"
              alt="UPI QR code — scan with any UPI app to pay"
              class="w-56 h-auto rounded-box shadow mt-2 border border-primary/30"
            />
            <p class="text-xs text-base-content/50 mt-1">
              UPI ID: anshumannie-2@okhdfcbank
            </p>

            <a href={upi_link(@selected_amount)} class="btn btn-primary gap-2 mt-4">
              <span class="hero-lock-open w-4 h-4"></span>
              Pay &#8377;{format_amount(@selected_amount)} In Your UPI App
            </a>
            <p class="text-xs text-base-content/50 mt-1 max-w-xs">
              The tap-to-pay button only works on a phone with a UPI app installed — on desktop, scan the QR instead. Either way, the amount isn't pre-filled on scan, so please enter it yourself once your UPI app opens.
            </p>

            <button
              $click={:confirm_payment_clicked, amount: @selected_amount}
              disabled={@paid_amount == @selected_amount}
              class="btn btn-outline btn-sm gap-2 mt-4"
            >
              {%if @checking_payment?}
                <span class="loading loading-spinner loading-xs"></span>
                Checking...
              {%else}
                <span class="hero-arrow-path w-4 h-4"></span>
                Confirm Payment
              {/if}
            </button>

            {%if @checked_amount == @selected_amount && @paid_amount != @selected_amount}
              <div class="alert alert-warning mt-3 max-w-xs">
                <span class="hero-exclamation-triangle w-5 h-5"></span>
                <span>No matching payment found yet — this can take a minute. Try again shortly, or message us on WhatsApp below.</span>
              </div>
            {/if}

            <div class="gold-divider w-16 my-4"></div>

            <p class="font-display text-sm">Know the founder personally?</p>
            <p class="text-xs text-base-content/50 mb-2 max-w-xs">
              {%if already_unlocked?(@promo_status, @paid_amount, @selected_amount, @premium?)}
                This tier is already unlocked — no need to request free access too.
              {%else}
                Describe your relation and request free access to this tier — subject to the founder's review, not automatic.
              {/if}
            </p>
            <textarea
              $change="update_promo_description"
              value={@promo_description}
              placeholder="e.g. cousin, college roommate + roll number"
              rows="2"
              disabled={already_unlocked?(@promo_status, @paid_amount, @selected_amount, @premium?)}
              class="textarea textarea-bordered w-full max-w-xs text-sm"
            />
            {%if @promo_error?}
              <p class="text-xs text-error mt-1">Please describe your relation first.</p>
            {/if}
            <button
              $click={:generate_promo_code_clicked, amount: @selected_amount}
              disabled={already_unlocked?(@promo_status, @paid_amount, @selected_amount, @premium?)}
              class="btn btn-outline btn-sm gap-2 mt-2"
            >
              <span class="hero-gift w-4 h-4"></span>
              Request Free Access
            </button>

            {%if @promo_status == "pending" && @paid_amount != @selected_amount}
              <div class="alert alert-info mt-3 max-w-xs">
                <span class="hero-clock w-5 h-5"></span>
                <span>Request submitted (code {@promo_code}) — pending the founder's review. Check back with Confirm Payment above once approved.</span>
              </div>
            {/if}

            {%if @promo_status == "rejected"}
              <div class="alert alert-error mt-3 max-w-xs">
                <span class="hero-x-circle w-5 h-5"></span>
                <span>Your free-access request (code {@promo_code}) was declined. You can still pay via UPI above, or submit a new request describing your relation.</span>
              </div>
            {/if}

            <div class="gold-divider w-16 my-4"></div>

            <p class="font-display text-sm">Have a code already?</p>
            <p class="text-xs text-base-content/50 mb-2 max-w-xs">
              If you reloaded the page or came back later, re-enter your code to see its live status.
            </p>
            <div class="join">
              <input
                type="text"
                $change="update_status_check_code"
                value={@status_check_code}
                placeholder="e.g. FC-A1B2C3"
                disabled={@paid_amount == @selected_amount}
                class="join-item input input-bordered input-sm w-40 text-center"
              />
              <button
                $click="check_code_status_clicked"
                disabled={@paid_amount == @selected_amount}
                class="join-item btn btn-sm btn-outline gap-2"
              >
                {%if @checking_code?}
                  <span class="loading loading-spinner loading-xs"></span>
                {%else}
                  <span class="hero-magnifying-glass w-4 h-4"></span>
                {/if}
                Check
              </button>
            </div>
            {%if @status_check_error?}
              <p class="text-xs text-error mt-1">
                {%if @status_check_code == ""}
                  Please enter a code first.
                {%else}
                  No request found with that code.
                {/if}
              </p>
            {/if}

            {%if @promo_code && !@status_check_error?}
              <p class="text-xs text-base-content/60 mt-2">
                Code <span class="font-mono">{@promo_code}</span> status:
                <span class={
                  case @promo_status do
                    "approved" -> "badge badge-success badge-sm"
                    "rejected" -> "badge badge-error badge-sm"
                    _ -> "badge badge-warning badge-sm"
                  end
                }>
                  {@promo_status}
                </span>
              </p>
            {/if}

            <div class="gold-divider w-16 my-4"></div>

            <a
              href="https://wa.me/919880538028"
              target="_blank"
              rel="noopener noreferrer"
              class="link link-hover text-sm"
            >
              Message us your payment screenshot on WhatsApp to confirm &rarr;
            </a>
          </div>
        </details>

        <div class="flex flex-wrap items-center justify-center gap-x-6 gap-y-2 mt-8 text-xs text-base-content/60">
          <span class="flex items-center gap-1">
            <span class="hero-shield-check w-4 h-4 text-primary"></span>
            Secure &amp; Private
          </span>
          <span class="flex items-center gap-1">
            <span class="hero-film w-4 h-4 text-primary"></span>
            Professional Curation
          </span>
          <span class="flex items-center gap-1">
            <span class="hero-link w-4 h-4 text-primary"></span>
            Custom Shareable Link
          </span>
        </div>

        <div class="text-center mt-6">
          <Link to={HowItWorksPage} class="link link-hover text-sm">
            See the full guide to browsing, admin &amp; scene focus &rarr;
          </Link>
        </div>

        <div class="flex flex-col items-center gap-3 mt-6">
          <Link to={DashboardPage} class="btn btn-outline btn-block gap-2">
            <span class="hero-arrow-right-end-on-rectangle w-4 h-4"></span>
            Back To Dashboard
          </Link>
        </div>
      </div>
    </div>
    """
  end
end
