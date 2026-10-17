/*
 * A2 - ns-3 Setup & Traffic Model
 * Petrajoy Davidson (M11502803), Multimedia Wireless Networks 2026
 *
 * Two-slice 5G NR downlink (5G-LENA v5.1, ns-3.48). Each slice is one bandwidth part (BWP).
 * The bandwidth split between the slices comes from an intent (see intent_enact.py), so this
 * run is the "enact -> measure" half of the intent loop in my A1 proposal.
 *
 *   Slice A (eMBB, 5QI 9, BWP 0): XR/cloud video, 3GPP TR 26.926 / TR 38.838 video model
 *                                 implemented in XrVideoApp below.
 *   Slice B (low latency, 5QI 80, BWP 1): small periodic packets (UdpClient).
 *
 * Outputs (in --outputDir):
 *   <simTag>-tx.csv        one row per slice-A packet: time, UE, frame id, sizes, jitter
 *   <simTag>-flowmon.xml   FlowMonitor stats with delay/jitter/size histograms
 *   <simTag>-kpi.txt       per-flow and per-slice throughput, delay, loss
 *   <simTag>-rh-*.pcap     remote host link capture (open in Wireshark)
 *
 * Built from contrib/nr/examples/cttc-nr-demo.cc (5g-lena-v5.1.y).
 */

#include "ns3/antenna-module.h"
#include "ns3/applications-module.h"
#include "ns3/config-store-module.h"
#include "ns3/core-module.h"
#include "ns3/flow-monitor-module.h"
#include "ns3/internet-apps-module.h"
#include "ns3/internet-module.h"
#include "ns3/mobility-module.h"
#include "ns3/nr-module.h"
#include "ns3/point-to-point-module.h"

#include <cmath>
#include <fstream>
#include <map>

using namespace ns3;

NS_LOG_COMPONENT_DEFINE("A2IntentSlicing");

/*
 * XrVideoApp: 3GPP XR video traffic (TR 38.838 V17.0.0 Sec. 5.1.1, used by TR 26.926).
 *
 *   frame rate        F (default 60 fps)
 *   frame size        truncated Gaussian, mean R/F/8 bytes, STD 10.5 %, range [50 %, 150 %]
 *   frame jitter      truncated Gaussian, mean 0, STD 2 ms, range [-4, +4] ms
 *   frame k arrives   at k/F + J_k   (jitter around a fixed grid, not accumulated)
 *   packetisation     each frame is cut into UDP payloads of at most MaxPayload bytes,
 *                     sent back to back
 *
 * Truncation is done by rejection sampling, which gives exactly the truncated distribution.
 */
class XrVideoApp : public Application
{
  public:
    static TypeId GetTypeId();

    XrVideoApp() = default;
    ~XrVideoApp() override = default;

    void Configure(Address remote,
                   double rateMbps,
                   double fps,
                   double stdRatio,
                   double minRatio,
                   double maxRatio,
                   double jitterStdMs,
                   double jitterBoundMs,
                   uint32_t maxPayload,
                   uint32_t ueId,
                   std::ofstream* log);

    int64_t AssignStreams(int64_t stream);

  private:
    void StartApplication() override;
    void StopApplication() override;
    void ScheduleFrame();
    void SendFrame(uint64_t frameId, double jitterMs);
    double SampleTruncated(Ptr<NormalRandomVariable> rv, double lo, double hi);

    Ptr<Socket> m_socket;
    Address m_remote;
    double m_meanFrameBytes{0};
    double m_fps{60};
    double m_minRatio{0.5};
    double m_maxRatio{1.5};
    double m_jitterBoundMs{4};
    uint32_t m_maxPayload{1400};
    uint32_t m_ueId{0};
    std::ofstream* m_log{nullptr};

    Ptr<NormalRandomVariable> m_frameSize;
    Ptr<NormalRandomVariable> m_jitter;
    Time m_t0;
    uint64_t m_nextFrame{0};
    EventId m_event;
};

NS_OBJECT_ENSURE_REGISTERED(XrVideoApp);

TypeId
XrVideoApp::GetTypeId()
{
    static TypeId tid = TypeId("ns3::XrVideoApp")
                            .SetParent<Application>()
                            .SetGroupName("Applications")
                            .AddConstructor<XrVideoApp>();
    return tid;
}

