# Run `intent-a90`

![traffic model check](intent-a90-traffic-model.png)

## Traffic model check (slice A)

| Quantity | Samples | My mean | 3GPP model mean | KS test |
| --- | --- | --- | --- | --- |
| Frame size (B) | 660 | 62333 | 62500 | D=0.035, p=0.38 |
| Frame jitter (ms) | 660 | -0.00 | 0.00 | D=0.018, p=0.98 |
| Frame inter-arrival (ms) | 658 | 16.66 | 16.67 | D=0.020, p=0.95 (two-sample) |
| Packet size (B) | 29715 | 1384 | 1385 | n/a |
| Packet inter-arrival (ms) | 29713 | 0.369 | 0.369 | n/a |

p > 0.05: no evidence that my generator differs from the model.

## Per-slice KPIs (FlowMonitor)

| Slice | Flows | Throughput (Mbps) | Mean delay (ms) | p95 delay (ms) | Loss (%) |
| --- | --- | --- | --- | --- | --- |
| A | 2 | 61.23 | 1.758 | 3.00 | 0.00 |
| B | 2 | 0.51 | 0.923 | 1.00 | 0.00 |

## Slice B SLA

- p95 delay 1.00 ms vs target 10 ms: met
- loss 0.00 % vs target 1 %: met
- **Verdict: SLA met** (intent `a90` was accepted by the capacity-only check)
