locals {
  openclaw_enabled = trimspace(var.openclaw_gateway_token) != ""

  openclaw_scrape_configs = local.openclaw_enabled ? [
    {
      job_name        = "openclaw"
      scrape_interval = "30s"
      metrics_path    = "/api/diagnostics/prometheus"
      authorization = {
        credentials_file = "/etc/prometheus/secrets/${kubernetes_secret.openclaw_gateway_token.metadata[0].name}/token"
      }
      static_configs = [
        {
          targets = [var.openclaw_target]
        }
      ]
    }
  ] : []

  openclaw_rules_map = local.openclaw_enabled ? {
    openclaw = {
      groups = [
        {
          name = "openclaw"
          rules = [
            {
              alert  = "OpenClawGatewayDown"
              expr   = "up{job=\"openclaw\"} == 0"
              for    = "5m"
              labels = { severity = "critical" }
              annotations = {
                summary     = "OpenClaw gateway {{ $labels.instance }} is unreachable"
                description = "No metrics for 5 minutes. The VM or gateway is down, the diagnostics-prometheus plugin is disabled, or the gateway token changed."
              }
            },
            {
              alert  = "OpenClawSessionStuck"
              expr   = "sum(increase(openclaw_session_stuck_total[15m])) > 0"
              labels = { severity = "warning" }
              annotations = {
                summary = "OpenClaw reported a stuck session in the last 15 minutes"
              }
            },
            {
              alert  = "OpenClawMemoryPressure"
              # The warning level fires at a hardcoded 1.5 GiB RSS, which the gateway sits around during normal use.
              expr   = "sum(increase(openclaw_memory_pressure_total{level=\"critical\"}[15m])) > 0"
              labels = { severity = "warning" }
              annotations = {
                summary = "OpenClaw reported critical memory pressure in the last 15 minutes"
              }
            }
          ]
        }
      ]
    }
  } : {}

  openclaw_panels = [
    { title = "Gateway up", type = "stat", unit = "none", x = 0, y = 0, w = 6, h = 4, targets = [{ expr = "up{job=\"openclaw\"}", legend = "up" }] },
    { title = "Runs (24h)", type = "stat", unit = "short", x = 6, y = 0, w = 6, h = 4, targets = [{ expr = "sum(increase(openclaw_run_completed_total[24h]))", legend = "runs" }] },
    { title = "Tokens (24h)", type = "stat", unit = "short", x = 12, y = 0, w = 6, h = 4, targets = [{ expr = "sum(increase(openclaw_model_tokens_total[24h]))", legend = "tokens" }] },
    { title = "Cost (24h)", type = "stat", unit = "currencyUSD", x = 18, y = 0, w = 6, h = 4, targets = [{ expr = "sum(increase(openclaw_model_cost_usd_total[24h]))", legend = "USD" }] },
    { title = "Runs per minute by outcome", type = "timeseries", unit = "short", x = 0, y = 4, w = 12, h = 8, targets = [{ expr = "sum by (outcome) (rate(openclaw_run_completed_total[5m])) * 60", legend = "{{outcome}}" }] },
    { title = "Run duration p95 by model", type = "timeseries", unit = "s", x = 12, y = 4, w = 12, h = 8, targets = [{ expr = "histogram_quantile(0.95, sum by (le, model) (rate(openclaw_run_duration_seconds_bucket[5m])))", legend = "{{model}}" }] },
    { title = "Tokens per minute by model", type = "timeseries", unit = "short", x = 0, y = 12, w = 12, h = 8, targets = [{ expr = "sum by (model, token_type) (rate(openclaw_model_tokens_total[5m])) * 60", legend = "{{model}} {{token_type}}" }] },
    { title = "Model calls per minute by outcome", type = "timeseries", unit = "short", x = 12, y = 12, w = 12, h = 8, targets = [{ expr = "sum by (model, outcome) (rate(openclaw_model_call_total[5m])) * 60", legend = "{{model}} {{outcome}}" }] },
    { title = "Tool executions per minute", type = "timeseries", unit = "short", x = 0, y = 20, w = 12, h = 8, targets = [{ expr = "sum by (tool) (rate(openclaw_tool_execution_total[5m])) * 60", legend = "{{tool}}" }] },
    { title = "Messages per minute by channel", type = "timeseries", unit = "short", x = 12, y = 20, w = 12, h = 8, targets = [{ expr = "sum by (channel) (rate(openclaw_message_received_total[5m])) * 60", legend = "{{channel}}" }] },
    { title = "Gateway memory", type = "timeseries", unit = "bytes", x = 0, y = 28, w = 12, h = 8, targets = [{ expr = "openclaw_memory_bytes{kind=~\"rss|heap_used\"}", legend = "{{kind}}" }] },
    { title = "Event loop delay p99 (window max)", type = "timeseries", unit = "s", x = 12, y = 28, w = 12, h = 8, targets = [{ expr = "histogram_quantile(0.99, sum by (le) (rate(openclaw_gateway_event_loop_delay_max_seconds_bucket[5m])))", legend = "p99" }] },
  ]
}

resource "kubernetes_secret" "openclaw_gateway_token" {
  metadata {
    name      = "openclaw-gateway-token"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }

  data = {
    token = trimspace(var.openclaw_gateway_token)
  }
}

# Picked up by the Grafana dashboard sidecar through the grafana_dashboard label.
resource "kubernetes_config_map" "openclaw_dashboard" {
  metadata {
    name      = "openclaw-dashboard"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
    labels = {
      grafana_dashboard = "1"
    }
  }

  data = {
    "openclaw.json" = jsonencode({
      title         = "OpenClaw"
      uid           = "openclaw"
      schemaVersion = 39
      refresh       = "1m"
      time          = { from = "now-24h", to = "now" }
      panels = [
        for i, p in local.openclaw_panels : {
          id         = i + 1
          title      = p.title
          type       = p.type
          datasource = { type = "prometheus", uid = "prometheus" }
          gridPos    = { x = p.x, y = p.y, w = p.w, h = p.h }
          fieldConfig = {
            defaults  = { unit = p.unit }
            overrides = []
          }
          targets = [
            for j, t in p.targets : {
              refId        = substr("ABCDEFGHIJ", j, 1)
              datasource   = { type = "prometheus", uid = "prometheus" }
              expr         = t.expr
              legendFormat = t.legend
            }
          ]
        }
      ]
    })
  }
}
