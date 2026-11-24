/*
 * A4 - Baseline Reproduction of Rana et al., IEEE TVT 2024, Fig. 6
 * Petrajoy Davidson (M11502803), Multimedia Wireless Networks 2026
 *
 * Downlink 5G NR (5G-LENA v5.1, ns-3.48) with three slices from Rana et al. Sec. V:
 *
 *   Slice 1  MTC    4-state semi-Markov source, L = [1, .5, .5, .5] s, W = [0, 55, 50, 0] pkt/s
 *                   5QI 80 (priority 68)  -> highest priority, as Scenario 1 of Table IV
 *   Slice 2  VoIP   12.65 kbit/s, Poisson arrivals (mean 20 ms, 32 B)
 *                   5QI 7  (priority 70)
 *   Slice 3  Video  H.265 4K, 30 fps, mean 15 Mbit/s, Pareto frame sizes, 1400 B packets
 *                   5QI 9  (priority 90)  -> lowest priority
 *
 * Topology (--hetnet=1): one macro gNB (3.7 GHz, UMa, 43 dBm, mu = 1) and one small cell
 * (28 GHz, UMi-StreetCanyon, 30 dBm, mu = 2) on separate bands, so they do not interfere.
 * 20 % of the UEs move at 100 km/h (outdoor, macro only), 80 % at 3 km/h (split between the
 * macro and the small cell). Random way-point inside each cell's box. 5G-LENA has no
 * handover, so a UE stays on the cell it attached to; the boxes keep it in coverage.
 *
 * The scheduler is a command-line switch (--scheduler=Qos | PF | RR), i.e. 5G-LENA's own
 * NrMacSchedulerOfdmaQos / OfdmaPF / OfdmaRR. Rana's proposed scheduler, FLS and CBAP have
 * no public code.
 *
 * Server -> UPF delay: NOT simulated here. All traffic is UDP, so that delay only adds to each
 * packet's RAN delay and does not change what the RAN does. analyze_a4.py adds it afterwards
 * for every delay value of Fig. 6 (10..80 ms). One run per (scheduler, seed) therefore serves
 * all eight points of the x-axis.
 *
 * Outputs (in --outputDir, prefix --simTag):
 *   <tag>-tx.csv     time_ns,flow,seq,bytes          one row per packet sent by a server app
 *   <tag>-rx.csv     time_ns,flow,seq,bytes,tx_ns    one row per packet received by a UE
 *   <tag>-flows.csv  flow,slice,cell,speed_kmh,node,x0,y0
 *   <tag>-summary.txt per-slice RAN delay / loss, for tuning the load before the full sweep
 *
 * Built from my A2 scenario (a2-intent-slicing.cc), itself from cttc-nr-demo.cc.
 */

#include "ns3/antenna-module.h"
#include "ns3/applications-module.h"
#include "ns3/core-module.h"
#include "ns3/internet-apps-module.h"
#include "ns3/internet-module.h"
#include "ns3/mobility-module.h"
#include "ns3/nr-module.h"
#include "ns3/point-to-point-module.h"

#include <array>
#include <cmath>
#include <fstream>
#include <vector>

using namespace ns3;

NS_LOG_COMPONENT_DEFINE("A4RanaServiceRate");

enum SliceId : uint8_t
{
    MTC = 0,
    VOIP = 1,
    VIDEO = 2
};

static const char* SLICE_NAME[] = {"MTC", "VoIP", "Video"};

/* ------------------------------------------------------------------------------------------ */
/* Traffic source: one class, three behaviours. Every packet carries a SeqTsHeader (12 bytes) */
/* so the UE side can match it to the tx log.                                                 */
/* ------------------------------------------------------------------------------------------ */
class SliceSourceApp : public Application
{
  public:
    static TypeId GetTypeId();

    void Setup(Address remote, SliceId slice, uint32_t flowId, std::ofstream* txLog);

