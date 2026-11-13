# Build 980252: architecture blocked on telemetry observation

Build 980252 stopped in relay leg 2 during architecture iteration 2. The unresolved
`external_prerequisite` was a deployed telemetry backend query contract for REQ-OBS-001.
This was a producer decision, not relay exhaustion: about 658 minutes remained in the
aggregate budget. The summary field repair succeeded (2002 to 1994 characters).

The preceding toolchain attempt correctly rejected a NuGet downgrade: MSTest 4.2.3
required Microsoft.NET.Test.Sdk >= 18.3.0 while the blueprint selected 17.13.0.
That failure returned to architecture for correction; it was not the terminal blocker.

## Evidence and architectural error

The run's discovery acceptance criteria for REQ-OBS-001 require health probes and
recording `cps.api.response_latency`. They do not specify a backend query API.
Product source also describes distributed tracing, which needs its own observation
boundary and assertions rather than being silently removed from coverage.

- `CommodityPricingService.Api/Program.cs` configures OTLP export for traces, metrics
  and logs, with `Telemetry:OtlpEndpoint` overriding the exporter endpoint.
- `CommodityPricingService.Api/SPEC.md` documents the latency histogram, units,
  quote/curve tags and exporter configuration.
- `CommodityPricingService.Messaging/PipelineInstrumentation.cs` defines the meter,
  histogram and activity source. Its SPEC mentions ClickStack for derived business
  log counts; that mention alone does not define a backend query contract.
- Worker `Program.cs` files configure the same export boundary. An empty endpoint
  setting is not an absent protocol: the documented environment/default behavior
  still applies.

OTLP defines telemetry export requests and responses, not a backend query API:
<https://opentelemetry.io/docs/specs/otlp/>.

The architect tied emission/propagation checks to a backend-specific query client
without ruling out observing real product exports through the existing configurable
boundary. Its prompt also required every named mechanism to exist already, conflicting
with the task of designing new automation fixtures and harnesses.

## Correction and limits

Shared instructions now require tracing the assertion to source, evaluating supported
test-owned observation points, and distinguishing instrumentation, export, propagation
and backend ingestion. Architecture explicitly permits planned automation helpers with
ownership, real dependencies and implementable lifecycle/observation contracts. All
architecture critics receive the same boundary rules.

A possible design is a test-owned OTLP receiver observing actual product exports in an
isolated target. This is a candidate, not a mandated framework or proof of execution.
It needs a compatible protocol implementation, a real product stimulus, bounded waiting,
isolation, readiness and cleanup. Histogram assertions need isolated measurements or
source-supported correlation; do not invent a request-ID metric label. Cross-service
propagation still requires the actual services and source-backed trace relationships.
Receiver self-tests do not prove product behavior or production backend ingestion.

Missing target access and configuration permissions remain execution prerequisites.
Explicitly required backend behavior with an unknown contract remains unresolved.
The runtime's external-blocker handling and completion checks are unchanged.

Prompt changes invalidate the saved run's input fingerprint. The next validation must
start fresh, rather than reuse an architecture produced under the old instructions.
Existing architecture and prerequisite tests check runtime invariants; only a new live
run can show whether the agents produce an acceptable design with these instructions.
