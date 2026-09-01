%% ============================================================
% GYRO AR NOISE MODEL VALIDATION
%
% Required from identification script:
%   sensorModel(i).Fs
%   sensorModel(i).residual
%   sensorModel(i).toneFreq
%   sensorModel(i).toneAmp
%   sensorModel(i).tonePhase
%   sensorModel(i).noiseA
%   sensorModel(i).noiseB
%
% Generates:
%   1. Residual vs AR PSD
%   2. Full test-noise vs full reconstructed-model PSD
%   3. Residual vs AR autocorrelation
%   4. Residual vs AR Allan deviation
%
% Quantitative outputs:
%   - PSD RMSE [dB]
%   - PSD MAE [dB]
%   - PSD relative L2 error
%   - RMS error
%   - Tone frequency / peak / bandpower errors
%   - Autocorrelation RMSE and relative L2 error
%   - Allan-deviation RMSE [dB]
% ============================================================

clc;
close all;

rng(1);


%% ============================================================
% USER SETTINGS
%
% Select identified regime and basic analysis settings.
% ============================================================

regimeToUse = 2;

model = sensorModel(regimeToUse);

Fs = model.Fs;

% AR startup transient to discard
burnInSamples = max(10*(length(model.noiseA)-1), round(5*Fs));

% Maximum lag shown in autocorrelation
maxLagSec = 2;

% Half-width used when evaluating each tone
toneBandHalfWidthHz = 0.5;

% Frequency range used for PSD metrics
freqRangeHz = [0 Fs/2];


%% ============================================================
% PLOT FORMATTING
%
% Requested:
%   Line width = 2
%   Font size  = 12
%   Bold font
%   No red plot lines
% ============================================================

set(groot, ...
    'defaultLineLineWidth',2, ...
    'defaultAxesFontSize',12, ...
    'defaultAxesFontWeight','bold', ...
    'defaultTextFontSize',12, ...
    'defaultTextFontWeight','bold');

% Plot colors
cTest  = [0.0000 0.4470 0.7410];   % Blue
cModel = [0.4660 0.6740 0.1880];   % Green
cTone  = [0.4940 0.1840 0.5560];   % Purple


%% ============================================================
% PREPARE TEST AND MODEL DATA
%
% The AR filter was identified from:
%
%   residual = debiased test data - explicit tone model
%
% Therefore:
%
%   residual      <-> AR model
%
% while:
%
%   residual + tones
%
% should be compared against:
%
%   AR model + tones
% ============================================================

residual = model.residual(:);

N = length(residual);

t = (0:N-1)'/Fs;


% ------------------------------------------------------------
% Reconstruct explicit tone model
% ------------------------------------------------------------

toneModel = zeros(N,1);

for j = 1:length(model.toneFreq)

    toneModel = toneModel + ...
        model.toneAmp(j) .* ...
        sin(2*pi*model.toneFreq(j).*t + model.tonePhase(j));

end


% This reconstructs the original debiased signal used before
% tone subtraction:
testFull = residual + toneModel;


% ------------------------------------------------------------
% Generate independent AR realization
%
% MATLAB equivalent:
%
%   noise = filter(noiseB,noiseA,randn(...))
%
% Burn-in is discarded to remove startup effects.
% ------------------------------------------------------------

w = randn(N + burnInSamples,1);

arTemp = filter(model.noiseB,model.noiseA,w);

arNoise = arTemp(burnInSamples+1:end);


% Complete model excluding bias:
modelFull = arNoise + toneModel;


% Remove small finite-record means from stochastic signals
residual = residual - mean(residual);
arNoise  = arNoise  - mean(arNoise);


%% ============================================================
% 1. RESIDUAL VS AR MODEL PSD
%
% WHY:
% The AR model was fitted specifically to the residual.
%
% WHAT WE LEARN:
% Whether the generated AR process reproduces:
%   - residual spectral shape
%   - broadband noise power
%   - residual RMS
%
% This is the primary validation of the stochastic model.
% ============================================================

[Ptest,f] = pwelch(residual,[],[],[],Fs);

[Par,fAR] = pwelch(arNoise,[],[],[],Fs);


% Ensure common frequency vector
if length(fAR) ~= length(f) || any(abs(fAR-f) > 1e-12)

    Par = interp1(fAR,Par,f,'linear','extrap');

end


freqMask = ...
    f >= freqRangeHz(1) & ...
    f <= freqRangeHz(2);


Ptest_dB = 10*log10(max(Ptest,realmin));

Par_dB = 10*log10(max(Par,realmin));


% ------------------------------------------------------------
% PSD quantitative metrics
% ------------------------------------------------------------

