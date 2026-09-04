// ============================================================
// STANDARD C++ HEADERS NEEDED FOR CSV MODEL LOADING
// Keep these in the SAME existing C++ source file.
// No additional compilation unit is required.
// ============================================================

#include <cmath>
#include <fstream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <vector>

// ============================================================
// TEST-DERIVED SENSOR MODEL CONTAINER
// ============================================================

struct SensorNoiseModel
{
    double Fs = 0.0;
    double bias = 0.0;
    int noiseOrder = 0;
    double noiseB = 0.0;
    int numberOfTones = 0;

    std::vector<double> noiseA;
    std::vector<double> toneFrequency;
    std::vector<double> toneAmplitude;
    std::vector<double> tonePhase;
};

// ============================================================
// SIMPLE CSV SPLIT
// MATLAB export contains numeric fields only, so quoted-field
// handling is not required here.
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
// LOAD ONE SELECTED REGIME FROM THE CSV
// ============================================================

static SensorNoiseModel load_sensor_model_csv(
    const std::string& csvPath,
    int regimeToUse)
{
    std::ifstream file(csvPath.c_str());

    if (!file.is_open())
        throw std::runtime_error("Could not open sensor model CSV: " + csvPath);

    std::string line;

    if (!std::getline(file,line))
        throw std::runtime_error("Sensor model CSV is empty.");

    std::vector<std::string> headers = split_csv(line);
    std::unordered_map<std::string,int> column;

    for (int i = 0; i < static_cast<int>(headers.size()); ++i)
        column[headers[i]] = i;

    while (std::getline(file,line))
    {
        if (line.empty())
            continue;

        std::vector<std::string> field = split_csv(line);

        int regime = std::stoi(field[column.at("Regime")]);

        if (regime != regimeToUse)
            continue;

        SensorNoiseModel model;

        model.Fs = std::stod(field[column.at("Fs")]);
        model.bias = std::stod(field[column.at("Bias")]);
        model.noiseOrder = std::stoi(field[column.at("NoiseOrder")]);
        model.noiseB = std::stod(field[column.at("NoiseB")]);
        model.numberOfTones = std::stoi(field[column.at("NumTones")]);

        model.noiseA.resize(model.noiseOrder + 1);

        for (int k = 0; k <= model.noiseOrder; ++k)
        {
            std::string name = "A" + std::to_string(k);
            model.noiseA[k] = std::stod(field[column.at(name)]);
        }

        model.toneFrequency.resize(model.numberOfTones);
        model.toneAmplitude.resize(model.numberOfTones);
        model.tonePhase.resize(model.numberOfTones);

        for (int j = 0; j < model.numberOfTones; ++j)
        {
            std::string n = std::to_string(j + 1);

            model.toneFrequency[j] =
                std::stod(field[column.at("ToneFreq" + n)]);

            model.toneAmplitude[j] =
                std::stod(field[column.at("ToneAmp" + n)]);

            model.tonePhase[j] =
                std::stod(field[column.at("TonePhase" + n)]);
        }

        return model;
    }

    throw std::runtime_error(
        "Requested sensor-model regime was not found in CSV.");
}

