%% GYRO TONE + OPTIONAL WHITE-NOISE MODEL CORRELATION
% Minimal modification of the previous AR + tone correlation script.
%
% Required sensorModel fields:
%   Fs, residual, toneFreq, toneAmp, tonePhase
% Optional:
%   noiseRMS
%
% Primary reference:
%   testFull = residual + toneModel
%
% Comparisons:
%   1. Tone-only model vs full bias-removed test signal
%   2. Tone + Gaussian white noise vs full bias-removed test signal

clc;
close all;
rng(1); % Makes the stochastic ensemble repeatable

%% SETTINGS
regimeToUse = 2;
maxLagSec = 2;
toneBandHalfWidthHz = 0.5;
maxWelchLength = 512;
nRealizations = 500;
psdPercentiles = [2.5 97.5];

model = sensorModel(regimeToUse);
Fs = model.Fs;

%% BUILD TEST SIGNAL AND DETERMINISTIC TONES
residual = model.residual(:);
residual = residual - mean(residual);
N = length(residual);
t = (0:N-1)'/Fs;

toneModel = zeros(N,1);
for j = 1:length(model.toneFreq)
    toneModel = toneModel + model.toneAmp(j)*sin( ...
        2*pi*model.toneFreq(j)*t + model.tonePhase(j));
end
toneModel = toneModel - mean(toneModel);

% Primary test reference: bias removed, tones retained.
testFull = residual + toneModel;
testFull = testFull - mean(testFull);

%% BUILD SIMPLIFIED MODELS
% Tone-only model is deterministic.
modelTone = toneModel;

% Use measured residual RMS as white-noise standard deviation.
% If identification stored noiseRMS, use it directly.
if isfield(model,'noiseRMS') && isfinite(model.noiseRMS) && model.noiseRMS > 0
    whiteSigma = model.noiseRMS;
else
    whiteSigma = sqrt(mean(residual.^2));
end

% Each column is one independent tone + white-noise realization.
whiteNoise = whiteSigma*randn(N,nRealizations);
modelWhite = toneModel + whiteNoise;

% Remove small finite-record mean from each stochastic realization.
modelWhite = modelWhite - mean(modelWhite,1);

%% COMMON WELCH SETTINGS
segmentLength = min(maxWelchLength,N-1);
if segmentLength < 8
    error('Selected regime is too short for validation.')
end
window = hamming(segmentLength,'periodic');
overlap = floor(segmentLength/2);
nfft = max(256,2^nextpow2(segmentLength));

%% PSDs
[PtestFull,f] = pwelch(testFull,window,overlap,nfft,Fs);
[Ptone,~] = pwelch(modelTone,window,overlap,nfft,Fs);

% Compute each stochastic PSD first, then average LINEAR power.
[PwhiteEach,~] = pwelch(modelWhite,window,overlap,nfft,Fs);
Pwhite = mean(PwhiteEach,2);

%% CUMULATIVE INTEGRATED PSD POWER
cumPowerTest = cumtrapz(f,PtestFull);
cumPowerTone = cumtrapz(f,Ptone);
cumPowerWhite = cumtrapz(f,Pwhite);

totalPowerTest = trapz(f,PtestFull);
totalPowerTone = trapz(f,Ptone);
totalPowerWhite = trapz(f,Pwhite);

%% FULL-SIGNAL AUTOCORRELATION
maxLag = min(round(maxLagSec*Fs),N-1);

[Rtest,lags] = xcorr(testFull,maxLag,'coeff');
[Rtone,~] = xcorr(modelTone,maxLag,'coeff');

% Average ACF estimates across realizations, then normalize at zero lag.
Rwhite = zeros(size(Rtest));
for k = 1:nRealizations
    Rwhite = Rwhite + xcorr(modelWhite(:,k),maxLag,'biased');
end
Rwhite = Rwhite/nRealizations;
Rwhite = Rwhite/Rwhite(maxLag+1);

lagSec = lags/Fs;

%% OPTIONAL ALLAN DEVIATION - FULL SIGNAL
maxM = floor((N-2)/2);
m = unique(round(logspace(0,log10(maxM),35)));
m = m(m >= 1 & m < (N-1)/2);

