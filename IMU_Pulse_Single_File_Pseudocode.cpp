// ============================================================================
// SELF-CONTAINED IMU PULSE ERROR MODEL -- SINGLE-FILE IMPLEMENTATION TEMPLATE
// ============================================================================
// This is executable C++11-style pseudocode: every generator helper is included.
// It follows the structure of your gyro error_sensor() template, but produces
// ACCELEROMETER ERROR rather than tones or angular-rate error.
//
// IMPORTANT: The numerical coefficients below are ILLUSTRATIVE EXAMPLE VALUES.
// Replace the marked constants using the FOUR tables from YOUR MATLAB run:
//   Coefficients, PulseTypes, PulseKnots, GapQuantiles.
// They are not the fitted coefficients of your sensor; those were not supplied.
//
// FILE ORDER:
//   1. Includes, model types, coefficient constants and persistent state.
//   2. RNG adapters and complete pulse-generator helper functions.
//   3. Initialization, called once at the beginning of EACH simulation run.
//   4. error_sensor(), called once per SENSOR SAMPLE, using the helpers above.
//   5. Optional standalone demonstration main(), enabled only with a build flag.
//
// All of this belongs in ONE .cpp file. No MATLAB process, CSV loader, recorded
// time history, separately compiled model source, or custom header is required.
// The construction matches the package model. Different MATLAB/C++ RNG algorithms
// or draw order mean that matching seeds do not guarantee identical waveforms.
// ============================================================================

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <random>
#include <stdexcept>
#include <vector>