psdError_dB = Par_dB(freqMask) - Ptest_dB(freqMask);

psdRMSE_dB = sqrt(mean(psdError_dB.^2));

psdMAE_dB = mean(abs(psdError_dB));


psdRelativeL2 = ...
    norm(Par(freqMask)-Ptest(freqMask)) / ...
    norm(Ptest(freqMask));


% ------------------------------------------------------------
% RMS comparison
% ------------------------------------------------------------

testRMS = sqrt(mean(residual.^2));

arRMS = sqrt(mean(arNoise.^2));


rmsErrorPct = ...
    100*(arRMS-testRMS)/testRMS;


% PSD-integrated RMS
testRMS_PSD = sqrt(trapz(f,Ptest));

arRMS_PSD = sqrt(trapz(f,Par));


% ------------------------------------------------------------
% Plot
% ------------------------------------------------------------

figure('Name','Residual vs AR PSD');

semilogy(f,Ptest, ...
    'Color',cTest);

hold on;

semilogy(f,Par, ...
    'Color',cModel);

grid on;

xlim(freqRangeHz);

xlabel('Frequency [Hz]');
ylabel('PSD [units^2/Hz]');

title('Test Residual vs AR Model PSD');

lgd = legend( ...
    'Test Residual', ...
    'AR Model', ...
    'Location','best');

lgd.FontSize = 12;
lgd.FontWeight = 'bold';


%% ============================================================
% 2. FULL TEST NOISE VS COMPLETE MODEL PSD + TONE METRICS
%
% WHY:
% The AR residual intentionally does NOT contain the explicit tones.
%
% Full comparison:
%
%   test residual + fitted tones
%
%           versus
%
%   AR realization + fitted tones
%
% WHAT WE LEARN:
% Whether the complete model reproduces the measured spectral
% peaks once the explicit tone model and AR residual are combined.
% ============================================================

[PfullTest,fFull] = pwelch(testFull,[],[],[],Fs);

[PfullModel,fFullModel] = pwelch(modelFull,[],[],[],Fs);


if length(fFullModel) ~= length(fFull) || ...
        any(abs(fFullModel-fFull) > 1e-12)

    PfullModel = interp1( ...
        fFullModel, ...
        PfullModel, ...
        fFull, ...
        'linear', ...
        'extrap');

end


figure('Name','Complete Noise Model PSD');

semilogy(fFull,PfullTest, ...
    'Color',cTest);

hold on;

semilogy(fFull,PfullModel, ...
    'Color',cModel);


% Mark expected tone frequencies
for j = 1:length(model.toneFreq)

    xline( ...
        model.toneFreq(j), ...
        '--', ...
        'Color',cTone, ...
        'LineWidth',2);

end


grid on;

xlim(freqRangeHz);

xlabel('Frequency [Hz]');
ylabel('PSD [units^2/Hz]');

title('Test Noise vs Complete AR + Tone Model PSD');

lgd = legend( ...
    'Test Noise', ...
    'AR + Tone Model', ...
    'Identified Tone Frequency', ...
    'Location','best');

lgd.FontSize = 12;
lgd.FontWeight = 'bold';


%% ============================================================
% QUANTITATIVE TONE METRICS
%
% For each expected tone:
%   - Find local test PSD peak
%   - Find local model PSD peak
%   - Compare peak frequency
%   - Compare peak PSD
%   - Compare integrated local bandpower
%
% Bandpower is useful because a single PSD bin can vary due to
% finite record length and Welch estimation.
% ============================================================

nTone = length(model.toneFreq);


Tone = (1:nTone)';

ExpectedFreq_Hz = model.toneFreq(:);

TestPeakFreq_Hz  = nan(nTone,1);
ModelPeakFreq_Hz = nan(nTone,1);

FreqError_Hz = nan(nTone,1);

TestPeakPSD_dB  = nan(nTone,1);
ModelPeakPSD_dB = nan(nTone,1);

PeakError_dB = nan(nTone,1);

TestBandPower  = nan(nTone,1);
ModelBandPower = nan(nTone,1);

BandPowerError_pct = nan(nTone,1);


