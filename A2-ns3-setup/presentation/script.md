# A2 Presentation Script (10 minutes)

**Deck:** [A2-ns3-setup-traffic-model.pptx](A2-ns3-setup-traffic-model.pptx) · **Target:** ~1 minute per slide, about 1 250 words, 120 to 140 words per minute. The same text is in each slide's speaker notes.

**One message:** my simulator is running and it already shows the problem of my project: an intent can fit in the carrier and still break another slice.

| # | Slide | Time |
| --- | --- | --- |
| 1 | Title | 0:30 |
| 2 | Does "it fits" mean "it is safe"? | 1:00 |
| 3 | Setup and what broke | 1:15 |
| 4 | The 3GPP XR video model | 1:00 |
| 5 | Why I did not use the built-in generator | 1:00 |
| 6 | The scenario: an intent loop in ns-3 | 1:00 |
| 7 | Verifying my traffic model | 1:15 |
| 8 | Proof on the wire | 0:50 |
| 9 | Four intents, one SLA violation | 1:15 |
| 10 | Take-aways and next steps | 0:55 |

---

## 1. Title (0:30)

Hello everyone. I am Petrajoy, and this is my A2: ns-3 setup and traffic model.

My project is about intent-based management for O-RAN slicing. So instead of a generic first scenario, I built the testbed my project needs. In the next ten minutes I will show that the simulator runs, that my traffic model matches the 3GPP model, and that this setup already reproduces the problem I want to solve.

## 2. Does "it fits" mean "it is safe"? (1:00)

Quick reminder of the problem from A1.

An operator writes an intent, for example: give the video slice ninety percent of the carrier. The system translates it into a configuration and enacts it automatically, with no human in the loop.

Before enacting, today's pipelines usually run one check: does the request fit in the cell's capacity? If the shares add up and every slice still gets some resource blocks, the intent is accepted.

My question is whether "it fits" also means "it is safe" for the other slices. In this assignment I built exactly this loop, intent, capacity check, enactment, measurement, in ns-3, so I can test that question with numbers.

## 3. Setup and what broke (1:15)

The setup. I run ns-3 version 3.48 with the 5G-LENA NR module, version 5.1, which is the release paired with 3.48. It runs on my lab VM: Ubuntu 22.04, eight virtual CPUs, sixteen gigabytes of RAM. The full build has about two thousand four hundred targets and took fifty-three minutes.

Four things broke, and they are all in my study note.

One: I cloned everything as root, and ns-3 refuses to build as root. I moved the tree to my normal user.

Two: ns-3.48 needs CMake 3.25, but Ubuntu 22.04 ships 3.22. I installed a newer CMake for my user only, so nothing else on the VM changed.

Three: the 5G-LENA README still shows old install commands. I followed its compatibility table instead.

Four: Wireshark labelled my video packets as a protocol called TAPA, because it uses the same UDP port 5000. I disabled that dissector.

## 4. The 3GPP XR video model (1:00)

For traffic, I used the XR video model of 3GPP TR 26.926. One note: 26.926 is a technical report, not a technical specification. Its video model comes from TR 38.838.

The model is simple. Sixty frames per second at thirty megabits per second. The frame size is a truncated Gaussian: mean 62.5 kilobytes, standard deviation 10.5 percent, cut at fifty and one hundred fifty percent. Each frame also has a jitter, a truncated Gaussian with a standard deviation of two milliseconds, cut at plus or minus four.

From this I can predict what I should see: frames every 16.7 milliseconds give or take the jitter, and since I cut each frame into packets of at most 1400 bytes, about forty-five packets per frame, sent back to back.

## 5. Why I did not use the built-in generator (1:00)

5G-LENA already has a generator for this model, so my first plan was to use it. But when I read its source code, it does not match the table.

The biggest issue: it sets the variance of the frame size to 0.105 times the mean, instead of the standard deviation. So the spread of the frame size is about 81 bytes instead of about 6 500. The frames are almost constant.

It also uses a jitter range of plus or minus two milliseconds instead of four, it adds the jitter to every gap so the frame times drift like a random walk, and the jitter is in whole milliseconds.

So I wrote my own generator, XrVideoApp. I used AI to help write it, and then I checked every parameter against the table myself, and checked the output against the model, which is the next part.

## 6. The scenario: an intent loop in ns-3 (1:00)

This is the scenario. An intent is a small JSON file: the bandwidth share of slice A, the number of users, the traffic, and the SLA of slice B.

A Python script runs the capacity-only check, translates the intent into ns-3 arguments, and runs the simulation.

In ns-3 there is one gNB at 28 gigahertz with one hundred megahertz, split into two bandwidth parts. Bandwidth part zero is slice A: two users receiving my XR video, thirty megabits each. Bandwidth part one is slice B, the low-latency slice, mapped to 5QI 80. Its SLA is a ninety-fifth percentile delay of ten milliseconds, from the 5QI 80 delay budget, and at most one percent loss.

At the end I get a FlowMonitor file, a log of every packet I sent, and a PCAP, and a second script turns them into plots and an SLA verdict.

## 7. Verifying my traffic model (1:15)

First, is my traffic really the 3GPP model?

Blue is my run, orange is the model. The top row is the frame size, PDF and CDF. The second row is the frame inter-arrival time. The bottom rows are the packet size and the packet inter-arrival time.

For the three random quantities I ran a Kolmogorov-Smirnov test against the model. Frame size: p equals 0.38. Jitter: 0.98. Frame inter-arrival: 0.95. All far above 0.05, so there is no evidence that my generator differs from the model. The means also match: 62.3 kilobytes against 62.5, and 16.66 milliseconds against 16.67.

The packet curves look strange, but they are expected: almost every packet is 1400 bytes with one smaller remainder per frame, and almost every gap is zero because the packets of a frame leave together.

## 8. Proof on the wire (0:50)

Second, is it really on the network? I captured the link from the server into the core and opened it in Wireshark.

The I/O graph shows one spike per video frame. Most spikes are about five hundred kilobits, which is exactly one frame of 62.5 kilobytes. The taller ones are two users' frames in the same millisecond. The flat line at the bottom is slice B.

And the three sources agree packet for packet: Wireshark, FlowMonitor, and my own send log all count 29 715 video packets.

## 9. Four intents, one SLA violation (1:15)

Now the main result. I enacted four intents. All four passed the capacity-only check.

With a seventy-thirty split and a light slice B, everything is fine. With ninety-ten and a light slice B, still fine: slice B only needs about half a megabit.

Then I made slice B heavier, forty megabits in total. At seventy-thirty it is still fine: one point one milliseconds at the ninety-fifth percentile.

But at ninety-ten with the heavy slice B, the ninety-fifth percentile delay is 12.7 milliseconds, above the ten-millisecond budget, and ten percent of its packets are not delivered. The SLA is violated, and the capacity check accepted it.

So the same split is safe or harmful depending on slice B's load. A check that only looks at the shares cannot see that.

## 10. Take-aways and next steps (0:55)

Three take-aways.

One: ns-3.48 with 5G-LENA runs on my VM, and the setup is documented, including what broke.

Two: my XR video generator matches the 3GPP model, checked with PDFs, CDFs, KS tests, and Wireshark.

Three: the capacity-only check accepts an intent that breaks slice B's SLA, and whether an intent is harmful depends on the victim's load, not only on the share.

The limits: one seed and six seconds per run so far. Next, in A3 I pick the baseline paper. In A4 I sweep the share and the load with at least ten seeds. And for the final project, I build the QoS-aware check that should reject intents like the last one.

Thank you. I am happy to take questions.
