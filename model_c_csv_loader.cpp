// ============================================================
// Includes / Packages
// ============================================================

#include <cmath>
#include <fstream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

// ============================================================
// TEST-DERIVED SENSOR MODEL CSV CONTAINER
//
// Each CSV contains ONE regime and has these columns:
//
// filter_order, number_of_tones, tone_frequency,
// tone_amplitude, tone_phase, noise_model_A, noise_model_B
//
// Rows are padded to length(noise_model_A) = filter_order + 1.
// ============================================================

struct SensorNoiseModel
{
    int filter_order = 0;
    int number_of_tones = 0;

    std::vector<double> tone_frequency;
    std::vector<double> tone_amplitude;
    std::vector<double> tone_phase;
    std::vector<double> noise_model_A;

    double noise_model_B = 0.0;
};

// ============================================================
// SIMPLE CSV SPLIT
// ============================================================

static std::vector<std::string> split_csv(const std::string& line)
{
    std::vector<std::string> fields;
    std::stringstream stream(line);
    std::string field;

    while (std::getline(stream,field,','))
    {
        if (!field.empty() && field.back() == '\r')
            field.pop_back();

        fields.push_back(field);
    }

    return fields;
}

// ============================================================
// LOAD ONE REGIME CSV
// ============================================================

static SensorNoiseModel load_sensor_model_csv(
    const std::string& csv_path)
{
    std::ifstream file(csv_path.c_str());

    if (!file.is_open())
        throw std::runtime_error(
            "Could not open sensor model CSV: " + csv_path);

    std::string line;

    // Discard header row.
    if (!std::getline(file,line))
        throw std::runtime_error("Sensor model CSV is empty.");

    SensorNoiseModel model;
    int row = 0;

    while (std::getline(file,line))
    {
        if (line.empty())
            continue;

        std::vector<std::string> field = split_csv(line);

        if (field.size() < 7)
            throw std::runtime_error(
                "Sensor model CSV has an invalid row.");

        // Scalars are repeated down the CSV, but only the first
        // row is needed to initialize them.
        if (row == 0)
        {
            model.filter_order = std::stoi(field[0]);
            model.number_of_tones = std::stoi(field[1]);
            model.noise_model_B = std::stod(field[6]);
        }

        // noise_model_A is valid on every row.
        model.noise_model_A.push_back(
            std::stod(field[5]));

        // Tone values occupy only the first number_of_tones rows.
        // Remaining tone cells are NaN padding and are ignored.
        if (row < model.number_of_tones)
        {
            model.tone_frequency.push_back(
                std::stod(field[2]));

            model.tone_amplitude.push_back(
                std::stod(field[3]));

            model.tone_phase.push_back(
                std::stod(field[4]));
        }

        row++;
    }

    if (static_cast<int>(model.noise_model_A.size())
        != model.filter_order + 1)
    {
        throw std::runtime_error(
            "noise_model_A length does not match filter_order + 1.");
    }

    if (static_cast<int>(model.tone_frequency.size())
        != model.number_of_tones)
    {
        throw std::runtime_error(
            "Tone count does not match number_of_tones.");
    }

    return model;
}


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
    // SELECT TEST-DERIVED SENSOR MODEL
    //
    // Only change regime_to_use when you want a different
    // model.  The file name is constructed automatically:
    //
    // sensor_model_regime_1.csv
    // sensor_model_regime_2.csv
    // ...
    // ========================================================

    static const std::string sensor_model_directory =
        "/YOUR/DIRECTORY";

    static const int regime_to_use = 3;

    static const std::string sensor_model_csv =
        sensor_model_directory
        + "/sensor_model_regime_"
        + std::to_string(regime_to_use)
        + ".csv";

    // Read the CSV once when the simulation first calls this
    // function.  Do NOT read the file every sensor update.
    static const SensorNoiseModel sensor_model =
        load_sensor_model_csv(sensor_model_csv);

    // Keep the names used by the original implementation so
    // the remainder of the function stays recognizable.
    const int noise_model_order =
        sensor_model.filter_order;

    const int number_of_tones =
        sensor_model.number_of_tones;

    const std::vector<double>& noise_model_a =
        sensor_model.noise_model_A;

    const double noise_model_b =
        sensor_model.noise_model_B;

    const std::vector<double>& tone_frequency =
        sensor_model.tone_frequency;

    const std::vector<double>& tone_amplitude =
        sensor_model.tone_amplitude;

    const std::vector<double>& tone_phase =
        sensor_model.tone_phase;

    static const double two_pi =
        6.283185307179586476925286766559;

    // ========================================================
    // AR FILTER MEMORY
    //
    // Sized automatically from the filter order loaded from
    // the CSV.  Previous AR residual outputs only are stored.
    // ========================================================

    static std::vector<double> noise_model_history(
        sensor_model.filter_order,
        0.0);

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
    // Generate RNG Values for Output Noise
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
    // TEST-DERIVED AR RESIDUAL NOISE MODEL
    // ========================================================

    double white_excitation =
        random_noise[1];

    double sensor_axis2_ar_noise =
        noise_model_b
        * white_excitation;

    for (int k = 1; k <= noise_model_order; k++)
    {
        sensor_axis2_ar_noise -=
            noise_model_a[k]
            * noise_model_history[k - 1];
    }

    sensor_axis2_ar_noise /=
        noise_model_a[0];

    // ========================================================
    // Update AR Filter Memory
    // ========================================================

    for (int k = noise_model_order - 1; k > 0; k--)
    {
        noise_model_history[k] =
            noise_model_history[k - 1];
    }

    if (noise_model_order > 0)
    {
        noise_model_history[0] =
            sensor_axis2_ar_noise;
    }

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
    // COMBINE AR RESIDUAL + EXPLICIT TONES
    // ========================================================

    double sensor_axis2_noise =
        sensor_axis2_ar_noise
        + sensor_axis2_tones;

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