[avarTest,tau] = allanvar(testFull,m,Fs);
avarTest = avarTest(:);
tau = tau(:);

avarTone = reshape(allanvar(modelTone,m,Fs),[],1);

avarWhite = zeros(numel(m),1);
for k = 1:nRealizations
    avarWhite = avarWhite + reshape(allanvar(modelWhite(:,k),m,Fs),[],1);
end

adevTest = sqrt(avarTest);
adevTone = sqrt(avarTone);
adevWhite = sqrt(avarWhite/nRealizations);

%% NUMERICAL METRICS
% Do NOT average stochastic time histories before RMS.
testRMS = sqrt(mean(testFull.^2));
toneRMS = sqrt(mean(modelTone.^2));
whiteRMS = sqrt(mean(modelWhite(:).^2));

toneRMSErrorPct = 100*(toneRMS-testRMS)/testRMS;
whiteRMSErrorPct = 100*(whiteRMS-testRMS)/testRMS;

testPSD_dB = 10*log10(max(PtestFull,realmin));
tonePSD_dB = 10*log10(max(Ptone,realmin));
whitePSD_dB = 10*log10(max(Pwhite,realmin));

tonePsdRMSE_dB = sqrt(mean((tonePSD_dB-testPSD_dB).^2));
whitePsdRMSE_dB = sqrt(mean((whitePSD_dB-testPSD_dB).^2));

tonePsdRelativeL2Pct = 100*norm(Ptone-PtestFull)/norm(PtestFull);
whitePsdRelativeL2Pct = 100*norm(Pwhite-PtestFull)/norm(PtestFull);

tonePowerErrorPct = 100*(totalPowerTone-totalPowerTest)/totalPowerTest;
whitePowerErrorPct = 100*(totalPowerWhite-totalPowerTest)/totalPowerTest;

toneAcfRMSE = sqrt(mean((Rtone-Rtest).^2));
whiteAcfRMSE = sqrt(mean((Rwhite-Rtest).^2));

validTone = adevTest > 0 & adevTone > 0;
validWhite = adevTest > 0 & adevWhite > 0;

allanToneRMSE_dB = sqrt(mean((20*log10(adevTone(validTone)) - ...
    20*log10(adevTest(validTone))).^2));

allanWhiteRMSE_dB = sqrt(mean((20*log10(adevWhite(validWhite)) - ...
    20*log10(adevTest(validWhite))).^2));

%% TONE-BAND POWER ERRORS
nTones = length(model.toneFreq);

testBandPower = zeros(nTones,1);
toneBandPower = zeros(nTones,1);
whiteBandPower = zeros(nTones,1);

for j = 1:nTones
    band = [max(0,model.toneFreq(j)-toneBandHalfWidthHz), ...
        min(Fs/2,model.toneFreq(j)+toneBandHalfWidthHz)];

    testBandPower(j) = bandpower(PtestFull,f,band,'psd');
    toneBandPower(j) = bandpower(Ptone,f,band,'psd');
    whiteBandPower(j) = bandpower(Pwhite,f,band,'psd');
end

toneBandErrorPct = 100*(toneBandPower-testBandPower)./testBandPower;
whiteBandErrorPct = 100*(whiteBandPower-testBandPower)./testBandPower;

toneMetrics = table( ...
    model.toneFreq(:),testBandPower,toneBandPower,toneBandErrorPct, ...
    whiteBandPower,whiteBandErrorPct, ...
    'VariableNames',{'Frequency_Hz','TestPower','ToneOnlyPower', ...
    'ToneOnlyError_pct','ToneWhitePower','ToneWhiteError_pct'});

%% PLOT FORMATTING
cTest = [0 0.4470 0.7410];
cModel = [0.4660 0.6740 0.1880];
cTone = [0.4940 0.1840 0.5560];

%% 1. PRIMARY PSD COMPARISONS
figure('Name','Simplified Sensor Model PSD');
tiledlayout(2,1);

nexttile;
semilogy(f,PtestFull,'Color',cTest,'LineWidth',2); hold on;
semilogy(f,Ptone,'Color',cTone,'LineWidth',2);
for j = 1:nTones
    xline(model.toneFreq(j),'--','Color',cTone, ...
        'LineWidth',1.2,'HandleVisibility','off');