for j = 1:nTone

    f0 = model.toneFreq(j);

    band = ...
        fFull >= max(0,f0-toneBandHalfWidthHz) & ...
        fFull <= min(Fs/2,f0+toneBandHalfWidthHz);


    fLocal = fFull(band);

    Pt = PfullTest(band);

    Pm = PfullModel(band);


    % Peak values
    [testPeak,kTest] = max(Pt);

    [modelPeak,kModel] = max(Pm);


    TestPeakFreq_Hz(j) = fLocal(kTest);

    ModelPeakFreq_Hz(j) = fLocal(kModel);


    FreqError_Hz(j) = ...
        ModelPeakFreq_Hz(j) - ...
        TestPeakFreq_Hz(j);


    TestPeakPSD_dB(j) = ...
        10*log10(max(testPeak,realmin));

    ModelPeakPSD_dB(j) = ...
        10*log10(max(modelPeak,realmin));


    PeakError_dB(j) = ...
        ModelPeakPSD_dB(j) - ...
        TestPeakPSD_dB(j);


    % Integrated power around tone
    TestBandPower(j) = trapz(fLocal,Pt);

    ModelBandPower(j) = trapz(fLocal,Pm);


    BandPowerError_pct(j) = ...
        100 * ...
        (ModelBandPower(j)-TestBandPower(j)) / ...
        TestBandPower(j);

end


toneMetrics = table( ...
    Tone, ...
    ExpectedFreq_Hz, ...
    TestPeakFreq_Hz, ...
    ModelPeakFreq_Hz, ...
    FreqError_Hz, ...
    TestPeakPSD_dB, ...
    ModelPeakPSD_dB, ...
    PeakError_dB, ...
    TestBandPower, ...
    ModelBandPower, ...
    BandPowerError_pct);


%% ============================================================
% 3. TEST RESIDUAL VS AR MODEL AUTOCORRELATION
%
% WHY:
% PSD measures frequency-domain behavior.
%
% Autocorrelation directly checks the temporal memory that the
% AR model is designed to reproduce.
%
% WHAT WE LEARN:
% Whether the generated model retains approximately the same
% sample-to-sample correlation structure as the measured residual.
% ============================================================

maxLagSamples = ...
    min(round(maxLagSec*Fs),N-1);


[Rtest,lags] = xcorr( ...
    residual, ...
    maxLagSamples, ...
    'coeff');


[Rar,~] = xcorr( ...
    arNoise, ...
    maxLagSamples, ...
    'coeff');


lagSec = lags/Fs;


% ------------------------------------------------------------
% Quantitative ACF metrics
% ------------------------------------------------------------

acfDifference = Rar-Rtest;


acfRMSE = ...
    sqrt(mean(acfDifference.^2));


acfRelativeL2 = ...
    norm(acfDifference) / ...
    norm(Rtest);


offZero = lags ~= 0;


acfRMSE_offZero = ...
    sqrt(mean(acfDifference(offZero).^2));


% ------------------------------------------------------------
% Plot
% ------------------------------------------------------------

figure('Name','Residual vs AR Autocorrelation');

plot(lagSec,Rtest, ...
    'Color',cTest);

hold on;

plot(lagSec,Rar, ...
    'Color',cModel);

grid on;

xlabel('Lag [s]');
ylabel('Normalized Autocorrelation');

title('Test Residual vs AR Model Autocorrelation');

lgd = legend( ...
    'Test Residual', ...
    'AR Model', ...
    'Location','best');

lgd.FontSize = 12;
lgd.FontWeight = 'bold';


%% ============================================================
% 4. TEST RESIDUAL VS AR MODEL ALLAN DEVIATION
%
% WHY:
% Allan deviation examines stochastic behavior over different
% averaging times rather than only in frequency.
%
% WHAT WE LEARN:
% Whether the test residual and AR model behave similarly over
% short and long observation intervals.
%
% This is used as an additional model-validation metric rather
% than attempting to classify the entire model as angular
% random walk.
% ============================================================

maxCluster = floor(N/4);


mValues = unique(round(logspace( ...
    0, ...
    log10(maxCluster), ...
    35)));


mValues = mValues( ...
    mValues >= 1 & ...
    2*mValues < N);


[tauTest,adevTest] = ...
    calcAllanDeviation(residual,Fs,mValues);


[tauAR,adevAR] = ...
    calcAllanDeviation(arNoise,Fs,mValues);


% Both functions use same m values, so tau should match
valid = ...
    adevTest > 0 & ...
    adevAR > 0 & ...
    isfinite(adevTest) & ...
    isfinite(adevAR);


allanError_dB = ...
    20*log10(adevAR(valid)) - ...
    20*log10(adevTest(valid));


allanRMSE_dB = ...
    sqrt(mean(allanError_dB.^2));


allanMAE_dB = ...
    mean(abs(allanError_dB));


% ------------------------------------------------------------
% Plot
% ------------------------------------------------------------

figure('Name','Residual vs AR Allan Deviation');

loglog( ...
    tauTest, ...
    adevTest, ...
    'Color',cTest);

hold on;

