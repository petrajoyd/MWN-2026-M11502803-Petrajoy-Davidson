| Slice | Model | Expected rate | Measured rate (mean ± sd over flows) | Expected pkt/s | Measured pkt/s | Pkt size | Flows |
| --- | --- | --- | --- | --- | --- | --- | --- |
| MTC | 4-state semi-Markov, Poisson inside a state | 16.8 kbit/s | 17.8 kbit/s ± 7.0 kbit/s | 21 | 22.3 | 100 B (model 100 B) | 60 |
| VoIP | Poisson, mean 20 ms | 12.8 kbit/s | 12.8 kbit/s ± 0.6 kbit/s | 50 | 50.1 | 32 B (model 32 B) | 60 |
| Video | 30 fps, truncated Pareto frame size, 1400 B packets | 14.25 Mbit/s | 14.23 Mbit/s ± 0.40 Mbit/s | 30 frames/s | 1285.1 | 1384 B | 40 |

Window 2–12 s of every run (10 runs). MTC time share per state (model) = 40%, 20%, 20%, 20%. Video: nominal 15 Mbit/s; the Pareto cap at 4x the mean trims the tail, so the model mean is 14.25 Mbit/s.
