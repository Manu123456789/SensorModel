%% ============================================================
% SENSOR ERROR MODEL IDENTIFICATION FROM TEST DATA
%
% Identifies for each regime:
%
%   bias
%   tone frequencies
%   tone amplitudes
%   tone phases
%   residual PSD
%   residual noise RMS
%   ARMA pole-zero noise shaping model
%
% Model:
%
% error = bias + tones + shaped stochastic noise
% ============================================================

clear; clc; close all;

rng(1);

%% ============================================================
% USER INPUTS
% ============================================================

xTest = YOUR_DATA(:);             % Full sensor test data

Fs_in = 1000;                     % Original sample rate [Hz]
Fs    = 80;                       % Downsampled rate [Hz]

baseline = 0;                     % Expected stationary reading

% Original-data regime indices
ts = [1      30001  60001];
te = [30000  60000  90000];

% Number of dominant tones to identify in each regime
nTones = [4 3 4];

% ARMA stochastic noise-model orders
arOrder = 10;
maOrder = 4;

%% ============================================================
% DOWNSAMPLE - NO ANTI-ALIAS FILTER
% ============================================================

ratio = Fs_in/Fs;

keepIdx = unique(round(1:ratio:length(xTest)));

x_ds = xTest(keepIdx);

%% ============================================================
% MAP ORIGINAL REGIMES TO DOWNSAMPLED DATA
% ============================================================

numRegimes = length(ts);

ts_ds = zeros(size(ts));
te_ds = zeros(size(te));

for i = 1:numRegimes

    ts_ds(i) = find(keepIdx >= ts(i),1,'first');
    te_ds(i) = find(keepIdx <= te(i),1,'last');

end

%% ============================================================
% IDENTIFY MODEL FOR EACH REGIME
% ============================================================

sensorModel = struct;

for i = 1:numRegimes

    %% Extract regime

    xr = x_ds(ts_ds(i):te_ds(i));

    L = length(xr);

    t = (0:L-1)'/Fs;

    %% --------------------------------------------------------
    % 1. BIAS
    % ---------------------------------------------------------

    bias = mean(xr) - baseline;

    x0 = xr - mean(xr);

    %% --------------------------------------------------------
    % 2. FFT
    % ---------------------------------------------------------

    Y = fft(x0);

    P = abs(Y/L);
    P = P(1:floor(L/2)+1);

    if rem(L,2) == 0
        P(2:end-1) = 2*P(2:end-1);
    else
        P(2:end) = 2*P(2:end);
    end

    f_fft = (0:floor(L/2))' * Fs/L;

    %% --------------------------------------------------------
    % 3. FIND DOMINANT TONES
    % ---------------------------------------------------------

    Psearch = P;

    % Do not identify DC as a tone
    Psearch(1) = 0;

    [~,peakLoc] = findpeaks( ...
        Psearch, ...
        'SortStr','descend');

    n = min(nTones(i),length(peakLoc));

    peakLoc = peakLoc(1:n);

    toneFreq = sort(f_fft(peakLoc));

    %% --------------------------------------------------------
    % 4. FIT TONE AMPLITUDES + PHASES
    % ---------------------------------------------------------

    H = zeros(L,2*n);

    for j = 1:n

        H(:,2*j-1) = ...
            sin(2*pi*toneFreq(j)*t);

        H(:,2*j) = ...
            cos(2*pi*toneFreq(j)*t);

    end

    beta = H\x0;

    toneModel = H*beta;

    toneAmp   = zeros(n,1);
    tonePhase = zeros(n,1);

    for j = 1:n

        a = beta(2*j-1);
        b = beta(2*j);

        toneAmp(j)   = hypot(a,b);
        tonePhase(j) = atan2(b,a);

    end

    %% --------------------------------------------------------
    % 5. REMOVE TONES
    % ---------------------------------------------------------

    residual = x0 - toneModel;

    %% --------------------------------------------------------
    % 6. PSD + RMS OF RESIDUAL NOISE
    % ---------------------------------------------------------

    [pxx,f] = pwelch(residual,[],[],[],Fs);

    noisePower = trapz(f,pxx);
    noiseRMS   = sqrt(noisePower);

    %% --------------------------------------------------------
    % 7. FIT ARMA NOISE SHAPING MODEL
    %
    % A(q) r[k] = C(q) e[k]
    %
    % e[k] has variance noiseVar. For simulation with a
    % unit-variance white Gaussian input w[k], define
    %
    % H(z) = noiseB(z) / noiseA(z)
    %      = sqrt(noiseVar)*C(z) / A(z)
    % ---------------------------------------------------------

    armaData = iddata(residual,[],1/Fs);

    armaModel = armax(armaData,[arOrder maOrder]);

    aNoise = armaModel.A;
    cNoise = armaModel.C;
    noiseVar = armaModel.NoiseVariance;

    % Effective numerator for unit-variance white Gaussian input.
    bNoise = sqrt(noiseVar) * cNoise;

    %% --------------------------------------------------------
    % 8. STORE MODEL
    % ---------------------------------------------------------

    sensorModel(i).Fs = Fs;

    sensorModel(i).bias = bias;

    sensorModel(i).toneFreq  = toneFreq;
    sensorModel(i).toneAmp   = toneAmp;
    sensorModel(i).tonePhase = tonePhase;

    sensorModel(i).PSDfreq = f;
    sensorModel(i).PSD     = pxx;

    sensorModel(i).noisePower = noisePower;
    sensorModel(i).noiseRMS   = noiseRMS;

    % ARMA transfer-function coefficients for unit white input.
    sensorModel(i).noiseA   = aNoise;
    sensorModel(i).noiseB   = bNoise;
    sensorModel(i).noiseC   = cNoise;
    sensorModel(i).noiseVar = noiseVar;

    sensorModel(i).residual = residual;

    %% --------------------------------------------------------
    % DISPLAY RESULTS
    % ---------------------------------------------------------

    fprintf('\n============================\n')
    fprintf('REGIME %d\n',i)
    fprintf('============================\n')

    fprintf('Bias      = %.6g\n',bias)
    fprintf('Noise RMS = %.6g\n',noiseRMS)
    fprintf('AR order  = %d\n',arOrder)
    fprintf('MA order  = %d\n',maOrder)

    fprintf('\nTones:\n')

    disp(table( ...
        toneFreq, ...
        toneAmp, ...
        tonePhase, ...
        'VariableNames', ...
        {'Frequency_Hz','Amplitude','Phase_rad'}))

    fprintf('noiseA = [')
    fprintf(' %.12g',aNoise)
    fprintf(' ]\n')

    fprintf('noiseB = [')
    fprintf(' %.12g',bNoise)
    fprintf(' ]\n')

    %% --------------------------------------------------------
    % PLOTS
    % ---------------------------------------------------------

    figure

    subplot(3,1,1)

    plot(xr)
    grid on

    xlabel('Downsampled Sample')
    ylabel('Sensor Output')
    title(sprintf('Regime %d - Test Data',i))

    subplot(3,1,2)

    plot(f_fft,P)
    grid on
    xlim([0 Fs/2])

    xlabel('Frequency [Hz]')
    ylabel('Amplitude')
    title('FFT')

    subplot(3,1,3)

    plot(f,pxx)
    grid on
    xlim([0 Fs/2])

    xlabel('Frequency [Hz]')
    ylabel('PSD [units^2/Hz]')

    title(sprintf( ...
        'Residual Noise PSD | RMS = %.4g', ...
        noiseRMS))