loglog( ...
    tauAR, ...
    adevAR, ...
    'Color',cModel);

grid on;

xlabel('Averaging Time, \tau [s]');
ylabel('Allan Deviation');

title('Test Residual vs AR Model Allan Deviation');

lgd = legend( ...
    'Test Residual', ...
    'AR Model', ...
    'Location','best');

lgd.FontSize = 12;
lgd.FontWeight = 'bold';


%% ============================================================
% SUMMARY RESULTS
%
% These are the main numerical results useful for a report or
% presentation alongside the plots.
% ============================================================

fprintf('\n')
fprintf('============================================================\n')
fprintf('GYRO AR MODEL VALIDATION - REGIME %d\n',regimeToUse)
fprintf('============================================================\n')

fprintf('\n--- RESIDUAL PSD --------------------------------------------\n')

fprintf('PSD RMSE                = %.4f dB\n',psdRMSE_dB)
fprintf('PSD MAE                 = %.4f dB\n',psdMAE_dB)
fprintf('PSD Relative L2 Error   = %.6f\n',psdRelativeL2)

fprintf('\n')

fprintf('Test Residual RMS       = %.10g\n',testRMS)
fprintf('AR Model RMS            = %.10g\n',arRMS)
fprintf('RMS Error               = %.3f %%\n',rmsErrorPct)

fprintf('\n')

fprintf('Test RMS from PSD       = %.10g\n',testRMS_PSD)
fprintf('AR RMS from PSD         = %.10g\n',arRMS_PSD)


fprintf('\n--- AUTOCORRELATION -----------------------------------------\n')

fprintf('ACF RMSE                = %.6f\n',acfRMSE)
fprintf('ACF Relative L2 Error   = %.6f\n',acfRelativeL2)
fprintf('Off-Zero ACF RMSE       = %.6f\n',acfRMSE_offZero)


fprintf('\n--- ALLAN DEVIATION -----------------------------------------\n')

fprintf('Allan RMSE              = %.4f dB\n',allanRMSE_dB)
fprintf('Allan MAE               = %.4f dB\n',allanMAE_dB)


fprintf('\n--- TONE METRICS --------------------------------------------\n')

disp(toneMetrics)

fprintf('============================================================\n')


%% ============================================================
% STORE VALIDATION RESULTS
%
% Convenient structure if values need to be used later for
% tables, reports, or presentation figures.
% ============================================================

validation = struct;


validation.regime = regimeToUse;


validation.PSD.RMSE_dB = psdRMSE_dB;
validation.PSD.MAE_dB = psdMAE_dB;
validation.PSD.relativeL2 = psdRelativeL2;

validation.PSD.f = f;
validation.PSD.test = Ptest;
validation.PSD.AR = Par;


validation.RMS.test = testRMS;
validation.RMS.AR = arRMS;
validation.RMS.error_pct = rmsErrorPct;

validation.RMS.test_PSD = testRMS_PSD;
validation.RMS.AR_PSD = arRMS_PSD;


validation.Tones = toneMetrics;


validation.ACF.RMSE = acfRMSE;
validation.ACF.relativeL2 = acfRelativeL2;
validation.ACF.offZeroRMSE = acfRMSE_offZero;

validation.ACF.lagSec = lagSec;
validation.ACF.test = Rtest;
validation.ACF.AR = Rar;


validation.Allan.RMSE_dB = allanRMSE_dB;
validation.Allan.MAE_dB = allanMAE_dB;

validation.Allan.tau = tauTest;
validation.Allan.test = adevTest;
validation.Allan.AR = adevAR;


%% ============================================================
% LOCAL FUNCTION - OVERLAPPING ALLAN DEVIATION
%
% Calculates Allan deviation from uniformly sampled rate data.
% ============================================================

function [tau,adev] = calcAllanDeviation(x,Fs,mValues)

x = x(:);

N = length(x);

mValues = mValues(:);


tau = nan(size(mValues));

adev = nan(size(mValues));


% Cumulative sum allows efficient moving averages
cs = [0; cumsum(x)];


for i = 1:length(mValues)

    m = mValues(i);


    if 2*m >= N
        continue
    end


    % All overlapping m-sample averages
    avg = ...
        (cs(m+1:end)-cs(1:end-m))/m;


    % Difference between averages separated by m samples
    d = ...
        avg(m+1:end)-avg(1:end-m);


    allanVar = ...
        0.5*mean(d.^2);


    tau(i) = m/Fs;

    adev(i) = sqrt(allanVar);

end


valid = ...
    isfinite(tau) & ...
    isfinite(adev);


tau = tau(valid);

adev = adev(valid);

end