// ============================================================
// TONE + WHITE-NOISE SENSOR ERROR MODEL
//
// Simplified replacement for the previous AR / ARMA model.
// No CSV loader and no filter history are required.
//
// Model on sensor axis 2:
//   noise(t) = sum_j A_j*sin(2*pi*f_j*t + phi_j)
//              + sigma_white*w(t)
//   w(t) ~ N(0,1)
//
// IMPORTANT:
// The existing bias(i) term in delta_measurement is retained.
// Do not also put the stationary bias inside noise[], because
// delta_noise = noise - previous_noise would difference it away.
// ============================================================

#include <cmath>

void error_sensor()
{
    // ========================================================
    // Local Variables
    // ========================================================

    double noise[3];
    double random_walk[3];
    double random_noise[3];
    double random_walk_noise[3];
    double delta_noise[3];
    double delta_measurement[3];

    // --------------------------------------------------------
    // Sensor / Platform Frame Variables
    // --------------------------------------------------------

    double frame_sens2plat[3][3];
    double frame_sens2plat_T[3][3];
    double noise_sensor_frame[3];
    double noise_platform_frame[3];

    // ========================================================
    // TEST-DERIVED TONE MODEL PARAMETERS
    //
    // Copy these directly from the MATLAB identification output.
    // Change number_of_tones and the array values as needed.
    // white_noise_sigma = RMS of the residual after removing
    //                     bias and fitted tones.
    // ========================================================

    static const int number_of_tones = 3;

    static const double tone_frequency[number_of_tones] = {
        0.0, 0.0, 0.0       // REPLACE WITH IDENTIFIED Hz
    };

    static const double tone_amplitude[number_of_tones] = {
        0.0, 0.0, 0.0       // REPLACE WITH IDENTIFIED AMPLITUDES
    };

    static const double tone_phase[number_of_tones] = {
        0.0, 0.0, 0.0       // REPLACE WITH IDENTIFIED PHASES [rad]
    };

    static const double white_noise_sigma =
        0.0;                 // REPLACE WITH TEST RESIDUAL RMS

    static const double two_pi =
        6.283185307179586476925286766559;

    // ========================================================
    // SENSOR -> PLATFORM TRANSFORMATION MATRIX
    // ========================================================

    frame_sens2plat[0][0] = 1.0;   // replace
    // ... existing matrix values ...
    frame_sens2plat[2][2] = 1.0;   // replace

    // ========================================================
    // TRANSPOSE SENSOR -> PLATFORM MATRIX
    // ========================================================

    for (int i = 0; i < 3; i++)
    {
        for (int j = 0; j < 3; j++)
        {
            frame_sens2plat_T[i][j] =
                frame_sens2plat[j][i];
        }
    }

    // ========================================================
    // Existing Error Vector Calculations
    // ========================================================

    error_vector_multiplier(
        xyz(0,0),
        delaythta(0),
        xyz(0,0)
    );

    // ========================================================
    // Generate RNG Values for White Noise
    // and Angular Random Walk
    // ========================================================

    size = 3;

    rn_norm_limits(
        &seed,
        &size,
        &random_noise[0]
    );

    rn_norm_limits(
        &seed,
        &size,
        &random_walk_noise[0]
    );

    // ========================================================
    // GENERATE IDENTIFIED EXPLICIT TONES
    // ========================================================

    double sensor_time =
        global_time;

    double sensor_axis2_tones = 0.0;

    for (int j = 0; j < number_of_tones; j++)
    {
        sensor_axis2_tones +=
            tone_amplitude[j]
            * std::sin(
                two_pi
                * tone_frequency[j]
                * sensor_time
                + tone_phase[j]
            );
    }

    // ========================================================
    // ADD WHITE STOCHASTIC NOISE
    //
    // random_noise[1] is assumed to be N(0,1), as in the
    // previous AR / ARMA implementation.
    // ========================================================

    double sensor_axis2_white_noise =
        white_noise_sigma
        * random_noise[1];

    double sensor_axis2_noise =
        sensor_axis2_tones
        + sensor_axis2_white_noise;

    // ========================================================
    // Build SENSOR-FRAME Noise Vector
    // ========================================================

    noise_sensor_frame[0] = 0.0;
    noise_sensor_frame[1] = sensor_axis2_noise;
    noise_sensor_frame[2] = 0.0;

    // ========================================================
    // Transform SENSOR-FRAME Noise -> PLATFORM FRAME
    // ========================================================

    for (int i = 0; i < 3; i++)
    {
        noise_platform_frame[i] = 0.0;

        for (int j = 0; j < 3; j++)
        {
            noise_platform_frame[i] +=
                frame_sens2plat_T[i][j]
                * noise_sensor_frame[j];
        }
    }

    // ========================================================
    // Assign Test-Derived Platform-Frame Noise
    // ========================================================

    for (int i = 0; i < 3; i++)
    {
        noise[i] =
            noise_platform_frame[i];
    }

    // ========================================================
    // Angular Random Walk
    // ========================================================

    for (int i = 0; i < 3; i++)
    {
        random_walk[i] =
            random_walk_noise[i]
            + random_walk_convolution[i];
    }

    // ========================================================
    // Calculate Final Sensor Delta / Measurement
    //
    // Existing bias(i) is intentionally retained here.
    // ========================================================

    for (int i = 0; i < 3; i++)
    {
        delta_noise[i] =
            noise[i]
            - internal_data.noise[i];

        delta_measurement[i] =
            delaythta(i)
            + bias(i)
            + other_error_terms(i)
            + delta_noise[i]
            + random_walk[i];

        internal_data.noise[i] =
            noise[i];
    }

    return;
}