    // MTC semi-Markov parameters (Rana et al. Sec. V-A)
    std::array<double, 4> mtcMeanStateS{1.0, 0.5, 0.5, 0.5};
    std::array<double, 4> mtcRatePps{0.0, 55.0, 50.0, 0.0};
    uint32_t mtcBytes{100}; // not stated in the paper (my choice)

    // VoIP
    double voipMeanIntervalS{0.020};
    uint32_t voipBytes{32}; // 32 B / 20 ms = 12.8 kbit/s ~ 12.65 kbit/s AMR-WB

    // Video
    double videoRateMbps{15};
    double videoFps{30};
    double videoParetoShape{2.5}; // not stated in the paper (my choice)
    double videoBoundRatio{4.0};  // frames capped at 4x the mean
    uint32_t maxPayload{1400};

  private:
    void StartApplication() override;
    void StopApplication() override;

    void Send(uint32_t bytes);
    void MtcEnterState(uint32_t s);
    void MtcSend();
    void VoipSend();
    void VideoFrame();

    Ptr<Socket> m_socket;
    Address m_remote;
    SliceId m_slice{MTC};
    uint32_t m_flowId{0};
    uint32_t m_seq{0};
    std::ofstream* m_txLog{nullptr};

    Ptr<ExponentialRandomVariable> m_exp;
    Ptr<UniformRandomVariable> m_uni;
    Ptr<ParetoRandomVariable> m_pareto;

    uint32_t m_mtcState{0};
    Time m_mtcStateEnd;
    EventId m_sendEvent;
    EventId m_stateEvent;
};

NS_OBJECT_ENSURE_REGISTERED(SliceSourceApp);

TypeId
SliceSourceApp::GetTypeId()
{
    static TypeId tid = TypeId("ns3::SliceSourceApp")
                            .SetParent<Application>()
                            .SetGroupName("Applications")
                            .AddConstructor<SliceSourceApp>();
    return tid;
}

void
SliceSourceApp::Setup(Address remote, SliceId slice, uint32_t flowId, std::ofstream* txLog)
{
    m_remote = remote;
    m_slice = slice;
    m_flowId = flowId;
    m_txLog = txLog;
    m_exp = CreateObject<ExponentialRandomVariable>();
    m_uni = CreateObject<UniformRandomVariable>();
    m_pareto = CreateObject<ParetoRandomVariable>();
}

void
SliceSourceApp::StartApplication()
{
    m_socket = Socket::CreateSocket(GetNode(), UdpSocketFactory::GetTypeId());
    m_socket->Bind();
    m_socket->Connect(m_remote);
    // Random start inside the first 100 ms so that flows are not synchronised.
    Time offset = Seconds(m_uni->GetValue(0.0, 0.1));
    switch (m_slice)
    {
    case MTC:
        m_stateEvent = Simulator::Schedule(offset,
                                           &SliceSourceApp::MtcEnterState,
                                           this,
                                           m_uni->GetInteger(0, 3));
        break;
    case VOIP:
        m_sendEvent = Simulator::Schedule(offset, &SliceSourceApp::VoipSend, this);
        break;
    case VIDEO:
        m_sendEvent = Simulator::Schedule(offset, &SliceSourceApp::VideoFrame, this);
        break;
    }
}

void
SliceSourceApp::StopApplication()
{
    Simulator::Cancel(m_sendEvent);
    Simulator::Cancel(m_stateEvent);
    if (m_socket)
    {
        m_socket->Close();
    }
}

void
SliceSourceApp::Send(uint32_t bytes)
{
    SeqTsHeader h; // timestamp = now
    h.SetSeq(m_seq);
    uint32_t hdr = h.GetSerializedSize();
    Ptr<Packet> p = Create<Packet>(bytes > hdr ? bytes - hdr : 0);
    p->AddHeader(h);
    m_socket->Send(p);
    *m_txLog << Simulator::Now().GetNanoSeconds() << "," << m_flowId << "," << m_seq << ","
             << p->GetSize() << "\n";
    ++m_seq;
}