void
XrVideoApp::Configure(Address remote,
                      double rateMbps,
                      double fps,
                      double stdRatio,
                      double minRatio,
                      double maxRatio,
                      double jitterStdMs,
                      double jitterBoundMs,
                      uint32_t maxPayload,
                      uint32_t ueId,
                      std::ofstream* log)
{
    m_remote = remote;
    m_fps = fps;
    m_meanFrameBytes = rateMbps * 1e6 / fps / 8.0;
    m_minRatio = minRatio;
    m_maxRatio = maxRatio;
    m_jitterBoundMs = jitterBoundMs;
    m_maxPayload = maxPayload;
    m_ueId = ueId;
    m_log = log;

    // NormalRandomVariable takes the variance, not the STD.
    double frameStd = stdRatio * m_meanFrameBytes;
    m_frameSize = CreateObject<NormalRandomVariable>();
    m_frameSize->SetAttribute("Mean", DoubleValue(m_meanFrameBytes));
    m_frameSize->SetAttribute("Variance", DoubleValue(frameStd * frameStd));

    m_jitter = CreateObject<NormalRandomVariable>();
    m_jitter->SetAttribute("Mean", DoubleValue(0.0));
    m_jitter->SetAttribute("Variance", DoubleValue(jitterStdMs * jitterStdMs));
}

int64_t
XrVideoApp::AssignStreams(int64_t stream)
{
    m_frameSize->SetStream(stream);
    m_jitter->SetStream(stream + 1);
    return 2;
}

double
XrVideoApp::SampleTruncated(Ptr<NormalRandomVariable> rv, double lo, double hi)
{
    while (true)
    {
        double v = rv->GetValue();
        if (v >= lo && v <= hi)
        {
            return v;
        }
    }
}

void
XrVideoApp::StartApplication()
{
    m_socket = Socket::CreateSocket(GetNode(), UdpSocketFactory::GetTypeId());
    m_socket->Bind();
    m_socket->Connect(m_remote);
    // Leave room for the first frame's negative jitter.
    m_t0 = Simulator::Now() + Seconds(m_jitterBoundMs * 1e-3);
    m_nextFrame = 0;
    ScheduleFrame();
}

void
XrVideoApp::StopApplication()
{
    Simulator::Cancel(m_event);
    if (m_socket)
    {
        m_socket->Close();
    }
}

void
XrVideoApp::ScheduleFrame()
{
    uint64_t k = m_nextFrame++;
    double jitterMs = SampleTruncated(m_jitter, -m_jitterBoundMs, m_jitterBoundMs);
    Time when = m_t0 + Seconds(k / m_fps + jitterMs * 1e-3);
    Time delay = when > Simulator::Now() ? when - Simulator::Now() : Time(0);
    m_event = Simulator::Schedule(delay, &XrVideoApp::SendFrame, this, k, jitterMs);
}

void
XrVideoApp::SendFrame(uint64_t frameId, double jitterMs)
{
    auto frameBytes = static_cast<uint32_t>(std::lround(SampleTruncated(m_frameSize,
                                                                        m_minRatio * m_meanFrameBytes,
                                                                        m_maxRatio * m_meanFrameBytes)));
    uint32_t nPkts = (frameBytes + m_maxPayload - 1) / m_maxPayload;
    uint32_t left = frameBytes;
    for (uint32_t i = 0; i < nPkts; ++i)
    {
        uint32_t sz = std::min(left, m_maxPayload);
        left -= sz;
        m_socket->Send(Create<Packet>(sz));
        if (m_log)
        {
            *m_log << Simulator::Now().GetNanoSeconds() << ",A," << m_ueId << "," << frameId << ","
                   << i << "," << nPkts << "," << sz << "," << frameBytes << "," << jitterMs
                   << "\n";
        }
    }
    ScheduleFrame();
}

struct SliceKpi
{
    uint64_t txPackets{0};
    uint64_t rxPackets{0};
    uint64_t rxBytes{0};
    double delaySumS{0};
    double jitterSumS{0};
};

