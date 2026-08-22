# Research: Stripe test-mode mechanics

Umbrella design doc: issue #1 ("BuJo SaaS learning app"). Planning ticket: issue #4 ("Research: Stripe test-mode mechanics").

Scope: what a real Stripe **test-mode** integration actually requires for a SaaS app with simple plan gating (free tier vs one paid tier). All claims below are sourced from Stripe's own docs (docs.stripe.com), fetched directly — no third-party tutorials.

A terminology note up front: Stripe's current docs increasingly say "**sandbox**" rather than "test mode" — every account ships with one built-in **test mode sandbox** (uses `sk_test_`/`pk_test_` keys, can't be deleted, shares some settings with live mode) plus the ability to create additional named sandboxes (up to 5, fully isolated settings). For this project's purposes "test mode" == the default test mode sandbox and its `_test_` keys; that's still the mechanism this doc describes. (["Testing use cases"](https://docs.stripe.com/testing-use-cases))

## What you actually need to build

- **Checkout approach**: Use **Stripe Checkout** (the hosted/embedded Checkout Sessions API), not raw Stripe Elements/Payment Intents. Stripe's own docs explicitly recommend Checkout Sessions "for most integrations" and call Payment Intents a lower-level API that "requires significantly more code and ongoing maintenance" — reserve it for cases needing full custom checkout UI ownership. Stripe's own SaaS-subscriptions guide builds the whole flow on Stripe-hosted Checkout. (["Compare the Checkout Sessions and Payment Intents APIs"](https://docs.stripe.com/payments/checkout-sessions-and-payment-intents-comparison), ["Sell subscriptions as a SaaS startup"](https://docs.stripe.com/get-started/use-cases/saas-subscriptions))
- **Minimal essential webhook set** for a free/paid-tier SaaS: `checkout.session.completed` (new subscription purchased — provision access), `invoice.paid` (recurring renewal succeeded — keep access active), `invoice.payment_failed` (renewal failed — notify/handle dunning), plus `customer.subscription.updated` and `customer.subscription.deleted` (plan changes and cancellations) to keep gating state in sync with subscription status changes. Stripe's own minimal SaaS guide lists exactly the first three as the "monitor at minimum" set. (["Sell subscriptions as a SaaS startup" § Monitor your subscriptions](https://docs.stripe.com/get-started/use-cases/saas-subscriptions), ["Using webhooks with subscriptions"](https://docs.stripe.com/billing/subscriptions/webhooks))
- **Gating pattern**: webhook-driven state stored in your own database — never poll Stripe live per request. Store a customer's access/expiration state in your DB, update it from webhook events (e.g., set an expiration timestamp on `invoice.paid`), and check that local state at login/request time. Stripe's fulfillment docs are blunt about this: "Webhooks are required for fulfillment" because you can't rely on the client-side redirect landing page alone. (["Fulfill orders"](https://docs.stripe.com/checkout/fulfillment), ["Using webhooks with subscriptions" § Track active subscriptions](https://docs.stripe.com/billing/subscriptions/webhooks))
- **Signature verification is non-negotiable**: every webhook handler must verify the `Stripe-Signature` header against a per-endpoint signing secret (`whsec_...`) using the SDK's `constructEvent`/`Webhook.construct_event` — never process a webhook body without it. (["Receive Stripe events in your webhook endpoint" § Secure your endpoint](https://docs.stripe.com/webhooks))
- **Test/live separation**: test and live mode are fully separate data universes (separate keys, separate objects, separate webhook endpoints and separate signing secrets even on the same URL) — flipping to live is mostly "swapping your API keys" plus re-registering webhook endpoints and completing account activation/business verification. Nothing about the app's *code* needs to change if built correctly against the SDK. (["API keys" § Switch to live mode](https://docs.stripe.com/keys), ["Go-live checklist"](https://docs.stripe.com/get-started/checklist/go-live))

---

## 1. Checkout flow options: Stripe Checkout vs Stripe Elements

Stripe's own comparison page frames this as **Checkout Sessions API vs Payment Intents API** (Elements is the UI-component layer that can sit in front of either):

> "We recommend the Checkout Sessions API for most integrations. Checkout Sessions allows you to build both a basic payment collection integration and complex checkout flows." … "If you use PaymentIntents, you must manually build equivalent features in your code, including discount logic, tax calculation, and currency conversion." … "Choose PaymentIntents only if you want to own every part of your checkout, and rebuild these capabilities yourself."
> — ["Compare the Checkout Sessions and Payment Intents APIs"](https://docs.stripe.com/payments/checkout-sessions-and-payment-intents-comparison)

Stripe's own feature-comparison table on that page (verbatim structure) covers exactly the tradeoffs this ticket asked about:

| Feature | Checkout Sessions API | Payment Intents API |
|---|---|---|
| Design | Complete checkout flows, one-time or complex (line items, taxes, shipping, subscriptions) | Lower-level; you implement all checkout logic yourself |
| Tax calculation | Built in (Stripe Tax) | Separate Tax API integration required |
| Subscriptions | Built-in subscription creation | Separate Subscriptions integration required |
| Coupons/discounts | Built in | Manual |
| UI flexibility | Hosted page, embedded forms, and custom UI (Elements) | Custom UI only |
| Webhook events | "Webhook events for the complete checkout lifecycle" | "Payment status events only" |

Source: ["Compare the Checkout Sessions and Payment Intents APIs"](https://docs.stripe.com/payments/checkout-sessions-and-payment-intents-comparison)

On integration effort and PCI scope specifically: Checkout is a Stripe-hosted or Stripe-embedded UI, so Stripe owns the compliance surface — "Stripe provides a globally compliant interface and handles requirements for displaying mandates and consent notices to customers," and Stripe.js "tokenizes sensitive payment details within an Element without ever having them touch your server" even when you use Elements directly. (["Stripe Web Elements"](https://docs.stripe.com/payments/elements))

**For a learning-project SaaS with a simple free/paid tier split**, Stripe's own SaaS-startup guide builds the entire reference integration on Stripe-hosted Checkout (`ui_mode` defaults to a full Stripe-hosted page): "The payment flow redirects your customers to a Stripe-hosted page to enter their payment details, then returns them to your site. You use Checkout to create the Stripe-hosted page, which calls the Checkout Sessions API." (["Sell subscriptions as a SaaS startup"](https://docs.stripe.com/get-started/use-cases/saas-subscriptions))

**Bottom line for this project**: Stripe Checkout (Checkout Sessions API, hosted page) is simpler — less code, no PCI-scope custom form to build, tax/discount/subscription logic built in, and Stripe explicitly recommends it as the default for "most integrations." Elements/Payment Intents is the right call only if a later ticket needs a fully custom-branded, in-page payment form; that tradeoff is Stripe's own stated one, not a third-party opinion.

## 2. Webhook events for subscription lifecycle

Stripe's dedicated subscriptions-webhooks doc lists the full event surface (table reproduced selectively; full list is longer — includes `subscription_schedule.*` events not relevant to a flat-rate single-paid-tier app):

| Event | Description (Stripe's own wording) |
|---|---|
| `customer.subscription.created` | "Sent when the subscription is created. The subscription `status` might be `incomplete` if customer authentication is required…" |
| `customer.subscription.updated` | "Sent when a subscription starts or changes. For example, renewing a subscription, adding a coupon, applying a discount, adding an invoice item, and changing plans all trigger this event." |
| `customer.subscription.deleted` | "Sent when a customer's subscription ends." |
| `customer.subscription.paused` / `.resumed` | Sent on trial-without-payment-method pause/resume flows. |
| `customer.subscription.trial_will_end` | "Sent 3 days before the trial period ends. If the trial is less than 3 days, this event is triggered." |
| `invoice.paid` | "Sent when the invoice is successfully paid. You can provision access to your product when you receive this event and the subscription `status` is `active`." |
| `invoice.payment_failed` | "A payment for an invoice failed… you can take several possible actions: Notify the customer… Configure Smart Retries…" |
| `invoice.upcoming` | "Sent a few days prior to the renewal of the subscription." |
| `invoice.created` / `invoice.finalized` / `invoice.finalization_failed` | Invoice lifecycle plumbing; `invoice.created` non-response delays finalization up to 72 hours. |

Source: ["Using webhooks with subscriptions"](https://docs.stripe.com/billing/subscriptions/webhooks)

Guidance on trial handling from the same page: "A few days before a trial ends and the subscription moves from `trialing` to `active`, you receive a `customer.subscription.trial_will_end` event. When you receive this event, verify that you have a payment method on the customer so you can bill them." (["Using webhooks with subscriptions" § Catch subscription status changes](https://docs.stripe.com/billing/subscriptions/webhooks))

For **checkout completion specifically**, the event is `checkout.session.completed`: "When someone pays you, it creates a `checkout.session.completed` event. Set up an endpoint on your server to accept, process, and confirm receipt of these events." (["Fulfill orders"](https://docs.stripe.com/checkout/fulfillment))

**Stripe's own minimum viable set for a SaaS startup** (their words, not an inference) is narrower than the full table above:

> "Monitor the following events at minimum (for more events, see Subscription webhooks): `checkout.session.completed` — 'Sent when a customer successfully completes checkout, informing you of a new purchase' → provision the subscription. `invoice.paid` — 'Sent each billing period when a payment succeeds' → continue to provision the subscription each period. `invoice.payment_failed` — 'Sent each billing period if there's an issue with your customer's payment method' → notify the customer and direct them to the customer portal."
> — ["Sell subscriptions as a SaaS startup" § Monitor your subscriptions](https://docs.stripe.com/get-started/use-cases/saas-subscriptions)

For a free-vs-paid gating model, add `customer.subscription.updated` and `customer.subscription.deleted` to that minimum set so plan downgrades/cancellations flip the user back to the free tier — these are the two events Stripe's subscriptions-webhooks page identifies as the ones that actually change a subscription's status (see status table cited in §3 below), and the "catch subscription status changes" guidance says explicitly: "When a subscription changes to `canceled` or `unpaid`, revoke access to your product." (["Using webhooks with subscriptions" § Catch subscription status changes](https://docs.stripe.com/billing/subscriptions/webhooks))

Stripe also warns that **event delivery order is not guaranteed**: "Stripe doesn't guarantee the delivery of events in the order that they're generated… Make sure that your event destination isn't dependent on receiving events in a specific order." (["Receive Stripe events in your webhook endpoint" § Event ordering](https://docs.stripe.com/webhooks))

## 3. Server-side plan/tier gating

Stripe's explicit recommendation is **webhook-driven state in your own database**, not live polling of the Stripe API per request:

> "For typical integrations, you store customers' credentials and a mapped timestamp value that represents the access expiration date for that customer on your site when a customer subscribes. When the customer logs in, you check whether the timestamp is still in the future… When the subscription renews, Stripe bills the customer… Stripe notifies your site of the invoice status by sending a webhook event: 1. Your site receives an `invoice.paid` event… 3. Your application updates the customer's access expiration date in your database to the appropriate date in the future (plus a day or two for leeway)."
> — ["Using webhooks with subscriptions" § Track active subscriptions](https://docs.stripe.com/billing/subscriptions/webhooks)

The fulfillment guide is even more direct about *why* the client-side redirect (and by extension any request-time live check) isn't sufficient on its own:

> "**Webhooks are required for fulfillment.** You can't rely on triggering fulfillment only from your checkout landing page, because it's not guaranteed customers visit that page. For example, a customer can pay successfully and then lose their internet connection before your landing page loads. Automatic fulfillment with webhooks is required if you sell subscriptions…"
> — ["Fulfill orders"](https://docs.stripe.com/checkout/fulfillment)

That guide also specifies the fulfillment function must be **idempotent**, since webhooks can be retried/duplicated: "Perform fulfillment only once per payment. Because of how this integration and the internet work, your `fulfill_checkout` function might be called multiple times, possibly concurrently, for the same Checkout Session." Recommended pattern: retrieve the Checkout Session from the API, check `payment_status`, perform fulfillment, then "record fulfillment status for this Checkout Session" in your own store so repeat deliveries are no-ops. (["Fulfill orders" § Create a fulfillment function](https://docs.stripe.com/checkout/fulfillment))

Practical status-to-access mapping from Stripe's status table (drives what "gated" should mean in the DB): `trialing`/`active` → grant access; `past_due` → notify, optionally still grant briefly while retries run; `canceled`/`unpaid` → revoke access ("Revoke access to your product when the subscription is `unpaid` because payments were already attempted and retried while `past_due`."). (["Using webhooks with subscriptions" § Catch subscription status changes](https://docs.stripe.com/billing/subscriptions/webhooks))

Stripe also has a purpose-built feature for this exact problem — **Entitlements** — referenced from the SaaS guide's webhook table ("Use entitlements to provision the subscription") and its own webhook event `entitlements.active_entitlement_summary.updated`: "Sent when a customer's active entitlements are updated. When you receive this event, you can provision or de-provision access to your product's features." This is still webhook-driven, just with Stripe computing the entitlement state for you rather than you deriving it from raw subscription/invoice events. (["Using webhooks with subscriptions"](https://docs.stripe.com/billing/subscriptions/webhooks), ["Sell subscriptions as a SaaS startup" § Monitor your subscriptions](https://docs.stripe.com/get-started/use-cases/saas-subscriptions)) — for a learning-project scope, deriving gating state directly from `invoice.paid`/`customer.subscription.updated`/`.deleted` into your own `users`/`subscriptions` table is simpler than adopting Entitlements as a separate concept, and is exactly the pattern the "Track active subscriptions" section above describes.

## 4. Webhook signature verification

Every registered webhook endpoint gets its own signing secret, and Stripe's docs are explicit that skipping verification is a real attack surface:

> "Without verification, an attacker could send fake webhook events to your endpoint to trigger actions like fulfilling orders, granting account access, or modifying records. Always verify that webhook events originate from Stripe before acting on them."
> — ["Receive Stripe events in your webhook endpoint" § Verify events are sent from Stripe](https://docs.stripe.com/webhooks)

Mechanics of the `Stripe-Signature` header:

> "The `Stripe-Signature` header included in each signed event contains a timestamp and one or more signatures that you must verify. The timestamp has a `t=` prefix, and each signature has a scheme prefix. Schemes start with `v`, followed by an integer. Currently, the only valid live signature scheme is `v1`. To aid with testing, Stripe sends an additional signature with a fake `v0` scheme, for test events." Example: `t=1492774577,v1=5257a869...,v0=6ffbb59b...`. "Stripe generates signatures using a hash-based message authentication code (HMAC) with SHA-256."
> — ["Receive Stripe events in your webhook endpoint" § Verify manually](https://docs.stripe.com/webhooks)

Recommended approach is the SDK helper, not manual HMAC code:

> "We recommend using our official libraries to verify signatures. You perform the verification by providing the event payload, the `Stripe-Signature` header, and the endpoint's secret." (Ruby example shown: `Stripe::Webhook.construct_event(payload, sig_header, endpoint_secret)`, raising `Stripe::SignatureVerificationError` on failure.) "Stripe requires the raw body of the request to perform signature verification. If you're using a framework, make sure it doesn't manipulate the raw body. Any manipulation to the raw body of the request causes the verification to fail."
> — ["Receive Stripe events in your webhook endpoint" § Verify with official libraries](https://docs.stripe.com/webhooks)

Replay-attack protection is built into the same check: "Stripe includes a timestamp in the `Stripe-Signature` header… Our libraries have a default tolerance of 5 minutes between the timestamp and the current time… Don't use a tolerance value of `0`. Using a tolerance value of `0` disables the recency check entirely." (["Receive Stripe events in your webhook endpoint" § Preventing replay attacks](https://docs.stripe.com/webhooks))

Operational notes relevant to this project: "If you use the same endpoint for both test and live API keys, the secret is different for each one" — so a single webhook URL used in both modes needs two secrets configured (one per mode) — and Stripe recommends periodically rolling secrets, with a 24-hour dual-secret grace window during rotation. (["Receive Stripe events in your webhook endpoint" § Retrieving your endpoint's secret / Roll endpoint signing secrets periodically](https://docs.stripe.com/webhooks))

Belt-and-suspenders: Stripe also recommends **IP allowlisting** alongside signature verification, since it publishes a fixed list of sending IPs. (["Receive Stripe events in your webhook endpoint" § Verify events are sent from Stripe](https://docs.stripe.com/webhooks))

## 5. Test mode → live mode

**API keys.** Every account gets test and live versions of publishable, secret, and restricted keys:

> "Build and test: Use your sandbox (test) keys. Sandbox keys start with `pk_test_` for publishable keys, `rk_test_` for restricted keys, and `sk_test_` for secret keys. They let you test without affecting live data. When you're ready to accept real payments: Switch to your live mode keys, which start with `pk_live_`, `rk_live_`, and `sk_live_`."
> — ["API keys"](https://docs.stripe.com/keys)

The key itself — not any separate account-level toggle — is what determines the mode of a given request: "Each mode has its own set of API keys, and objects in one mode aren't accessible to the other. For example, a sandbox product object can't be part of a live mode payment." (["API keys" § Sandbox versus live mode](https://docs.stripe.com/keys))

**Switching**: "When you're ready to accept real payments, use live mode API keys instead of sandbox (test) keys. On the API keys page, toggle from sandbox mode to live mode… Switching API keys is only one step. Review the full go-live checklist to make sure your integration is production ready." (["API keys" § Switch to live mode](https://docs.stripe.com/keys))

**Webhook signing secrets change too, per endpoint**: "If you use webhooks, update each webhook endpoint's URL and copy the new signing secret from the Webhooks section of the Dashboard." (["API keys" § Switch to live mode](https://docs.stripe.com/keys))

**Data is fully separate and does not migrate**: "Stripe objects created in a sandbox environment — such as plans, coupons, products, and SKUs — aren't usable in live mode. This prevents your test data from being inadvertently used in your production code. When recreating necessary objects in live mode, be sure to use the same ID values (for example, the same plan ID, not the same name) to guarantee your code continues to work without issue." (["Go-live checklist"](https://docs.stripe.com/get-started/checklist/go-live))

**Webhook endpoints must be re-registered for live mode**, and Stripe explicitly calls this out as its own checklist item, not something that carries over automatically: "Your Stripe account can have both test and live webhook endpoints. If you're using webhooks, make sure you've defined live endpoints in your Stripe account. Then confirm that the live endpoint functions exactly the same as your test endpoint." Same checklist also flags handling delayed/duplicate webhook deliveries and not depending on delivery order — as production concerns, not just test-mode niceties. (["Go-live checklist"](https://docs.stripe.com/get-started/checklist/go-live))

**Account activation / business verification is required before live mode works at all.** From Stripe's own SaaS guide's "Go live" section: "In the Dashboard, open your Account settings. Enter your business type, tax details, business details, personal verification information, and customer-facing information… Add bank details to confirm where to pay out your money. Set up two-step authentication to secure your account… Review the information you entered, and click Agree and submit. After you activate your profile, Stripe updates you from sandbox mode to live mode." (["Sell subscriptions as a SaaS startup" § Go live](https://docs.stripe.com/get-started/use-cases/saas-subscriptions))

Other go-live checklist items worth carrying into a design ticket: pin/confirm the API version your integration relies on, review error handling for every Stripe error type (not just the common ones), keep your own logs as a backup independent of Stripe's Dashboard logs, and rotate API keys before going live in case they were ever exposed during development. (["Go-live checklist"](https://docs.stripe.com/get-started/checklist/go-live))

**Sandbox vs. the built-in "test mode sandbox," for completeness**: Stripe's testing docs distinguish the one built-in, undeletable "test mode sandbox" every account has (shares some settings with live mode — a Dashboard notice warns when a change there also affects live settings) from additional named sandboxes you can create (up to 5, fully isolated settings, deletable). Both use `_test_`-prefixed keys and the same test card numbers; card networks/payment providers never process real payments in either. (["Testing use cases"](https://docs.stripe.com/testing-use-cases))

---

### Citation coverage

Every factual claim above is inline-cited to a specific `docs.stripe.com` page fetched directly during this research pass. No claim relies on unstated model knowledge. Pages consulted:

- https://docs.stripe.com/payments/checkout-sessions-and-payment-intents-comparison
- https://docs.stripe.com/payments/elements
- https://docs.stripe.com/get-started/use-cases/saas-subscriptions
- https://docs.stripe.com/billing/subscriptions/webhooks
- https://docs.stripe.com/checkout/fulfillment
- https://docs.stripe.com/webhooks
- https://docs.stripe.com/keys
- https://docs.stripe.com/get-started/checklist/go-live
- https://docs.stripe.com/testing-use-cases