namespace { // File-local names: visible to functions in this .cpp only.

// A knot specifies one COMPLETE error value at a sample position in a pulse.
// MATLAB PulseKnots.Row0 is already zero-based; copy it WITHOUT subtracting one.
struct Knot {
    std::size_t row;
    double value; // micro-g, including the retained measured error offset/texture
};

struct PulseType {
    std::size_t count;       // PulseTypes.CountPerBlock: integer multiplicity
    std::size_t width;       // PulseTypes.Width_samples: integer sample count
    std::vector<Knot> knots; // Ordered PulseKnots rows for this TypeIndex0
};

struct RecordParams {
    std::size_t blockSamples;
    double b, sigma;                    // Quiet normal proposal location/scale
    double lo, hi;                      // Bounds for the COMPLETE modeled error
    double quietLo, quietHi;            // Bounds for interior quiet samples
    double releaseLo, releaseHi;        // Bounds for FIRST sample of a quiet gap
    std::vector<PulseType> types;
    std::vector<double> gapQ;           // Extra quiet samples at equal CDF spacing
};

// Unlike the fixed coefficients, these counters change on every sensor tick.
// Keeping this object outside error_sensor() preserves it between calls.
struct RecordState {
    bool initialized = false;          // A block schedule currently exists
    std::vector<std::size_t> order;    // Shuffled pulse-type indices for this block
    std::vector<std::size_t> gaps;     // One quiet gap before/between/after pulses
    std::size_t event = 0;             // Which scheduled pulse is next/current
    std::size_t pulseRow = 0;          // Sample index inside that pulse
    std::size_t gapLeft = 0;           // Remaining samples in the current gap
};

// ============================================================================
// EDIT 1 -- PASTE YOUR FITTED COEFFICIENT VALUES HERE.
// ============================================================================
// This example has 3 positive pulses and 1 negative pulse per 1000-sample block.
// Add/remove types and knots to match YOUR tables. Their counts need not match
// this example. Group PulseKnots by TypeIndex0 and sort by KnotIndex0.
const RecordParams kModel = {
    1000,                      // Coefficients.BlockSamples
    0.0, 1.0,                  // QuietLocation_ug, QuietScale_ug
    -40.0, 100.0,              // LowerBound_ug, UpperBound_ug
    -4.0, 4.0,                 // QuietLower_ug, QuietUpper_ug
    -2.0, 2.0,                 // ReleaseLower_ug, ReleaseUpper_ug
    {
        // {CountPerBlock, Width_samples, {{Row0,Value_ug}, ...}}
        {3, 3, {{0,20.0}, {1,100.0}, {2,20.0}}}, // Example type 0
        {1, 2, {{0,-40.0}, {1,-15.0}}}           // Example type 1
    },
    {0.0, 20.0, 70.0, 140.0}   // GapQuantiles.ExtraQuietSamples, in table order
};
// The real GapQuantiles table can have a different number of entries.
// Copy the VALUES, not its Probability column; probabilities are equally spaced.
// Types.Sign and SourceEventIndex1 are diagnostics, not runtime inputs.

// ============================================================================
// EDIT 2 -- SENSOR SELECTION, SAMPLE RATE, HOST OUTPUT UNITS AND FRAME MATRIX.
// ============================================================================
const std::size_t kSensorAxis = 1; // Copy SensorIndex0: 1 = SENSOR axis 2 / MATLAB Y.
const double kFitFsHz = 1000.0;   // Copy Coefficients.Fs_Hz. Call at this rate.

// Default host output: instantaneous acceleration in m/s^2.
// Set the first flag for ft/s^2; set the second if the measurement is DELTA V.
// If delta-V is selected, ideal_measurement and retained_error_terms passed to
// error_sensor() must ALREADY be delta-velocity quantities in matching units.
const bool kHostUsesFtPerSec2 = false;
const bool kHostOutputsDeltaVelocity = false;

// Paste the ACTUAL sensor-column -> platform-column multiplication matrix.
// These values must match cfg.R_sensor_to_PLT used in MATLAB.
// Your gyro file multiplies by frame_sens2plat_T. You may use that existing
// matrix instead, PROVIDED its numerical mapping is the same as this R.
// Whether a stored host matrix needs transposition depends on its convention.
const double kSensorToPlatform[3][3] = {
    {1.0, 0.0, 0.0},
    {0.0, 1.0, 0.0},
    {0.0, 0.0, 1.0}
};

// ============================================================================
// PERSISTENT GENERATOR AND RNG STATE -- ONE INSTANCE FOR ONE SERIAL SIMULATION.
// ============================================================================
// For parallel Monte Carlo runs or multiple sensor instances, give EACH instance
// its own state and RNG instead of sharing these mutable file-local objects.
RecordState gState;
bool gRunReady = false;
std::mt19937 gEngine;
std::normal_distribution<double> gNormal(0.0, 1.0);
std::uniform_real_distribution<double> gUniform(0.0, 1.0);
using Draw = double (*)();

// ============================================================================
// EDIT 3 -- OPTIONAL ADAPTATION TO YOUR EXISTING HOST RNG.
// ============================================================================
// These standard-library implementations make the file runnable by itself.
// To use your existing RNG, replace just these two bodies, and adapt seeding in
// initialize_sensor_error_for_run(). Every callback MUST consume a FRESH draw.
//
// rn_norm_limits() can supply freshN01() only if its output has the required
// standard-normal law. Extra host truncation changes the modeled noise law.
// Repeatedly returning one unchanged random_noise[1] is NOT a fresh draw:
// rejection sampling could keep rejecting it forever.
//
// A block plan consumes many uniform draws; a quiet sample may require multiple
// normal draws. Three precomputed values per sensor tick are not a general limit.
double freshN01() { return gNormal(gEngine); }
double freshUniform01() { return gUniform(gEngine); }

// Require the [0,1) convention used by indexing and stratified gap sampling.
double uniformDraw(Draw draw) {
    const double u = draw();
    if (!std::isfinite(u) || u < 0.0 || u >= 1.0)
        throw std::runtime_error("Uniform callback must return a fresh value in [0,1)");
    return u;
}

// Fisher-Yates shuffle: randomizes order while preserving every multiplicity.
template<class T>
void shuffleRecord(std::vector<T>& values, Draw uniform01) {
    for (std::size_t remaining = values.size(); remaining > 1; --remaining) {
        const std::size_t chosen = static_cast<std::size_t>(
            uniformDraw(uniform01) * remaining);
        std::swap(values[remaining-1], values[chosen]);
    }
}

// Run these checks once at initialization, after pasting coefficients.
// Count/width guards also prevent unsigned subtraction or multiplication overflow
// during construction of the schedule's available quiet-time budget.
void validateRecord(const RecordParams& p) {
    if (p.blockSamples == 0 || !std::isfinite(p.lo) || !std::isfinite(p.hi)
        || !(p.lo < p.hi) || !std::isfinite(p.b) || !std::isfinite(p.sigma)
        || p.sigma < 0 || !std::isfinite(p.quietLo) || !std::isfinite(p.quietHi)
        || p.quietLo < p.lo || p.quietHi > p.hi || !(p.quietLo < p.quietHi)
        || p.b < p.quietLo || p.b > p.quietHi || !std::isfinite(p.releaseLo)
        || !std::isfinite(p.releaseHi) || p.releaseLo < p.quietLo
        || p.releaseHi > p.quietHi || !(p.releaseLo < p.releaseHi)
        || p.types.empty() || p.gapQ.size() < 2)
        throw std::invalid_argument("Invalid axis coefficients");

    std::size_t active = 0, events = 0;
    for (const auto& t : p.types) {
        if (t.width == 0 || t.count == 0 || t.knots.empty()
            || t.count > (p.blockSamples-active)/t.width
            || t.count > p.blockSamples-events)
            throw std::invalid_argument("Invalid pulse count/width");
        active += t.count*t.width;
        events += t.count;
        if (t.knots.front().row != 0 || t.knots.back().row != t.width-1)
            throw std::invalid_argument("Pulse needs first and last sample knots");
        for (std::size_t k = 0; k < t.knots.size(); ++k) {
            if (!std::isfinite(t.knots[k].value) || t.knots[k].value < p.lo
                || t.knots[k].value > p.hi || t.knots[k].row >= t.width
                || (k > 0 && t.knots[k].row <= t.knots[k-1].row))
                throw std::invalid_argument("Invalid pulse knot value/order");
        }
    }
    if (events >= p.blockSamples-active)
        throw std::invalid_argument("Need at least one quiet sample in each of E+1 gaps");
    for (std::size_t k = 0; k < p.gapQ.size(); ++k) {
        if (!std::isfinite(p.gapQ[k]) || p.gapQ[k] < 0
            || (k > 0 && p.gapQ[k] < p.gapQ[k-1]))
            throw std::invalid_argument("Invalid gap-quantile values/order");
    }
}

// Approximate inverse CDF for EXTRA quiet samples, using the fitted table.
double gapQuantile(const RecordParams& p, double probability) {
    const double position = probability * (p.gapQ.size()-1);
    const std::size_t left = std::min(
        static_cast<std::size_t>(position), p.gapQ.size()-2);
    const double fraction = position-left;
    return p.gapQ[left] + fraction*(p.gapQ[left+1]-p.gapQ[left]);
}

// Create one full fitted-length block. This is called initially and after each
// completed block, not on every sample. It allocates vectors at block boundaries;
// use preallocated storage if your host has hard real-time allocation constraints.
void planRecord(const RecordParams& p, RecordState& s, Draw uniform01) {
    s = RecordState{};
    std::size_t activeSamples = 0;
    for (std::size_t type = 0; type < p.types.size(); ++type) {
        // Example: a count of 3 inserts that type index three times.
        s.order.insert(s.order.end(), p.types[type].count, type);
        activeSamples += p.types[type].count * p.types[type].width;
    }
    shuffleRecord(s.order, uniform01);

    // E pulses need E+1 gaps: before, between, and after pulses.
    // Give every gap one quiet sample, then distribute the remaining budget.
    const std::size_t slots = s.order.size()+1;
    const std::size_t extra = p.blockSamples-activeSamples-slots;
    std::vector<double> weights(slots);
    double totalWeight = 0.0;
    for (std::size_t k = 0; k < slots; ++k) {
        // One random quantile in each stratum helps cover the spacing range.
        weights[k] = gapQuantile(p, (k+uniformDraw(uniform01))/slots);
        totalWeight += weights[k];
    }
    shuffleRecord(weights, uniform01);
    if (totalWeight <= 0.0) {
        std::fill(weights.begin(), weights.end(), 1.0);
        totalWeight = static_cast<double>(slots);
    }

    // Cumulative randomized rounding preserves the EXACT integer total.
    // It avoids independent rounding accidentally changing the block length.
    const double offset = uniformDraw(uniform01);
    double cumulative = 0.0;
    std::size_t previous = 0;
    s.gaps.resize(slots);
    for (std::size_t k = 0; k < slots; ++k) {
        cumulative += weights[k];
        std::size_t rounded = (k+1 == slots) ? extra :
            static_cast<std::size_t>(std::floor(extra*(cumulative/totalWeight)+offset));
        rounded = std::max(previous, std::min(extra, rounded));
        s.gaps[k] = 1 + rounded-previous;
        previous = rounded;
    }
    s.gapLeft = s.gaps[0];
    s.initialized = true;
}

// Return one bounded background draw. The FIRST quiet sample after a pulse uses
// release bounds to end detection at the scheduled pulse boundary. Later quiet
// samples use the wider quiet bounds. Rejection draws fresh values; it does not
// clip the random output onto the endpoints.
double quietRecord(const RecordParams& p, bool firstInGap, Draw normal01) {
    const double lo = firstInGap ? p.releaseLo : p.quietLo;
    const double hi = firstInGap ? p.releaseHi : p.quietHi;
    const double center = std::max(lo, std::min(hi, p.b));
    if (p.sigma == 0.0) return center;
    double value;
    do { value = center + p.sigma*normal01(); }
    while (!std::isfinite(value) || value < lo || value > hi);
    return value;
}

// Return one pulse sample by linear interpolation between measured knots.
// Knot values are COMPLETE errors: do not add quiet offset or another Gaussian.
// A width-one pulse needs just one knot, at row zero.
double pulseRecord(const PulseType& t, std::size_t row) {
    if (t.width == 1) return t.knots.front().value;
    std::size_t right = 1;
    while (right+1 < t.knots.size() && t.knots[right].row < row) ++right;
    const Knot& a = t.knots[right-1];
    const Knot& b = t.knots[right];
    const double fraction = double(row-a.row)/double(b.row-a.row);
    const double value = a.value + fraction*(b.value-a.value);
    // Numerical guard only: interpolation should already lie between neighbors.
    return std::max(std::min(a.value,b.value), std::min(std::max(a.value,b.value),value));
}

void resetRecord(const RecordParams& p, RecordState& s, Draw uniform01) {
    validateRecord(p);
    planRecord(p, s, uniform01);
}

// This is the replacement for the gyro's tone-sum + white-noise calculation.
// Exactly ONE call advances the model by exactly ONE fitted sensor sample.
double sampleRecord(const RecordParams& p, RecordState& s,
                    Draw normal01, Draw uniform01) {
    if (!s.initialized) planRecord(p, s, uniform01);
    if (s.gapLeft > 0) {
        const bool firstInGap = (s.gapLeft == s.gaps[s.event]);
        --s.gapLeft;
        const double value = quietRecord(p, firstInGap, normal01);
        // The final quiet gap completes the block. Replan on the NEXT tick.
        if (s.event == s.order.size() && s.gapLeft == 0) s.initialized = false;
        return value;
    }
    const PulseType& type = p.types[s.order[s.event]];
    const double value = pulseRecord(type, s.pulseRow);
    if (++s.pulseRow == type.width) {
        s.pulseRow = 0;
        ++s.event;
        s.gapLeft = s.gaps[s.event];
    }
    return value;
}

} // End file-local definitions. Public host entry points follow below.