end

%% ============================================================
% EXPORT ONE CSV PER REGIME FOR SIMULATION
%
% File naming:
%   sensor_model_regime_1.csv
%   sensor_model_regime_2.csv
%   ...
%
% ARMA form used by the simulation:
%
%   H(z) = noise_model_B(z) / noise_model_A(z)
%
% where noise_model_B already includes sqrt(noiseVar), so the
% simulation input is unit-variance white Gaussian noise.
%
% CSV columns:
%   ar_order
%   ma_order
%   number_of_tones
%   tone_frequency
%   tone_amplitude
%   tone_phase
%   noise_model_A
%   noise_model_B
% ============================================================

outputDirectory = 'YOUR_DIRECTORY';

if ~exist(outputDirectory,'dir')
    mkdir(outputDirectory);
end

for i = 1:numRegimes

    model = sensorModel(i);

    ar_order        = length(model.noiseA)-1;
    ma_order        = length(model.noiseB)-1;
    number_of_tones = length(model.toneFreq);

    % Enough rows for both AR and MA coefficients and tone values.
    nRows = max([ ...
        length(model.noiseA), ...
        length(model.noiseB), ...
        number_of_tones]);

    tone_frequency = nan(nRows,1);
    tone_amplitude = nan(nRows,1);
    tone_phase     = nan(nRows,1);
    noise_model_A  = nan(nRows,1);
    noise_model_B  = nan(nRows,1);

    tone_frequency(1:number_of_tones) = model.toneFreq(:);
    tone_amplitude(1:number_of_tones) = model.toneAmp(:);
    tone_phase(1:number_of_tones)     = model.tonePhase(:);

    noise_model_A(1:length(model.noiseA)) = model.noiseA(:);
    noise_model_B(1:length(model.noiseB)) = model.noiseB(:);

    % Repeat scalar values down the file. The C++ loader only
    % needs the first row for these values.
    ar_order_col        = repmat(ar_order,nRows,1);
    ma_order_col        = repmat(ma_order,nRows,1);
    number_of_tones_col = repmat(number_of_tones,nRows,1);

    T = table( ...
        ar_order_col, ...
        ma_order_col, ...
        number_of_tones_col, ...
        tone_frequency, ...
        tone_amplitude, ...
        tone_phase, ...
        noise_model_A, ...
        noise_model_B, ...
        'VariableNames',{ ...
        'ar_order', ...
        'ma_order', ...
        'number_of_tones', ...
        'tone_frequency', ...
        'tone_amplitude', ...
        'tone_phase', ...
        'noise_model_A', ...
        'noise_model_B'});

    csvName = sprintf('sensor_model_regime_%d.csv',i);
    csvPath = fullfile(outputDirectory,csvName);

    writetable(T,csvPath);

    fprintf('Wrote regime %d ARMA model to: %s\n',i,csvPath);
end
