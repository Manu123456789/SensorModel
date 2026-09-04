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
%   all-pole noise shaping model
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

% Order of AR/all-pole stochastic noise model
noiseOrder = 10;

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
    % 7. FIT ALL-POLE NOISE SHAPING MODEL
    %
    % H(z) = noiseB / noiseA(z)
    %
    % Input to H(z) is unit-variance white Gaussian noise.
    % ---------------------------------------------------------

    [aNoise,noiseVar] = aryule(residual,noiseOrder);

    bNoise = sqrt(noiseVar);

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

    % Transfer-function coefficients
    sensorModel(i).noiseA   = aNoise;
    sensorModel(i).noiseB   = bNoise;
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

    fprintf('\nTones:\n')

    disp(table( ...
        toneFreq, ...
        toneAmp, ...
        tonePhase, ...
        'VariableNames', ...
        {'Frequency_Hz','Amplitude','Phase_rad'}))

    fprintf('noiseB = %.12g\n',bNoise)

    fprintf('noiseA = [')
    fprintf(' %.12g',aNoise)
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
% EXPORT ALL REGIMES TO ONE CSV FOR SIMULATION
%
% One row = one regime.
%
% Variable-length arrays are written as separate columns:
%   A0, A1, ..., Amax
%   ToneFreq1, ..., ToneFreqN
%   ToneAmp1,  ..., ToneAmpN
%   TonePhase1,..., TonePhaseN
%
% Unused columns for a given regime are NaN and are ignored by
% the C++ loader using NoiseOrder and NumTones.
% ============================================================

outputDirectory = 'YOUR_DIRECTORY';
modelCsv = fullfile(outputDirectory,'sensor_models.csv');

if ~exist(outputDirectory,'dir')
    mkdir(outputDirectory);
end

maxOrder = max(arrayfun(@(s) length(s.noiseA)-1, sensorModel));
maxTones = max(arrayfun(@(s) length(s.toneFreq), sensorModel));

names = {'Regime','Fs','Bias','NoiseOrder','NoiseB','NumTones'};

for k = 0:maxOrder
    names{end+1} = sprintf('A%d',k);
end
for j = 1:maxTones
    names{end+1} = sprintf('ToneFreq%d',j);
end
for j = 1:maxTones
    names{end+1} = sprintf('ToneAmp%d',j);
end
for j = 1:maxTones
    names{end+1} = sprintf('TonePhase%d',j);
end

modelData = nan(numRegimes,length(names));

aStart     = 7;
freqStart  = aStart + maxOrder + 1;
ampStart   = freqStart + maxTones;
phaseStart = ampStart + maxTones;

for i = 1:numRegimes
    order = length(sensorModel(i).noiseA)-1;
    nTone = length(sensorModel(i).toneFreq);

    modelData(i,1:6) = [ ...
        i, ...
        sensorModel(i).Fs, ...
        sensorModel(i).bias, ...
        order, ...
        sensorModel(i).noiseB, ...
        nTone];

    modelData(i,aStart:aStart+order) = ...
        sensorModel(i).noiseA(:).';

    if nTone > 0
        modelData(i,freqStart:freqStart+nTone-1) = ...
            sensorModel(i).toneFreq(:).';
        modelData(i,ampStart:ampStart+nTone-1) = ...
            sensorModel(i).toneAmp(:).';
        modelData(i,phaseStart:phaseStart+nTone-1) = ...
            sensorModel(i).tonePhase(:).';
    end
end

modelTable = array2table(modelData,'VariableNames',names);
writetable(modelTable,modelCsv);

fprintf('\nWrote all %d regimes to:\n%s\n',numRegimes,modelCsv);

%% ============================================================
% SELECT A REGIME FOR SIM IMPLEMENTATION
% ============================================================

regimeToUse = 2;

model = sensorModel(regimeToUse);

fprintf('\nMODEL FOR REGIME %d\n',regimeToUse)

fprintf('Bias = %.12g\n',model.bias)

fprintf('\nTone frequencies:\n')
disp(model.toneFreq)

fprintf('Tone amplitudes:\n')
disp(model.toneAmp)

fprintf('Tone phases:\n')
disp(model.tonePhase)

fprintf('noiseB = %.12g\n',model.noiseB)

fprintf('noiseA = [')
fprintf(' %.12g',model.noiseA)
fprintf(' ]\n')