// ============================================================================
// ONCE PER RUN -- CALL FROM YOUR SIMULATION INITIALIZATION/RESET PATH.
// ============================================================================
void initialize_sensor_error_for_run(std::uint32_t run_seed) {
    gRunReady = false;
    if (kSensorAxis >= 3 || !std::isfinite(kFitFsHz) || kFitFsHz <= 0.0)
        throw std::invalid_argument("Invalid sensor axis/sample rate");
    gEngine.seed(run_seed);
    // normal_distribution may cache a spare sample. Reset that cache as well
    // as the engine so the same seed repeats a run within this implementation.
    gNormal.reset();
    gUniform.reset();
    resetRecord(kModel, gState, freshUniform01);
    gRunReady = true;
}

// ============================================================================
// INSIDE THE SENSOR FUNCTION -- CALLED AT kFitFsHz, ONCE PER SENSOR SAMPLE.
// ============================================================================
// These arguments are explicit placeholders for your host's existing variables:
//   ideal_measurement     = ideal measurement in PLATFORM frame and host units
//   retained_error_terms  = other deliberately retained PLATFORM-frame errors
//   delta_measurement     = resulting PLATFORM-frame measurement in host units
//
// In your existing void error_sensor(), remove these arguments and bind the same
// logic to your host variables. In-place input/output arrays are supported.
// The default output is acceleration despite the inherited delta_measurement
// name. Set kHostOutputsDeltaVelocity only for an actual delta-velocity interface.
void error_sensor(const double ideal_measurement[3],
                  const double retained_error_terms[3],
                  double delta_measurement[3]) {
    if (!gRunReady)
        throw std::logic_error("Call initialize_sensor_error_for_run() before sampling");

    // 1. Generate COMPLETE axis error in micro-g, using coefficients and RNG.
    // Cache this result if multiple host readers inspect the same sensor tick.
    const double error_ug = sampleRecord(kModel, gState, freshN01, freshUniform01);

    // 2. Convert micro-g to the host measurement units.
    //    1 micro-g = 9.80665e-6 m/s^2.
    double sensor_axis2_noise = error_ug * 9.80665e-6;
    if (kHostUsesFtPerSec2) sensor_axis2_noise /= 0.3048;
    if (kHostOutputsDeltaVelocity) sensor_axis2_noise *= 1.0/kFitFsHz;

    // 3. Apply this NEW model contribution only to the selected SENSOR axis.
    //    Other host sensor axes can keep their independently specified errors.
    double noise_sensor_frame[3] = {0.0, 0.0, 0.0};
    noise_sensor_frame[kSensorAxis] = sensor_axis2_noise;

    // 4. Rotate this contribution into PLATFORM coordinates, as in the gyro.
    //    One sensor-axis contribution may project onto several platform axes.
    double noise_platform_frame[3] = {0.0, 0.0, 0.0};
    for (int i = 0; i < 3; ++i) {
        for (int j = 0; j < 3; ++j) {
            noise_platform_frame[i] += kSensorToPlatform[i][j]*noise_sensor_frame[j];
        }
    }

    // 5. Add the model contribution to the host measurement.
    //    error_ug is acceleration error, so do NOT use the gyro expression
    //        noise[i] - internal_data.noise[i]
    //    on this instantaneous output. That would change pulses into edges and
    //    difference away a constant offset. Delta-V uses acceleration*dt above.
    for (int i = 0; i < 3; ++i) {
        const double noise = noise_platform_frame[i];
        delta_measurement[i] = ideal_measurement[i] + retained_error_terms[i] + noise;
    }

    // The fitted model already contains quiet offset, background noise and
    // retained pulse texture. To reproduce the validated model, remove matching
    // old error contributions on this SENSOR axis before assembling retained
    // errors. Keeping them adds another modeled disturbance on top.
    //
    // Keep any intentional additional errors with their correct frame and units.
    // For rotated frames, setting just platform element [1] to zero does not
    // generally remove the old SENSOR-axis-2 contribution.
}

// ============================================================================
// OPTIONAL DEMONSTRATION -- NOT REQUIRED BY YOUR SIMULATION.
// ============================================================================
// Build/run the illustrative example with:
//   g++ -std=c++11 -O2 -DIMU_PULSE_DEMO_MAIN IMU_Pulse_Single_File_Pseudocode.cpp -o imu_demo
//   ./imu_demo
// Without this flag, compile this file into your host; no main() is defined.
#ifdef IMU_PULSE_DEMO_MAIN
#include <iostream>
int main() {
    initialize_sensor_error_for_run(1234);
    const double ideal_measurement[3] = {0.0, 0.0, 0.0};
    const double retained_error_terms[3] = {0.0, 0.0, 0.0};
    double delta_measurement[3] = {};
    std::cout << "sample,outputX,outputY,outputZ\n";
    for (std::size_t sample = 0; sample < 2*kModel.blockSamples; ++sample) {
        error_sensor(ideal_measurement, retained_error_terms, delta_measurement);
        std::cout << sample << ',' << delta_measurement[0] << ','
                  << delta_measurement[1] << ',' << delta_measurement[2] << '\n';
    }
}
#endif