// ============================================================
// EXISTING SENSOR FUNCTION
// ============================================================

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

    double frame_sens2plat[3][3];
    double frame_sens2plat_T[3][3];
    double noise_sensor_frame[3];
    double noise_platform_frame[3];

    // ========================================================
    // CSV MODEL SELECTION
    //
    // Point this to the CSV produced by MATLAB.
    // Ideally regimeToUse comes from your normal sim/config
    // input instead of being hard-coded here.
    //
    // The CSV is read ONLY when the selected regime changes,
    // not at every sensor update.
    // ========================================================

    const std::string sensorModelCsv =
        "/YOUR/DIRECTORY/sensor_models.csv";

    int regimeToUse = 2; // Replace with your sim/config value.

    static int loadedRegime = -1;
    static SensorNoiseModel model;
    static std::vector<double> noise_model_history;
    static double regime_start_time = 0.0;

    if (loadedRegime != regimeToUse)
    {
        model = load_sensor_model_csv(sensorModelCsv,regimeToUse);

        noise_model_history.assign(
            model.noiseOrder,
            0.0);

        loadedRegime = regimeToUse;

        // Fitted tone phase is referenced to t = 0 at the
        // beginning of the identified regime.
        regime_start_time = global_time;
    }

    // ========================================================
    // YOUR EXISTING SENSOR -> PLATFORM MATRIX SETUP GOES HERE
    // ========================================================

    // frame_sens2plat[0][0] = ...;
    // ...

    for (int i = 0; i < 3; ++i)
    {
        for (int j = 0; j < 3; ++j)
            frame_sens2plat_T[i][j] = frame_sens2plat[j][i];
    }

    // ========================================================
    // YOUR EXISTING ERROR-VECTOR CALCULATIONS GO HERE
    // ========================================================

    // error_vector_multiplier(...);

    // ========================================================
    // EXISTING UNIT-GAUSSIAN RNG
    // ========================================================

    size = 3;

    rn_norm_limits(&seed,&size,&random_noise[0]);
    rn_norm_limits(&seed,&size,&random_walk_noise[0]);

    // ========================================================
    // TEST-DERIVED AR RESIDUAL NOISE MODEL
    // ========================================================

    double white_excitation = random_noise[1];

    double sensor_axis2_ar_noise =
        model.noiseB * white_excitation;

    for (int k = 1; k <= model.noiseOrder; ++k)
    {
        sensor_axis2_ar_noise -=
            model.noiseA[k]
            * noise_model_history[k - 1];
    }

    sensor_axis2_ar_noise /= model.noiseA[0];

    // ========================================================
    // UPDATE AR FILTER HISTORY
    // Store AR residual only; do NOT store tones here.
    // ========================================================

    if (model.noiseOrder > 0)
    {
        for (int k = model.noiseOrder - 1; k > 0; --k)
            noise_model_history[k] = noise_model_history[k - 1];

        noise_model_history[0] = sensor_axis2_ar_noise;
    }

    // ========================================================
    // GENERATE EXPLICIT IDENTIFIED TONES
    // ========================================================

    const double two_pi =
        6.283185307179586476925286766559;

    double sensor_time =
        global_time - regime_start_time;

    double sensor_axis2_tones = 0.0;

    for (int j = 0; j < model.numberOfTones; ++j)
    {
        sensor_axis2_tones +=
            model.toneAmplitude[j]
            * std::sin(
                two_pi
                * model.toneFrequency[j]
                * sensor_time
                + model.tonePhase[j]);
    }

    // ========================================================
    // COMPLETE IDENTIFIED DYNAMIC NOISE
    // ========================================================

    double sensor_axis2_noise =
        sensor_axis2_ar_noise
        + sensor_axis2_tones;

    noise_sensor_frame[0] = 0.0;
    noise_sensor_frame[1] = sensor_axis2_noise;
    noise_sensor_frame[2] = 0.0;

    // ========================================================
    // EXISTING SENSOR -> PLATFORM TRANSFORM
    // ========================================================

    for (int i = 0; i < 3; ++i)
    {
        noise_platform_frame[i] = 0.0;

        for (int j = 0; j < 3; ++j)
        {
            noise_platform_frame[i] +=
                frame_sens2plat_T[i][j]
                * noise_sensor_frame[j];
        }
    }

    for (int i = 0; i < 3; ++i)
        noise[i] = noise_platform_frame[i];

    // ========================================================
    // EXISTING ANGULAR RANDOM WALK REMAINS UNCHANGED
    // ========================================================

    for (int i = 0; i < 3; ++i)
    {
        random_walk[i] =
            random_walk_noise[i]
            + random_walk_convolution[i];
    }

    // ========================================================
    // EXISTING DELTA-MEASUREMENT LOGIC REMAINS UNCHANGED
    // ========================================================

    for (int i = 0; i < 3; ++i)
    {
        delta_noise[i] =
            noise[i]
            - internal_data.noise[i];

        // Continue with your existing delta_measurement[i]
        // calculation here.
        //
        // IMPORTANT ABOUT BIAS:
        // model.bias is available from the CSV. If your
        // existing sim already applies bias(i), do NOT also
        // add model.bias unless you intend to replace that
        // existing bias source with the test-derived bias.
    }

    // Continue with the remainder of your existing function.
}