end
grid on; xlim([0 Fs/2]);
xlabel('Frequency [Hz]'); ylabel('PSD [units^2/Hz]');
title('Full Bias-Removed Test vs Tone-Only Model');
legend('Test','Tone Only','Location','best');

nexttile;
semilogy(f,PtestFull,'Color',cTest,'LineWidth',2); hold on;
semilogy(f,Pwhite,'Color',cModel,'LineWidth',2);
for j = 1:nTones
    xline(model.toneFreq(j),'--','Color',cTone, ...
        'LineWidth',1.2,'HandleVisibility','off');
end
grid on; xlim([0 Fs/2]);
xlabel('Frequency [Hz]'); ylabel('PSD [units^2/Hz]');
title(sprintf('Full Test vs Tone + White Noise (%d-Run Mean PSD)',nRealizations));
legend('Test','Tone + White Noise','Location','best');

%% 2. CUMULATIVE INTEGRATED PSD POWER
figure('Name','Cumulative Integrated PSD Power');
plot(f,cumPowerTest,'Color',cTest,'LineWidth',2); hold on;
plot(f,cumPowerTone,'Color',cTone,'LineWidth',2);
plot(f,cumPowerWhite,'Color',cModel,'LineWidth',2);
grid on; xlim([0 Fs/2]);
xlabel('Frequency [Hz]');
ylabel('Cumulative Integrated PSD Power [units^2]');
title('Cumulative Spectral Power vs Frequency');
legend('Test','Tone Only','Tone + White Noise','Location','best');

%% 3. FULL-SIGNAL AUTOCORRELATION
figure('Name','Full-Signal Autocorrelation');
plot(lagSec,Rtest,'Color',cTest,'LineWidth',2); hold on;
plot(lagSec,Rtone,'Color',cTone,'LineWidth',2);
plot(lagSec,Rwhite,'Color',cModel,'LineWidth',2);
grid on;
xlabel('Lag [s]'); ylabel('Normalized Autocorrelation');
title('Full Bias-Removed Signal Autocorrelation');
legend('Test','Tone Only','Tone + White Noise Ensemble','Location','best');

%% 4. REPRESENTATIVE TIME HISTORIES
nPlot = min(N,round(5*Fs));

figure('Name','Representative Time Histories');
tiledlayout(2,1);

nexttile;
plot(t(1:nPlot),testFull(1:nPlot),'Color',cTest,'LineWidth',1); hold on;
plot(t(1:nPlot),modelTone(1:nPlot),'Color',cTone,'LineWidth',1);
grid on;
xlabel('Time [s]'); ylabel('Sensor Error');
title('Test vs Tone-Only Model');
legend('Test','Tone Only','Location','best');

nexttile;
plot(t(1:nPlot),testFull(1:nPlot),'Color',cTest,'LineWidth',1); hold on;
plot(t(1:nPlot),modelWhite(1:nPlot,1),'Color',cModel,'LineWidth',1);
grid on;
xlabel('Time [s]'); ylabel('Sensor Error');
title('Test vs Representative Tone + White-Noise Realization');
legend('Test','Tone + White Noise','Location','best');

%% 5. FULL-SIGNAL AMPLITUDE DISTRIBUTIONS
% Pool stochastic realizations; do not average their time histories.
ampBins = 60;
ampLimit = max([max(abs(testFull)),max(abs(modelTone)),max(abs(modelWhite(:)))]);
if ampLimit == 0
    ampLimit = 1;
end
ampEdges = linspace(-ampLimit,ampLimit,ampBins+1);

figure('Name','Full-Signal Amplitude Distributions');
histogram(testFull,ampEdges,'Normalization','pdf', ...
    'DisplayStyle','stairs','EdgeColor',cTest,'LineWidth',2);
hold on;
histogram(modelTone,ampEdges,'Normalization','pdf', ...
    'DisplayStyle','stairs','EdgeColor',cTone,'LineWidth',2);
histogram(modelWhite(:),ampEdges,'Normalization','pdf', ...
    'DisplayStyle','stairs','EdgeColor',cModel,'LineWidth',2);
grid on; xlim([-ampLimit ampLimit]);
xlabel('Bias-Removed Sensor Error');
ylabel('Probability Density');
title('Full-Signal Amplitude Distribution');
legend('Test','Tone Only',sprintf('Tone + White (%d runs pooled)',nRealizations), ...
    'Location','best');