// MTC: state s lasts Exp(L[s]); inside it packets arrive as Poisson(W[s]).
// Transition matrix P is not given numerically in the paper: next state is uniform among the
// other three (my assumption).
void
SliceSourceApp::MtcEnterState(uint32_t s)
{
    m_mtcState = s;
    Simulator::Cancel(m_sendEvent);
    Time dur = Seconds(m_exp->GetValue(mtcMeanStateS[s], 0));
    m_mtcStateEnd = Simulator::Now() + dur;
    if (mtcRatePps[s] > 0)
    {
        m_sendEvent = Simulator::Schedule(Seconds(m_exp->GetValue(1.0 / mtcRatePps[s], 0)),
                                          &SliceSourceApp::MtcSend,
                                          this);
    }
    uint32_t next = (s + 1 + m_uni->GetInteger(0, 2)) % 4;
    m_stateEvent = Simulator::Schedule(dur, &SliceSourceApp::MtcEnterState, this, next);
}

void
SliceSourceApp::MtcSend()
{
    if (Simulator::Now() >= m_mtcStateEnd)
    {
        return;
    }
    Send(mtcBytes);
    m_sendEvent = Simulator::Schedule(Seconds(m_exp->GetValue(1.0 / mtcRatePps[m_mtcState], 0)),
                                      &SliceSourceApp::MtcSend,
                                      this);
}

void
SliceSourceApp::VoipSend()
{
    Send(voipBytes);
    m_sendEvent = Simulator::Schedule(Seconds(m_exp->GetValue(voipMeanIntervalS, 0)),
                                      &SliceSourceApp::VoipSend,
                                      this);
}

// Video: one frame every 1/fps s; frame size Pareto with the given mean, cut into packets.
void
SliceSourceApp::VideoFrame()
{
    double mean = videoRateMbps * 1e6 / videoFps / 8.0;
    double scale = mean * (videoParetoShape - 1) / videoParetoShape;
    auto frame = static_cast<uint32_t>(
        std::lround(m_pareto->GetValue(scale, videoParetoShape, videoBoundRatio * mean)));
    while (frame > 0)
    {
        uint32_t sz = std::min(frame, maxPayload);
        Send(sz);
        frame -= sz;
    }
    m_sendEvent = Simulator::Schedule(Seconds(1.0 / videoFps), &SliceSourceApp::VideoFrame, this);
}

/* ------------------------------------------------------------------------------------------ */
/* Receive side                                                                                */
/* ------------------------------------------------------------------------------------------ */
struct SliceCounters
{
    uint64_t tx{0};
    uint64_t rx{0};
    double delaySumMs{0};
    double delayMaxMs{0};
};

static std::array<SliceCounters, 3> g_counters;
static std::vector<uint8_t> g_flowSlice;

static void
RxTrace(std::ofstream* log, uint32_t flowId, Ptr<const Packet> p, const Address& /*from*/)
{
    SeqTsHeader h;
    p->PeekHeader(h);
    int64_t now = Simulator::Now().GetNanoSeconds();
    int64_t tx = h.GetTs().GetNanoSeconds();
    *log << now << "," << flowId << "," << h.GetSeq() << "," << p->GetSize() << "," << tx
         << "\n";
    SliceCounters& c = g_counters[g_flowSlice[flowId]];
    double d = (now - tx) * 1e-6;
    c.rx++;
    c.delaySumMs += d;
    c.delayMaxMs = std::max(c.delayMaxMs, d);
}

struct UeInfo
{
    Ptr<Node> node;
    SliceId slice;
    bool macro;
    bool fast;
};

