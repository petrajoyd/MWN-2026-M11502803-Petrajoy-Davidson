# Run `intent-a70-heavyB`

![traffic model check](intent-a70-heavyB-traffic-model.png)

## Traffic model check (slice A)

| Quantity | Samples | My mean | 3GPP model mean | KS test |
| --- | --- | --- | --- | --- |
| Frame size (B) | 660 | 62333 | 62500 | D=0.035, p=0.38 |
| Frame jitter (ms) | 660 | -0.00 | 0.00 | D=0.018, p=0.98 |
| Frame inter-arrival (ms) | 658 | 16.66 | 16.67 | D=0.021, p=0.93 (two-sample) |
| Packet size (B) | 29715 | 1384 | 1385 | n/a |
| Packet inter-arrival (ms) | 29713 | 0.369 | 0.369 | n/a |

p > 0.05: no evidence that my generator differs from the model.

## Per-slice KPIs (FlowMonitor)

| Slice | Flows | Throughput (Mbps) | Mean delay (ms) | p95 delay (ms) | Loss (%) |
| --- | --- | --- | --- | --- | --- |
| A | 2 | 61.22 | 2.089 | 3.70 | 0.00 |
| B | 2 | 41.14 | 0.876 | 1.10 | 0.01 |

## Slice B SLA

- p95 delay 1.10 ms vs target 10 ms: met
- loss 0.01 % vs target 1 %: met
- **Verdict: SLA met** (intent `a70-heavyB` was accepted by the capacity-only check)