int
main(int argc, char* argv[])
{
    // Intent-derived parameters (filled by intent_enact.py)
    std::string intentId = "manual";
    double totalBandwidth = 100e6; // Hz, shared by the two slices
    double sliceAShare = 0.5;      // fraction of totalBandwidth given to slice A
    uint16_t uesSliceA = 2;
    uint16_t uesSliceB = 2;

    // Slice A traffic: TR 26.926 / TR 38.838 XR video
    double videoRateMbps = 30;
    double videoFps = 60;
    double frameStdRatio = 0.105;
    double frameMinRatio = 0.5;
    double frameMaxRatio = 1.5;
    double jitterStdMs = 2;
    double jitterBoundMs = 4;
    uint32_t maxPayload = 1400;

    // Slice B traffic: low-latency periodic packets
    uint32_t llPacketBytes = 100;
    double llPeriodMs = 4;

    // Radio
    uint16_t numerology = 2;
    double centralFrequencyA = 28.0e9;
    double centralFrequencyB = 28.4e9;
    double totalTxPower = 35;

    Time simTime = Seconds(6);
    Time appStart = MilliSeconds(500);
    std::string simTag = "a2";
    std::string outputDir = ".";
    bool pcap = true;

    CommandLine cmd(__FILE__);
    cmd.AddValue("intentId", "Id of the intent being enacted (for the output files)", intentId);
    cmd.AddValue("totalBandwidth", "Bandwidth shared by both slices (Hz)", totalBandwidth);
    cmd.AddValue("sliceAShare", "Share of totalBandwidth given to slice A (0..1)", sliceAShare);
    cmd.AddValue("uesSliceA", "UEs in slice A (video)", uesSliceA);
    cmd.AddValue("uesSliceB", "UEs in slice B (low latency)", uesSliceB);
    cmd.AddValue("videoRateMbps", "Slice A mean video rate per UE (Mbps)", videoRateMbps);
    cmd.AddValue("videoFps", "Slice A frame rate (fps)", videoFps);
    cmd.AddValue("frameStdRatio", "Frame size STD / mean", frameStdRatio);
    cmd.AddValue("frameMinRatio", "Frame size lower bound / mean", frameMinRatio);
    cmd.AddValue("frameMaxRatio", "Frame size upper bound / mean", frameMaxRatio);
    cmd.AddValue("jitterStdMs", "Frame jitter STD (ms)", jitterStdMs);
    cmd.AddValue("jitterBoundMs", "Frame jitter bound, range is [-b, +b] (ms)", jitterBoundMs);
    cmd.AddValue("maxPayload", "Max UDP payload per packet (bytes)", maxPayload);
    cmd.AddValue("llPacketBytes", "Slice B packet size (bytes)", llPacketBytes);
    cmd.AddValue("llPeriodMs", "Slice B packet period (ms)", llPeriodMs);
    cmd.AddValue("numerology", "Numerology of both BWPs", numerology);
    cmd.AddValue("totalTxPower", "gNB power (dBm), split in proportion to bandwidth", totalTxPower);
    cmd.AddValue("simTime", "Simulation time", simTime);
    cmd.AddValue("appStart", "Start time of the applications", appStart);
    cmd.AddValue("simTag", "Prefix of the output files", simTag);
    cmd.AddValue("outputDir", "Output directory", outputDir);
    cmd.AddValue("pcap", "Write a PCAP of the remote host link", pcap);
    cmd.Parse(argc, argv);

    NS_ABORT_MSG_IF(sliceAShare <= 0 || sliceAShare >= 1, "sliceAShare must be in (0, 1)");
    double bandwidthA = totalBandwidth * sliceAShare;
    double bandwidthB = totalBandwidth - bandwidthA;

    Config::SetDefault("ns3::NrRlcUm::MaxTxBufferSize", UintegerValue(999999999));

    // Topology: 1 gNB, UEs placed randomly in a 3 m x 3 m area around it (as cttc-nr-demo)
    GridScenarioHelper gridScenario;
    gridScenario.SetRows(1);
    gridScenario.SetColumns(1);
    gridScenario.SetHorizontalBsDistance(10.0);
    gridScenario.SetVerticalBsDistance(10.0);
    gridScenario.SetBsHeight(10);
    gridScenario.SetUtHeight(1.5);
    gridScenario.SetSectorization(GridScenarioHelper::SINGLE);
    gridScenario.SetBsNumber(1);
    gridScenario.SetUtNumber(uesSliceA + uesSliceB);
    gridScenario.SetScenarioHeight(3);
    gridScenario.SetScenarioLength(3);
    gridScenario.CreateScenario();

    NodeContainer ueA;
    NodeContainer ueB;
    for (uint32_t j = 0; j < gridScenario.GetUserTerminals().GetN(); ++j)
    {
        (j < uesSliceA ? ueA : ueB).Add(gridScenario.GetUserTerminals().Get(j));
    }

    Ptr<NrPointToPointEpcHelper> nrEpcHelper = CreateObject<NrPointToPointEpcHelper>();
    Ptr<IdealBeamformingHelper> beamformingHelper = CreateObject<IdealBeamformingHelper>();
    Ptr<NrHelper> nrHelper = CreateObject<NrHelper>();
    nrHelper->SetBeamformingHelper(beamformingHelper);
    nrHelper->SetEpcHelper(nrEpcHelper);

    // Spectrum: one band per slice, one CC and one BWP per band.
    // BWP 0 = slice A, BWP 1 = slice B. The intent sets their widths.
    CcBwpCreator ccBwpCreator;
    CcBwpCreator::SimpleOperationBandConf bandConfA(centralFrequencyA, bandwidthA, 1);
    CcBwpCreator::SimpleOperationBandConf bandConfB(centralFrequencyB, bandwidthB, 1);
    OperationBandInfo bandA = ccBwpCreator.CreateOperationBandContiguousCc(bandConfA);
    OperationBandInfo bandB = ccBwpCreator.CreateOperationBandContiguousCc(bandConfB);

    Ptr<NrChannelHelper> channelHelper = CreateObject<NrChannelHelper>();
    channelHelper->ConfigureFactories("UMi", "Default", "ThreeGpp");
    channelHelper->SetChannelConditionModelAttribute("UpdatePeriod", TimeValue(MilliSeconds(0)));
    channelHelper->SetPathlossAttribute("ShadowingEnabled", BooleanValue(false));
    channelHelper->AssignChannelsToBands({bandA, bandB});
    BandwidthPartInfoPtrVector allBwps = CcBwpCreator::GetAllBwps({bandA, bandB});

    beamformingHelper->SetAttribute("BeamformingMethod",
                                    TypeIdValue(DirectPathBeamforming::GetTypeId()));
    nrEpcHelper->SetAttribute("S1uLinkDelay", TimeValue(MilliSeconds(0)));

    nrHelper->SetUeAntennaAttribute("NumRows", UintegerValue(2));
    nrHelper->SetUeAntennaAttribute("NumColumns", UintegerValue(4));
    nrHelper->SetUeAntennaAttribute("AntennaElement",
                                    PointerValue(CreateObject<IsotropicAntennaModel>()));
    nrHelper->SetGnbAntennaAttribute("NumRows", UintegerValue(4));
    nrHelper->SetGnbAntennaAttribute("NumColumns", UintegerValue(8));
    nrHelper->SetGnbAntennaAttribute("AntennaElement",
                                     PointerValue(CreateObject<IsotropicAntennaModel>()));

    // Slice = 5QI -> BWP mapping
    const uint32_t bwpSliceA = 0;
    const uint32_t bwpSliceB = 1;
    nrHelper->SetGnbBwpManagerAlgorithmAttribute("NGBR_VIDEO_TCP_DEFAULT",
                                                 UintegerValue(bwpSliceA));
    nrHelper->SetGnbBwpManagerAlgorithmAttribute("NGBR_LOW_LAT_EMBB", UintegerValue(bwpSliceB));
    nrHelper->SetUeBwpManagerAlgorithmAttribute("NGBR_VIDEO_TCP_DEFAULT",
                                                UintegerValue(bwpSliceA));
    nrHelper->SetUeBwpManagerAlgorithmAttribute("NGBR_LOW_LAT_EMBB", UintegerValue(bwpSliceB));

    NetDeviceContainer gnbDev = nrHelper->InstallGnbDevice(gridScenario.GetBaseStations(), allBwps);
    NetDeviceContainer ueADev = nrHelper->InstallUeDevice(ueA, allBwps);
    NetDeviceContainer ueBDev = nrHelper->InstallUeDevice(ueB, allBwps);
    NetDeviceContainer ueDevs;
    ueDevs.Add(ueADev);
    ueDevs.Add(ueBDev);
    nrHelper->AssignStreams({.scenario = &gridScenario, .gnbDevs = gnbDev, .ueDevs = ueDevs});
    int64_t stream = 100000; // my apps: far above the NR helper stream bases

    // Same numerology on both BWPs so the share is the only difference; power split by bandwidth.
    double powerMw = std::pow(10, totalTxPower / 10);
    NrHelper::GetGnbPhy(gnbDev.Get(0), bwpSliceA)
        ->SetAttribute("Numerology", UintegerValue(numerology));
    NrHelper::GetGnbPhy(gnbDev.Get(0), bwpSliceA)
        ->SetTxPower(10 * std::log10(sliceAShare * powerMw));
    NrHelper::GetGnbPhy(gnbDev.Get(0), bwpSliceB)
        ->SetAttribute("Numerology", UintegerValue(numerology));
    NrHelper::GetGnbPhy(gnbDev.Get(0), bwpSliceB)
        ->SetTxPower(10 * std::log10((1 - sliceAShare) * powerMw));

    auto [remoteHost, remoteHostAddr] = nrEpcHelper->SetupRemoteHost("100Gb/s", 2500, Seconds(0));

    InternetStackHelper internet;
    internet.Install(gridScenario.GetUserTerminals());
    Ipv4InterfaceContainer ueAIface = nrEpcHelper->AssignUeIpv4Address(ueADev);
    Ipv4InterfaceContainer ueBIface = nrEpcHelper->AssignUeIpv4Address(ueBDev);
    nrHelper->AttachToClosestGnb(ueADev, gnbDev);
    nrHelper->AttachToClosestGnb(ueBDev, gnbDev);

    const uint16_t portA = 5000;
    const uint16_t portB = 6000;

    ApplicationContainer serverApps;
    ApplicationContainer clientApps;

    std::string base = outputDir + "/" + simTag;
    std::ofstream txLog(base + "-tx.csv");
    txLog << "time_ns,slice,ue,frame,pkt_idx,pkts_in_frame,pkt_bytes,frame_bytes,jitter_ms\n";

    // Slice A: XR video, 5QI 9 -> BWP 0
    PacketSinkHelper sinkA("ns3::UdpSocketFactory",
                           InetSocketAddress(Ipv4Address::GetAny(), portA));
    serverApps.Add(sinkA.Install(ueA));
    NrQosFlow flowA(NrQosFlow::NGBR_VIDEO_TCP_DEFAULT);
    Ptr<NrQosRule> ruleA = Create<NrQosRule>();
    NrQosRule::PacketFilter pfA;
    pfA.localPortStart = portA;
    pfA.localPortEnd = portA;
    ruleA->Add(pfA);
    for (uint32_t i = 0; i < ueA.GetN(); ++i)
    {
        Ptr<XrVideoApp> app = CreateObject<XrVideoApp>();
        app->Configure(InetSocketAddress(ueAIface.GetAddress(i), portA),
                       videoRateMbps,
                       videoFps,
                       frameStdRatio,
                       frameMinRatio,
                       frameMaxRatio,
                       jitterStdMs,
                       jitterBoundMs,
                       maxPayload,
                       i,
                       &txLog);
        stream += app->AssignStreams(stream);
        remoteHost->AddApplication(app);
        clientApps.Add(app);
        nrHelper->ActivateDedicatedQosFlow(ueADev.Get(i), flowA, ruleA);
    }

    // Slice B: low-latency periodic traffic, 5QI 80 -> BWP 1
    UdpServerHelper sinkB(portB);
    serverApps.Add(sinkB.Install(ueB));
    UdpClientHelper clientB;
    clientB.SetAttribute("MaxPackets", UintegerValue(0xFFFFFFFF));
    clientB.SetAttribute("PacketSize", UintegerValue(llPacketBytes));
    clientB.SetAttribute("Interval", TimeValue(Seconds(llPeriodMs * 1e-3)));
    NrQosFlow flowB(NrQosFlow::NGBR_LOW_LAT_EMBB);
    Ptr<NrQosRule> ruleB = Create<NrQosRule>();
    NrQosRule::PacketFilter pfB;
    pfB.localPortStart = portB;
    pfB.localPortEnd = portB;
    ruleB->Add(pfB);
    for (uint32_t i = 0; i < ueB.GetN(); ++i)
    {
        clientB.SetAttribute(
            "Remote",
            AddressValue(addressUtils::ConvertToSocketAddress(ueBIface.GetAddress(i), portB)));
        clientApps.Add(clientB.Install(remoteHost));
        nrHelper->ActivateDedicatedQosFlow(ueBDev.Get(i), flowB, ruleB);
    }

    serverApps.Start(appStart);
    clientApps.Start(appStart);
    serverApps.Stop(simTime);
    clientApps.Stop(simTime);

    if (pcap)
    {
        // The remote host's point-to-point link towards the PGW: every downlink packet of
        // both slices passes here before entering the GTP tunnel.
        PointToPointHelper p2p;
        for (uint32_t d = 0; d < remoteHost->GetNDevices(); ++d)
        {
            if (DynamicCast<PointToPointNetDevice>(remoteHost->GetDevice(d)))
            {
                p2p.EnablePcap(base + "-rh", remoteHost->GetDevice(d), true);
            }
        }
    }

    FlowMonitorHelper flowmonHelper;
    NodeContainer endpoints;
    endpoints.Add(remoteHost);
    endpoints.Add(gridScenario.GetUserTerminals());
    Ptr<FlowMonitor> monitor = flowmonHelper.Install(endpoints);
    monitor->SetAttribute("DelayBinWidth", DoubleValue(0.0001));
    monitor->SetAttribute("JitterBinWidth", DoubleValue(0.0001));
    monitor->SetAttribute("PacketSizeBinWidth", DoubleValue(20));

    std::cout << "Intent " << intentId << ": slice A " << bandwidthA / 1e6 << " MHz ("
              << sliceAShare * 100 << " %), slice B " << bandwidthB / 1e6 << " MHz, "
              << uesSliceA << "+" << uesSliceB << " UEs, video " << videoRateMbps << " Mbps @ "
              << videoFps << " fps per UE\n";

    Simulator::Stop(simTime);
    Simulator::Run();

    txLog.close();
    monitor->CheckForLostPackets();
    monitor->SerializeToXmlFile(base + "-flowmon.xml", true, true);

    Ptr<Ipv4FlowClassifier> classifier =
        DynamicCast<Ipv4FlowClassifier>(flowmonHelper.GetClassifier());
    std::map<char, SliceKpi> slices;
    std::ofstream kpi(base + "-kpi.txt");
    kpi.setf(std::ios_base::fixed);
    kpi.precision(3);
    double activeS = (simTime - appStart).GetSeconds();
    for (const auto& [id, s] : monitor->GetFlowStats())
    {
        Ipv4FlowClassifier::FiveTuple t = classifier->FindFlow(id);
        char slice = t.destinationPort == portA ? 'A' : (t.destinationPort == portB ? 'B' : '?');
        kpi << "Flow " << id << " slice " << slice << " (" << t.sourceAddress << ":"
            << t.sourcePort << " -> " << t.destinationAddress << ":" << t.destinationPort
            << ")\n  tx " << s.txPackets << " pkts, rx " << s.rxPackets << " pkts, throughput "
            << s.rxBytes * 8.0 / activeS / 1e6 << " Mbps";
        if (s.rxPackets > 0)
        {
            kpi << ", mean delay " << 1e3 * s.delaySum.GetSeconds() / s.rxPackets << " ms";
        }
        kpi << "\n";
        SliceKpi& k = slices[slice];
        k.txPackets += s.txPackets;
        k.rxPackets += s.rxPackets;
        k.rxBytes += s.rxBytes;
        k.delaySumS += s.delaySum.GetSeconds();
        k.jitterSumS += s.jitterSum.GetSeconds();
    }
    kpi << "\nPer slice (intent " << intentId << ", slice A share " << sliceAShare << ")\n";
    for (const auto& [slice, k] : slices)
    {
        double loss = k.txPackets ? 100.0 * (k.txPackets - k.rxPackets) / k.txPackets : 0;
        kpi << "  Slice " << slice << ": throughput " << k.rxBytes * 8.0 / activeS / 1e6
            << " Mbps, mean delay " << (k.rxPackets ? 1e3 * k.delaySumS / k.rxPackets : 0)
            << " ms, mean jitter "
            << (k.rxPackets > 1 ? 1e3 * k.jitterSumS / (k.rxPackets - 1) : 0)
            << " ms, loss " << loss << " %\n";
    }
    kpi.close();

    std::ifstream f(base + "-kpi.txt");
    std::cout << f.rdbuf();

    Simulator::Destroy();
    return 0;
}