int
main(int argc, char* argv[])
{
    std::string scheduler = "Qos"; // Qos | PF | RR
    bool hetnet = true;

    uint32_t nMtc = 6; // cut from 10 for run time (deadline)
    uint32_t nVoip = 6;
    uint32_t nVideo = 4; // 8 overloaded the macro (21-38 % video loss)
    double fastShare = 0.2; // Rana: 20 % outdoor at 100 km/h
    double fastKmh = 100;
    double slowKmh = 3;

    // Macro cell (Rana Table III: 3.7 GHz, 43 dBm, SCS 15/30 kHz)
    double macroFreq = 3.7e9;
    double macroBw = 100e6; // Rana: 200 MHz. 200 MHz took 170 s CPU per simulated s -> 100 MHz
    uint16_t macroMu = 1;
    double macroPower = 43;
    // Rana: 866 m site distance. 433 m (corners 612 m) left edge UEs unable to carry 15 Mbit/s
    // video in my smoke test (37-98 % loss beyond 450 m), so the default box is smaller.
    double macroHalfSide = 300;
    std::string macroScenario = "UMa";

    // Small cell (Rana Table III: 28 GHz, 30 dBm, SCS 60 kHz, radius 250 m)
    double smallFreq = 28e9;
    double smallBw = 100e6;
    uint16_t smallMu = 2;
    double smallPower = 30;
    // Rana: radius 250 m. At 30 dBm / 28 GHz / UMi, the smoke test lost 13-43 % of VoIP beyond
    // ~170 m (coverage, not load), so UEs move in a +-110 m box (corners ~155 m).
    double smallRadius = 110;
    double smallX = 300; // position of the small cell inside the macro area
    std::string smallScenario = "UMi";

    uint32_t gnbRows = 2; // 4x8 in A2; 2x4 cuts the 3GPP channel cost
    uint32_t gnbCols = 4;
    std::string tddPattern = "DL|S|UL|UL|DL|DL|S|UL|UL|DL|";

    // Fairness exponent alpha of the QoS scheduler: weight = (100 - P) * potTput^alpha / avgTput.
    // With alpha > 0 a UE whose potential throughput is 0 (CQI 0) gives weight 0 and 5G-LENA
    // aborts (NS_ASSERT "Weight must be greater than zero"); it did with moving UEs even after
    // shrinking the cells. alpha = 0 -> weight = (100 - P) / avgTput, never 0.
    // Negative = keep 5G-LENA's default.
    double qosAlpha = 0;

    Time simTime = Seconds(12.5); // 2 s warm-up + 5 windows of 2 s + 0.5 s drain
    Time appStart = MilliSeconds(400);
    std::string simTag = "a4";
    std::string outputDir = ".";

    CommandLine cmd(__FILE__);
    cmd.AddValue("scheduler", "5G-LENA OFDMA scheduler: Qos, PF or RR", scheduler);
    cmd.AddValue("hetnet", "1 = macro + small cell, 0 = macro only", hetnet);
    cmd.AddValue("nMtc", "Number of MTC UEs (slice 1)", nMtc);
    cmd.AddValue("nVoip", "Number of VoIP UEs (slice 2)", nVoip);
    cmd.AddValue("nVideo", "Number of video UEs (slice 3)", nVideo);
    cmd.AddValue("fastShare", "Share of UEs at fastKmh (macro only)", fastShare);
    cmd.AddValue("macroBw", "Macro bandwidth (Hz)", macroBw);
    cmd.AddValue("smallBw", "Small-cell bandwidth (Hz)", smallBw);
    cmd.AddValue("macroMu", "Macro numerology", macroMu);
    cmd.AddValue("smallMu", "Small-cell numerology", smallMu);
    cmd.AddValue("tddPattern", "TDD pattern of both gNBs", tddPattern);
    cmd.AddValue("macroHalfSide", "Macro UEs move in a box of +- this many m", macroHalfSide);
    cmd.AddValue("smallRadius", "Small-cell UEs move in a box of +- this many m", smallRadius);
    cmd.AddValue("macroPower", "Macro gNB power (dBm)", macroPower);
    cmd.AddValue("smallPower", "Small-cell gNB power (dBm)", smallPower);
    cmd.AddValue("gnbRows", "gNB antenna rows", gnbRows);
    cmd.AddValue("gnbCols", "gNB antenna columns", gnbCols);
    cmd.AddValue("qosAlpha", "QoS scheduler fairness exponent (<0 = 5G-LENA default)", qosAlpha);
    cmd.AddValue("simTime", "Simulation time", simTime);
    cmd.AddValue("simTag", "Prefix of the output files", simTag);
    cmd.AddValue("outputDir", "Output directory", outputDir);
    cmd.Parse(argc, argv);
    // Seeds: use the standard ns-3 option --RngRun=<n>.

    Config::SetDefault("ns3::NrRlcUm::MaxTxBufferSize", UintegerValue(999999999));
    // Moving UEs: refresh the fast-fading channel every 100 ms.
    Config::SetDefault("ns3::ThreeGppChannelModel::UpdatePeriod", TimeValue(MilliSeconds(100)));

    /* ---------------- nodes and mobility ---------------- */
    NodeContainer gnbs;
    gnbs.Create(hetnet ? 2 : 1);
    MobilityHelper gnbMob;
    Ptr<ListPositionAllocator> gnbPos = CreateObject<ListPositionAllocator>();
    gnbPos->Add(Vector(0, 0, 25));
    if (hetnet)
    {
        gnbPos->Add(Vector(smallX, 0, 10));
    }
    gnbMob.SetPositionAllocator(gnbPos);
    gnbMob.SetMobilityModel("ns3::ConstantPositionMobilityModel");
    gnbMob.Install(gnbs);

    std::vector<UeInfo> ues;
    uint32_t perSlice[3] = {nMtc, nVoip, nVideo};
    for (uint8_t s = 0; s < 3; ++s)
    {
        uint32_t nFast = static_cast<uint32_t>(std::lround(fastShare * perSlice[s]));
        uint32_t slowIdx = 0;
        for (uint32_t i = 0; i < perSlice[s]; ++i)
        {
            UeInfo u;
            u.node = CreateObject<Node>();
            u.slice = static_cast<SliceId>(s);
            u.fast = i < nFast;
            // slow UEs alternate macro / small cell; fast UEs always on the macro
            u.macro = u.fast || !hetnet || (slowIdx++ % 2 == 0);
            ues.push_back(u);
        }
    }

    auto boxAllocator = [](double cx, double cy, double half) {
        Ptr<RandomRectanglePositionAllocator> a = CreateObject<RandomRectanglePositionAllocator>();
        Ptr<UniformRandomVariable> x = CreateObject<UniformRandomVariable>();
        x->SetAttribute("Min", DoubleValue(cx - half));
        x->SetAttribute("Max", DoubleValue(cx + half));
        Ptr<UniformRandomVariable> y = CreateObject<UniformRandomVariable>();
        y->SetAttribute("Min", DoubleValue(cy - half));
        y->SetAttribute("Max", DoubleValue(cy + half));
        a->SetX(x);
        a->SetY(y);
        a->SetAttribute("Z", DoubleValue(1.5));
        return a;
    };
    Ptr<RandomRectanglePositionAllocator> macroBox = boxAllocator(0, 0, macroHalfSide);
    Ptr<RandomRectanglePositionAllocator> smallBox = boxAllocator(smallX, 0, smallRadius);

    for (auto& u : ues)
    {
        double v = (u.fast ? fastKmh : slowKmh) / 3.6;
        Ptr<RandomRectanglePositionAllocator> box = u.macro ? macroBox : smallBox;
        MobilityHelper m;
        m.SetMobilityModel("ns3::RandomWaypointMobilityModel",
                           "Speed",
                           StringValue("ns3::ConstantRandomVariable[Constant=" +
                                       std::to_string(v) + "]"),
                           "Pause",
                           StringValue("ns3::ConstantRandomVariable[Constant=0]"),
                           "PositionAllocator",
                           PointerValue(box));
        m.SetPositionAllocator(box);
        m.Install(u.node);
    }

    NodeContainer macroUes;
    NodeContainer smallUes;
    std::vector<uint32_t> macroIdx;
    std::vector<uint32_t> smallIdx;
    for (uint32_t i = 0; i < ues.size(); ++i)
    {
        if (ues[i].macro)
        {
            macroUes.Add(ues[i].node);
            macroIdx.push_back(i);
        }
        else
        {
            smallUes.Add(ues[i].node);
            smallIdx.push_back(i);
        }
    }

    /* ---------------- NR ---------------- */
    Ptr<NrPointToPointEpcHelper> nrEpcHelper = CreateObject<NrPointToPointEpcHelper>();
    Ptr<IdealBeamformingHelper> beamformingHelper = CreateObject<IdealBeamformingHelper>();
    Ptr<NrHelper> nrHelper = CreateObject<NrHelper>();
    nrHelper->SetBeamformingHelper(beamformingHelper);
    nrHelper->SetEpcHelper(nrEpcHelper);
    beamformingHelper->SetAttribute("BeamformingMethod",
                                    TypeIdValue(DirectPathBeamforming::GetTypeId()));
    nrEpcHelper->SetAttribute("S1uLinkDelay", TimeValue(MilliSeconds(0)));

    nrHelper->SetSchedulerTypeId(TypeId::LookupByName("ns3::NrMacSchedulerOfdma" + scheduler));
    if (scheduler == "Qos" && qosAlpha >= 0)
    {
        // Attribute name differs between 5G-LENA versions: try the known ones, never abort.
        bool set = false;
        for (const char* name : {"ns3::NrMacSchedulerOfdmaQos::FairnessIndex",
                                 "ns3::NrMacSchedulerOfdmaQos::Alpha"})
        {
            if (Config::SetDefaultFailSafe(name, DoubleValue(qosAlpha)))
            {
                std::cout << "QoS fairness exponent: " << name << " = " << qosAlpha << "\n";
                set = true;
                break;
            }
        }
        if (!set)
        {
            std::cout << "WARNING: could not set the QoS fairness exponent (attribute not found)\n";
        }
    }
    nrHelper->SetGnbPhyAttribute("Pattern", StringValue(tddPattern));

    nrHelper->SetUeAntennaAttribute("NumRows", UintegerValue(1));
    nrHelper->SetUeAntennaAttribute("NumColumns", UintegerValue(2));
    nrHelper->SetUeAntennaAttribute("AntennaElement",
                                    PointerValue(CreateObject<IsotropicAntennaModel>()));
    nrHelper->SetGnbAntennaAttribute("NumRows", UintegerValue(gnbRows));
    nrHelper->SetGnbAntennaAttribute("NumColumns", UintegerValue(gnbCols));
    nrHelper->SetGnbAntennaAttribute("AntennaElement",
                                     PointerValue(CreateObject<IsotropicAntennaModel>()));

    // One band per cell, separate creators so each gNB's single BWP has index 0.
    CcBwpCreator macroCreator;
    CcBwpCreator::SimpleOperationBandConf macroConf(macroFreq, macroBw, 1);
    OperationBandInfo macroBand = macroCreator.CreateOperationBandContiguousCc(macroConf);
    Ptr<NrChannelHelper> macroChannel = CreateObject<NrChannelHelper>();
    macroChannel->ConfigureFactories(macroScenario, "Default", "ThreeGpp");
    macroChannel->SetChannelConditionModelAttribute("UpdatePeriod", TimeValue(MilliSeconds(100)));
    macroChannel->AssignChannelsToBands({macroBand});
    BandwidthPartInfoPtrVector macroBwps = CcBwpCreator::GetAllBwps({macroBand});

    NetDeviceContainer gnbMacroDev = nrHelper->InstallGnbDevice(gnbs.Get(0), macroBwps);
    nrHelper->SetUePhyAttribute("TxPower", DoubleValue(23));
    NetDeviceContainer ueMacroDev = nrHelper->InstallUeDevice(macroUes, macroBwps);
    NrHelper::GetGnbPhy(gnbMacroDev.Get(0), 0)->SetAttribute("Numerology", UintegerValue(macroMu));
    NrHelper::GetGnbPhy(gnbMacroDev.Get(0), 0)->SetTxPower(macroPower);

    NetDeviceContainer gnbSmallDev;
    NetDeviceContainer ueSmallDev;
    if (hetnet)
    {
        CcBwpCreator smallCreator;
        CcBwpCreator::SimpleOperationBandConf smallConf(smallFreq, smallBw, 1);
        OperationBandInfo smallBand = smallCreator.CreateOperationBandContiguousCc(smallConf);
        Ptr<NrChannelHelper> smallChannel = CreateObject<NrChannelHelper>();
        smallChannel->ConfigureFactories(smallScenario, "Default", "ThreeGpp");
        smallChannel->SetChannelConditionModelAttribute("UpdatePeriod",
                                                        TimeValue(MilliSeconds(100)));
        smallChannel->AssignChannelsToBands({smallBand});
        BandwidthPartInfoPtrVector smallBwps = CcBwpCreator::GetAllBwps({smallBand});

        gnbSmallDev = nrHelper->InstallGnbDevice(gnbs.Get(1), smallBwps);
        nrHelper->SetUePhyAttribute("TxPower", DoubleValue(16));
        ueSmallDev = nrHelper->InstallUeDevice(smallUes, smallBwps);
        NrHelper::GetGnbPhy(gnbSmallDev.Get(0), 0)
            ->SetAttribute("Numerology", UintegerValue(smallMu));
        NrHelper::GetGnbPhy(gnbSmallDev.Get(0), 0)->SetTxPower(smallPower);
    }

    auto [remoteHost, remoteHostAddr] = nrEpcHelper->SetupRemoteHost("100Gb/s", 2500, Seconds(0));

    InternetStackHelper internet;
    internet.Install(macroUes);
    internet.Install(smallUes);
    Ipv4InterfaceContainer macroIface = nrEpcHelper->AssignUeIpv4Address(ueMacroDev);
    Ipv4InterfaceContainer smallIface;
    nrHelper->AttachToClosestGnb(ueMacroDev, gnbMacroDev);
    if (hetnet)
    {
        smallIface = nrEpcHelper->AssignUeIpv4Address(ueSmallDev);
        nrHelper->AttachToClosestGnb(ueSmallDev, gnbSmallDev);
    }

    /* ---------------- applications ---------------- */
    std::string base = outputDir + "/" + simTag;
    std::ofstream txLog(base + "-tx.csv");
    std::ofstream rxLog(base + "-rx.csv");
    std::ofstream flowLog(base + "-flows.csv");
    txLog << "time_ns,flow,seq,bytes\n";
    rxLog << "time_ns,flow,seq,bytes,tx_ns\n";
    flowLog << "flow,slice,cell,speed_kmh,node,x0,y0\n";

    const uint16_t port[3] = {7000, 7100, 7200};
    // Slice -> 5QI. Lower 5QI priority level = served first by the QoS scheduler.
    auto qosFlowOf = [](SliceId s) {
        switch (s)
        {
        case MTC:
            return NrQosFlow(NrQosFlow::NGBR_LOW_LAT_EMBB); // 5QI 80, priority 68
        case VOIP:
            return NrQosFlow(NrQosFlow::NGBR_VOICE_VIDEO_GAMING); // 5QI 7, priority 70
        default:
            return NrQosFlow(NrQosFlow::NGBR_VIDEO_TCP_DEFAULT); // 5QI 9, priority 90
        }
    };

    ApplicationContainer apps;
    g_flowSlice.resize(ues.size());
    auto setupUe = [&](uint32_t ueIndex, Ptr<NetDevice> dev, Ipv4Address addr, bool macro) {
        const UeInfo& u = ues[ueIndex];
        uint32_t flowId = ueIndex;
        g_flowSlice[flowId] = u.slice;
        uint16_t p = port[u.slice];

        PacketSinkHelper sinkHelper("ns3::UdpSocketFactory",
                                    InetSocketAddress(Ipv4Address::GetAny(), p));
        ApplicationContainer sink = sinkHelper.Install(u.node);
        sink.Get(0)->TraceConnectWithoutContext("Rx",
                                                MakeBoundCallback(&RxTrace, &rxLog, flowId));
        apps.Add(sink);

        Ptr<SliceSourceApp> src = CreateObject<SliceSourceApp>();
        src->Setup(InetSocketAddress(addr, p), u.slice, flowId, &txLog);
        remoteHost->AddApplication(src);
        apps.Add(src);

        NrQosFlow flow = qosFlowOf(u.slice);
        Ptr<NrQosRule> rule = Create<NrQosRule>();
        NrQosRule::PacketFilter pf;
        pf.localPortStart = p;
        pf.localPortEnd = p;
        rule->Add(pf);
        nrHelper->ActivateDedicatedQosFlow(dev, flow, rule);

        Vector pos = u.node->GetObject<MobilityModel>()->GetPosition();
        flowLog << flowId << "," << SLICE_NAME[u.slice] << "," << (macro ? "macro" : "small")
                << "," << (u.fast ? fastKmh : slowKmh) << "," << u.node->GetId() << ","
                << pos.x << "," << pos.y << "\n";
    };
    for (uint32_t k = 0; k < macroIdx.size(); ++k)
    {
        setupUe(macroIdx[k], ueMacroDev.Get(k), macroIface.GetAddress(k), true);
    }
    for (uint32_t k = 0; k < smallIdx.size(); ++k)
    {
        setupUe(smallIdx[k], ueSmallDev.Get(k), smallIface.GetAddress(k), false);
    }
    flowLog.close();

    apps.Start(appStart);
    apps.Stop(simTime);

    std::cout << "A4 run " << simTag << ": scheduler " << scheduler << ", "
              << (hetnet ? "macro + small cell" : "macro only") << ", UEs MTC/VoIP/Video = "
              << nMtc << "/" << nVoip << "/" << nVideo << " (macro " << macroUes.GetN()
              << ", small " << smallUes.GetN() << ")\n";

    Simulator::Stop(simTime);
    Simulator::Run();

    txLog.close();
    rxLog.close();

    // Quick summary for load tuning (tx counted from the log file).
    {
        std::ifstream in(base + "-tx.csv");
        std::string line;
        std::getline(in, line);
        while (std::getline(in, line))
        {
            size_t a = line.find(',');
            size_t b = line.find(',', a + 1);
            uint32_t f = std::stoul(line.substr(a + 1, b - a - 1));
            g_counters[g_flowSlice[f]].tx++;
        }
    }
    std::ofstream sum(base + "-summary.txt");
    sum.setf(std::ios_base::fixed);
    sum.precision(3);
    for (uint8_t s = 0; s < 3; ++s)
    {
        const SliceCounters& c = g_counters[s];
        sum << SLICE_NAME[s] << ": tx " << c.tx << " rx " << c.rx << " loss "
            << (c.tx ? 100.0 * (c.tx - c.rx) / c.tx : 0) << " %, RAN delay mean "
            << (c.rx ? c.delaySumMs / c.rx : 0) << " ms, max " << c.delayMaxMs << " ms\n";
    }
    sum.close();
    std::ifstream f(base + "-summary.txt");
    std::cout << f.rdbuf();

    Simulator::Destroy();
    return 0;
}
