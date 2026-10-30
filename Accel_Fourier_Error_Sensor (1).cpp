// ============================================================
// ACCELEROMETER TONE + OPTIONAL WHITE-NOISE ERROR MODEL
//
// Same section order and sine-loop structure as your gyro file.
// Model on the selected SENSOR axis (Y = index 1 in this example):
//   error_ug(t) = fitted_mean + sum A*sin(2*pi*f*t+phase)
//                 + white_noise_sigma*N(0,1).
//
// ACCEL CHANGES:
//  1. The new sum is acceleration error in micro-g.
//  2. Convert to your measurement units; multiply by dt ONCE for delta-v.
//  3. It replaces ALL old error on that sensor axis, including bias/RW.
//  4. Keep the old noise-difference/history path for the legacy model only.
//
// The numeric initializer is SYNTHETIC. Paste your actual MATLAB values.
// All model constants and persistent variables are INSIDE error_sensor(),
// beside the corresponding gyro sections. Only these includes go above it.
// ============================================================
#include <cmath>
#include <algorithm>
#include <cstdint>
#include <stdexcept>

void error_sensor()
{
    // ========================================================
    // Local Variables -- KEEP your existing accel declarations.
    // ========================================================
    double noise[3];
    double random_walk[3];
    double random_noise[3];
    double random_walk_noise[3];
    double delta_noise[3];
    double delta_measurement[3];

    // --------------------------------------------------------
    // Sensor / Platform Frame Variables -- SAME gyro names.
    // --------------------------------------------------------
    double frame_sens2plat[3][3];
    double frame_sens2plat_T[3][3];
    double noise_sensor_frame[3];
    double noise_platform_frame[3];
    double model_platform_frame[3] = {0.0,0.0,0.0}; // ADD.

    // ========================================================
    // TEST-DERIVED TONE MODEL PARAMETERS -- SAME location as gyro.
    // Paste Coefficients + ToneCoefficients values HERE.
    // Frequency: Hz. Amplitude/mean/white sigma: micro-g.
    // Phase: radians, already converted for std::sin().
    // Full Fourier contains measured ambient noise: sigma=0 by default.
    // ========================================================
    // BEGIN_FOURIER_COEFFICIENTS
    static const int modeled_sensor_axis = 1; // SENSOR Y; X=0, Y=1, Z=2.
    static const double model_Fs_Hz = 200.0;
    static const std::uint64_t model_record_samples = 32;
    static const int number_of_tones = 16;
    static const int tone_storage = number_of_tones>0 ? number_of_tones : 1;
    static const double fitted_error_mean_ug = 1.9906250000000001;
    static const double white_noise_sigma = 0.0;
    static const double tone_frequency[tone_storage] = {
        6.25, 12.5, 18.75, 25, 31.25, 37.5, 43.75, 50, 56.25, 62.5, 68.75, 75, 81.25, 87.5, 93.75, 100
    };
    static const double tone_amplitude[tone_storage] = {
        7.004455666208095, 4.3965707239554215, 7.7623287575349034, 4.6987739424769108, 5.0777031451080523, 7.0256512327511746, 1.5099677480766884, 9.0437500000000011, 1.5099677480766884, 7.0256512327511746, 5.0777031451080523, 4.6987739424769099, 7.7623287575349034, 4.3965707239554215, 7.004455666208095, 1.6906250000000003
    };
    static const double tone_phase[tone_storage] = {
        0.87177960082789241, -1.2189585366554927, -0.90864613009703676, -3.0028879265291648, -2.9871086195313872, 1.8535695835243846, 1.1231801990116299, 0, -1.1231801990116304, -1.8535695835243846, 2.9871086195313872, 3.0028879265291648, 0.90864613009703632, 1.2189585366554923, -0.87177960082789241, -1.5707963267948966
    };
    // END_FOURIER_COEFFICIENTS

    static const double two_pi = 6.283185307179586476925286766559;
    // ADD: select your real accumulator interface. Default delta-v [ft/s].
    static const bool model_output_is_delta_velocity = true;
    static const double ug_to_host_acceleration = 9.80665e-6/0.3048;
    // For SI acceleration/increments use 9.80665e-6 instead (no /.3048).
    // For instantaneous acceleration output set the bool above to false.
    static const bool randomize_record_start = false; // MATLAB aligned default.

    // ========================================================
    // ADD: small persistent clock / activation / run-reset section.
    // No AR/filter history, pulse scheduler or extra model source file.
    // Host names here follow the supplied accel snippet/reference layout:
    //   reset_model, sensor_tick, sensor_dt_s,
    //   use_test_accel_model, test_model_condition, test_model_start_time_s.
    // Bind them to the corresponding EXISTING host variables.
    // ========================================================
    static bool model_initialized = false;
    static bool was_model_enabled = false;
    static bool have_model_tick = false;
    static std::uint64_t model_sample = 0, start_offset = 0, previous_tick = 0;
    static double cached_model_error_ug = 0.0;
    static decltype(seed) phase_seed = {}; // Only for OPTIONAL random start.

    if (reset_model || !model_initialized)
    {
        was_model_enabled = false;
        have_model_tick = false;
        model_sample = 0;
        start_offset = 0;
        phase_seed = seed; // Copy existing run RNG state; consume no legacy draw.
        if (!(model_Fs_Hz>0.0) || !std::isfinite(model_Fs_Hz) ||
            model_record_samples==0 || modeled_sensor_axis<0 || modeled_sensor_axis>2 ||
            number_of_tones<0 || !std::isfinite(fitted_error_mean_ug) ||
            !std::isfinite(white_noise_sigma) || white_noise_sigma<0.0)
            throw std::runtime_error("Invalid accelerometer Fourier parameters");
        for (int j=0; j<number_of_tones; j++)
        {
            const double bin=tone_frequency[j]*double(model_record_samples)/model_Fs_Hz;
            if (!std::isfinite(tone_frequency[j]) || tone_frequency[j]<=0.0 ||
                tone_frequency[j]>model_Fs_Hz/2.0+1e-10 ||
                std::abs(bin-std::round(bin))>1e-7 ||
                !std::isfinite(tone_amplitude[j]) || tone_amplitude[j]<0.0 ||
                !std::isfinite(tone_phase[j]))
                throw std::runtime_error("Copy frequencies, amplitudes, phases and record length consistently");
        }
        model_initialized = true;
    }
    // As in your accel snippet, clear this owned flag once. If shared, retain
    // its clearing at the established host lifecycle point instead.
    reset_model = false;
    const bool model_enabled = use_test_accel_model
                            && test_model_condition
                            && global_time >= test_model_start_time_s;

    // ========================================================
    // SENSOR -> PLATFORM TRANSFORMATION MATRIX -- KEEP all 9 lines.
    // accel_frame_settings denotes the values already in your actual file.
    // Keep your original right-hand sides; the convention is unchanged.
    // ========================================================
    frame_sens2plat[0][0] = accel_frame_settings[0][0];
    frame_sens2plat[0][1] = accel_frame_settings[0][1];
    frame_sens2plat[0][2] = accel_frame_settings[0][2];
    frame_sens2plat[1][0] = accel_frame_settings[1][0];
    frame_sens2plat[1][1] = accel_frame_settings[1][1];
    frame_sens2plat[1][2] = accel_frame_settings[1][2];
    frame_sens2plat[2][0] = accel_frame_settings[2][0];
    frame_sens2plat[2][1] = accel_frame_settings[2][1];
    frame_sens2plat[2][2] = accel_frame_settings[2][2];

    // ========================================================
    // TRANSPOSE SENSOR -> PLATFORM MATRIX -- UNCHANGED.
    // ========================================================
    for (int i=0; i<3; i++)
    {
        for (int j=0; j<3; j++)
            frame_sens2plat_T[i][j] = frame_sens2plat[j][i];
    }

    // ========================================================
    // Existing Error Vector Calculations -- KEEP your ACCEL equivalent.
    // delaythta is the gyro reference spelling used as a positional alias
    // here. Bind it to the ideal ACCEL increment, not an actual gyro angle.
    // ========================================================
    error_vector_multiplier(xyz(0,0),delaythta(0),xyz(0,0));

    // ========================================================
    // Generate RNG Values for White Noise and Random Walk -- UNCHANGED.
    // The new white term reuses random_noise[selected axis], just like gyro.
    // It adds NO draws to this legacy stream. Assume UNIT normal draws.
    // ========================================================
    size = 3;
    rn_norm_limits(&seed,&size,&random_noise[0]);
    rn_norm_limits(&seed,&size,&random_walk_noise[0]);

    // ========================================================
    // KEEP YOUR EXISTING LEGACY ACCEL NOISE CALCULATION IN THIS BOX.
    // This filled example is ordinary per-axis white noise; the actual full
    // accel formula was not supplied. Retain its real formula if different.
    // Its existing noise-state units/scales must stay unchanged.
    // We keep this running for X/Z and for clean disable transitions.
    // ========================================================
    for (int i=0; i<3; i++)
        noise_sensor_frame[i] = accel_noise_sigma[i]*random_noise[i];
    for (int i=0; i<3; i++)
    {
        noise_platform_frame[i] = 0.0;
        for (int j=0; j<3; j++)
            noise_platform_frame[i] += frame_sens2plat_T[i][j]*noise_sensor_frame[j];
        noise[i] = noise_platform_frame[i]; // Preserve LEGACY noise[] history.
    }

    // ========================================================
    // GENERATE IDENTIFIED EXPLICIT TONES -- SAME gyro sine loop.
    // ADD: local sample clock matches MATLAB t=0 at the first fitted row.
    // global_time controls activation; the fitted record repeats every N/Fs.
    // ========================================================
    if (model_enabled && !was_model_enabled)
    {
        model_sample = 0;
        start_offset = 0;
        have_model_tick = false;
        if (randomize_record_start)
        {
            // Optional common circular shift. Separate seed preserves the
            // legacy stream. Phi(Z) needs UNTRUNCATED N(0,1); otherwise bind
            // your host's uniform routine at this line instead.
            decltype(size) one=1; double z=0.0;
            rn_norm_limits(&phase_seed,&one,&z);
            if (!std::isfinite(z)) throw std::runtime_error("Invalid phase draw");
            const double u=std::min(std::nextafter(1.0,0.0),0.5*std::erfc(-z/std::sqrt(2.0)));
            start_offset=std::min(model_record_samples-1,std::uint64_t(u*double(model_record_samples)));
        }
    }
    const bool new_model_tick = model_enabled
                            && (!have_model_tick || sensor_tick!=previous_tick);
    if (model_enabled)
    {
        if (!(sensor_dt_s>0.0) || !std::isfinite(sensor_dt_s) ||
            std::abs(sensor_dt_s*model_Fs_Hz-1.0)>1e-8)
            throw std::runtime_error("Accel model must update at fitted Fs");
        if (new_model_tick && have_model_tick && sensor_tick!=previous_tick+1)
            throw std::runtime_error("Skipped/backward model tick: reset or schedule missing samples");
    }
    const std::uint64_t wrapped_sample = (model_sample+start_offset)%model_record_samples;
    double sensor_time = double(wrapped_sample)/model_Fs_Hz;
    double sensor_axis_tones = 0.0;
    if (new_model_tick)
    {
        for (int j=0; j<number_of_tones; j++)
        {
            sensor_axis_tones += tone_amplitude[j]
                              * std::sin(two_pi*tone_frequency[j]*sensor_time+tone_phase[j]);
        }
    }

    // ========================================================
    // ADD WHITE STOCHASTIC NOISE -- SAME gyro architecture.
    // WhiteSigma_ug is zero by default because full Fourier already contains
    // the measured ambient noise. No AR/ARMA path or burn-in is involved.
    // ========================================================
    double sensor_axis_white_noise = white_noise_sigma*random_noise[modeled_sensor_axis];
    if (new_model_tick)
    {
        cached_model_error_ug = fitted_error_mean_ug
                             + sensor_axis_tones + sensor_axis_white_noise;
        model_sample = (model_sample+1)%model_record_samples;
        previous_tick = sensor_tick;
        have_model_tick = true;
    }
    double sensor_axis_noise = model_enabled ? cached_model_error_ug : 0.0;

    // ========================================================
    // Build SENSOR-FRAME Noise Vector -- SAME location as gyro.
    // ACCEL CHANGE: full error includes the fitted mean/bias ONCE.
    // Convert ug -> ft/s^2; multiply by dt ONCE for delta velocity [ft/s].
    // ========================================================
    double model_error_in_host_units = sensor_axis_noise*ug_to_host_acceleration;
    if (model_output_is_delta_velocity) model_error_in_host_units *= sensor_dt_s;
    noise_sensor_frame[0] = 0.0;
    noise_sensor_frame[1] = 0.0;
    noise_sensor_frame[2] = 0.0;
    noise_sensor_frame[modeled_sensor_axis] = model_error_in_host_units;

    // ========================================================
    // Transform SENSOR-FRAME Noise -> PLATFORM FRAME -- SAME loop.
    // ========================================================
    for (int i=0; i<3; i++)
    {
        noise_platform_frame[i] = 0.0;
        for (int j=0; j<3; j++)
            noise_platform_frame[i] += frame_sens2plat_T[i][j]*noise_sensor_frame[j];
    }

    // ========================================================
    // Assign Test-Derived Platform-Frame Error -- ACCEL CHANGE.
    // Store separately from LEGACY noise[]. The new acceleration sum must
    // BYPASS noise - previous_noise, which would differentiate the spikes.
    // ========================================================
    for (int i=0; i<3; i++)
        model_platform_frame[i] = noise_platform_frame[i];

    // ========================================================
    // Existing Accelerometer Random Walk -- KEEP original calculation.
    // Keep its convolution update at the original host location as well.
    // ========================================================
    for (int i=0; i<3; i++)
        random_walk[i] = random_walk_noise[i]+random_walk_convolution[i];

    // ========================================================
    // Calculate Final Sensor Delta / Measurement -- ACCEL CHANGE.
    // Gather ALL old errors first, in PLATFORM frame and final measurement
    // units. Continue the legacy noise difference even while overridden.
    // ========================================================
    double legacy_error_platform[3];
    for (int i=0; i<3; i++)
    {
        delta_noise[i] = noise[i]-internal_data.noise[i];
        legacy_error_platform[i] = bias(i)+other_error_terms(i)
                                 + delta_noise[i]+random_walk[i];
    }
    // R=sensor->platform. Dot(column selected of R, complete platform error)
    // extracts the old complete selected SENSOR-axis error, including bias/RW.
    double old_selected_sensor_error = 0.0;
    if (model_enabled)
        for (int i=0; i<3; i++)
            old_selected_sensor_error += frame_sens2plat_T[i][modeled_sensor_axis]
                                       * legacy_error_platform[i];

    for (int i=0; i<3; i++)
    {
        if (model_enabled)
        {
            const double old_selected_platform_error =
                frame_sens2plat_T[i][modeled_sensor_axis]*old_selected_sensor_error;
            delta_measurement[i] = delaythta(i) // KEEP ideal ACCEL increment.
                                 + legacy_error_platform[i]
                                 - old_selected_platform_error
                                 + model_platform_frame[i];
        }
        else
        {
            // EXACT original sum. Model disabled -> original behavior.
            delta_measurement[i] = delaythta(i)+bias(i)+other_error_terms(i)
                                 + delta_noise[i]+random_walk[i];
        }
        // KEEP legacy history even while enabled; no stale difference on exit.
        internal_data.noise[i] = noise[i];
        // KEEP your existing output/accumulator assignment at this location.
        accel_delta_output[i] = delta_measurement[i]; // Example host name only.
    }
    was_model_enabled = model_enabled;
    return;
}