%% 6. POINTWISE PSD PERCENTILE BAND
% Percentiles are calculated in linear power units across realizations.
psdBand = prctile(PwhiteEach,psdPercentiles,2);

figure('Name','Tone + White-Noise PSD Percentile Band');
fill([f(:); flipud(f(:))], ...
    [max(psdBand(:,1),realmin); flipud(max(psdBand(:,2),realmin))], ...
    [0.8 0.8 0.8],'EdgeColor','none','FaceAlpha',0.5);
hold on;
plot(f,max(PtestFull,realmin),'Color',cTest,'LineWidth',2);
plot(f,max(Pwhite,realmin),'Color',cModel,'LineWidth',2);
set(gca,'YScale','log');
grid on; xlim([0 Fs/2]);
xlabel('Frequency [Hz]'); ylabel('PSD [units^2/Hz]');
title('Tone + White Noise: Pointwise PSD Variation');
legend(sprintf('Pointwise %g-%g percentile band', ...
    psdPercentiles(1),psdPercentiles(2)), ...
    'Test',sprintf('Ensemble Mean (%d runs)',nRealizations), ...
    'Location','best');

%% 7. OPTIONAL ALLAN DEVIATION
figure('Name','Full-Signal Allan Deviation');
loglog(tau,adevTest,'Color',cTest,'LineWidth',2); hold on;
loglog(tau,adevTone,'Color',cTone,'LineWidth',2);
loglog(tau,adevWhite,'Color',cModel,'LineWidth',2);
grid on;
xlabel('Averaging Time, \tau [s]'); ylabel('Allan Deviation');
title('Full-Signal Allan Deviation');
legend('Test','Tone Only','Tone + White Noise Ensemble','Location','best');

%% NUMERICAL SUMMARY
fprintf('\n============================================================\n')
fprintf('SIMPLIFIED GYRO MODEL CORRELATION - REGIME %d\n',regimeToUse)
fprintf('White-noise sigma = %.6g | realizations = %d\n', ...
    whiteSigma,nRealizations)
fprintf('============================================================\n')

fprintf('\n--- RMS ------------------------------------------------------\n')
fprintf('Test RMS                 = %.6g\n',testRMS)
fprintf('Tone-only RMS            = %.6g | error = %.2f %%\n', ...
    toneRMS,toneRMSErrorPct)
fprintf('Tone + white RMS         = %.6g | error = %.2f %%\n', ...
    whiteRMS,whiteRMSErrorPct)

fprintf('\n--- PSD ------------------------------------------------------\n')
fprintf('Tone-only PSD RMSE       = %.3f dB\n',tonePsdRMSE_dB)
fprintf('Tone + white PSD RMSE    = %.3f dB\n',whitePsdRMSE_dB)
fprintf('Tone-only PSD Rel L2     = %.2f %%\n',tonePsdRelativeL2Pct)
fprintf('Tone + white PSD Rel L2  = %.2f %%\n',whitePsdRelativeL2Pct)

fprintf('\n--- INTEGRATED PSD POWER -------------------------------------\n')
fprintf('Test integrated power    = %.6g\n',totalPowerTest)
fprintf('Tone-only power          = %.6g | error = %.2f %%\n', ...
    totalPowerTone,tonePowerErrorPct)
fprintf('Tone + white power       = %.6g | error = %.2f %%\n', ...
    totalPowerWhite,whitePowerErrorPct)

fprintf('\n--- AUTOCORRELATION ------------------------------------------\n')
fprintf('Tone-only ACF RMSE       = %.6f\n',toneAcfRMSE)
fprintf('Tone + white ACF RMSE    = %.6f\n',whiteAcfRMSE)

fprintf('\n--- ALLAN DEVIATION (SECONDARY) ------------------------------\n')
fprintf('Tone-only Allan RMSE     = %.3f dB\n',allanToneRMSE_dB)
fprintf('Tone + white Allan RMSE  = %.3f dB\n',allanWhiteRMSE_dB)

fprintf('\n--- TONE-BAND POWER ------------------------------------------\n')
disp(toneMetrics)
fprintf('============================================================\n')
