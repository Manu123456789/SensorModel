%% GYRO AR + TONE MODEL CORRELATION
% Minimal modification of Model_Correlation_Tones_White_Full.
%
% Required sensorModel fields:
%   Fs, residual, toneFreq, toneAmp, tonePhase, noiseA, noiseB
%
% Primary reference:
%   testFull = residual + toneModel
%
% Comparisons:
%   1. AR stochastic output vs measured residual (filter validation)
%   2. AR + tones vs full bias-removed test signal

clc;
close all;
rng(1); % Makes the stochastic ensemble repeatable

%% SETTINGS
regimeToUse = 2;
maxLagSec = 2;
toneBandHalfWidthHz = 0.5;
maxWelchLength = 512;
nRealizations = 500;

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

%% BUILD AR + TONE MODEL
% AR CHANGE: this replaces the white-noise block in the tone/white script.
% Each column is one independent AR + tone realization.
% The burn-in removes the zero-initial-condition transient.
burnIn = max(10*(max(length(model.noiseA),length(model.noiseB))-1), ...
    round(5*Fs));
w = randn(N+burnIn,nRealizations);
arTemp = filter(model.noiseB,model.noiseA,w);
arNoise = arTemp(burnIn+1:end,:);

% Remove the small finite-record mean from each stochastic realization.
arNoise = arNoise - mean(arNoise,1);
modelFull = toneModel + arNoise;
modelFull = modelFull - mean(modelFull,1);

%% COMMON WELCH SETTINGS
segmentLength = min(maxWelchLength,N-1);
if segmentLength < 8
    error('Selected regime is too short for validation.')
end
window = hamming(segmentLength,'periodic');
overlap = floor(segmentLength/2);
nfft = max(256,2^nextpow2(segmentLength));

%% PSDs
% AR-only residual PSD comparison.
[Presidual,f] = pwelch(residual,window,overlap,nfft,Fs);
[ParEach,~] = pwelch(arNoise,window,overlap,nfft,Fs);
Par = mean(ParEach,2);

% Complete-signal PSD comparison.
[PtestFull,~] = pwelch(testFull,window,overlap,nfft,Fs);
[PmodelFullEach,~] = pwelch(modelFull,window,overlap,nfft,Fs);
PmodelFull = mean(PmodelFullEach,2);

%% CUMULATIVE INTEGRATED PSD POWER
cumPowerTest = cumtrapz(f,PtestFull);
cumPowerModel = cumtrapz(f,PmodelFull);

totalPowerTest = trapz(f,PtestFull);
totalPowerModel = trapz(f,PmodelFull);

%% FULL-SIGNAL AUTOCORRELATION
% This follows the method used in Model_Correlation_Tones_White_Full:
% average biased ACF estimates, then normalize the ensemble at zero lag.
maxLag = min(round(maxLagSec*Fs),N-1);

[Rtest,lags] = xcorr(testFull,maxLag,'coeff');
Rmodel = zeros(size(Rtest));
for k = 1:nRealizations
    Rmodel = Rmodel + xcorr(modelFull(:,k),maxLag,'biased');
end
Rmodel = Rmodel/nRealizations;
Rmodel = Rmodel/Rmodel(maxLag+1);

lagSec = lags/Fs;

%% AR-ONLY AUTOCORRELATION
[Rresidual,~] = xcorr(residual,maxLag,'coeff');
Rar = zeros(size(Rresidual));
for k = 1:nRealizations
    Rar = Rar + xcorr(arNoise(:,k),maxLag,'biased');
end
Rar = Rar/nRealizations;
Rar = Rar/Rar(maxLag+1);

%% ALLAN DEVIATION - FULL SIGNAL AND AR-ONLY RESIDUAL
maxM = floor((N-2)/2);
m = unique(round(logspace(0,log10(maxM),35)));
m = m(m >= 1 & m < (N-1)/2);

[avarTest,tau] = allanvar(testFull,m,Fs);
avarTest = avarTest(:);
tau = tau(:);

avarModel = zeros(numel(m),1);
for k = 1:nRealizations
    avarModel = avarModel + reshape(allanvar(modelFull(:,k),m,Fs),[],1);
end

[avarResidual,tauResidual] = allanvar(residual,m,Fs);
avarResidual = avarResidual(:);
tauResidual = tauResidual(:);

avarAR = zeros(numel(m),1);
for k = 1:nRealizations
    avarAR = avarAR + reshape(allanvar(arNoise(:,k),m,Fs),[],1);
end

adevTest = sqrt(avarTest);
adevModel = sqrt(avarModel/nRealizations);
adevResidual = sqrt(avarResidual);
adevAR = sqrt(avarAR/nRealizations);

%% NUMERICAL METRICS
% Do NOT average stochastic time histories before RMS.
residualRMS = sqrt(mean(residual.^2));
arRMS = sqrt(mean(arNoise(:).^2));
testRMS = sqrt(mean(testFull.^2));
modelRMS = sqrt(mean(modelFull(:).^2));

residualRMSErrorPct = 100*(arRMS-residualRMS)/residualRMS;
modelRMSErrorPct = 100*(modelRMS-testRMS)/testRMS;

residualPSD_dB = 10*log10(max(Presidual,realmin));
arPSD_dB = 10*log10(max(Par,realmin));
testPSD_dB = 10*log10(max(PtestFull,realmin));
modelPSD_dB = 10*log10(max(PmodelFull,realmin));

residualPsdRMSE_dB = sqrt(mean((arPSD_dB-residualPSD_dB).^2));
modelPsdRMSE_dB = sqrt(mean((modelPSD_dB-testPSD_dB).^2));

residualPsdRelativeL2Pct = 100*norm(Par-Presidual)/norm(Presidual);
modelPsdRelativeL2Pct = 100*norm(PmodelFull-PtestFull)/norm(PtestFull);

modelPowerErrorPct = 100*(totalPowerModel-totalPowerTest)/totalPowerTest;

residualAcfRMSE = sqrt(mean((Rar-Rresidual).^2));
modelAcfRMSE = sqrt(mean((Rmodel-Rtest).^2));

validFull = adevTest > 0 & adevModel > 0;
validResidual = adevResidual > 0 & adevAR > 0;

allanModelRMSE_dB = sqrt(mean((20*log10(adevModel(validFull)) - ...
    20*log10(adevTest(validFull))).^2));

allanResidualRMSE_dB = sqrt(mean((20*log10(adevAR(validResidual)) - ...
    20*log10(adevResidual(validResidual))).^2));

%% TONE-BAND POWER ERRORS
nTones = length(model.toneFreq);

testBandPower = zeros(nTones,1);
modelBandPower = zeros(nTones,1);

for j = 1:nTones
    band = [max(0,model.toneFreq(j)-toneBandHalfWidthHz), ...
        min(Fs/2,model.toneFreq(j)+toneBandHalfWidthHz)];

    testBandPower(j) = bandpower(PtestFull,f,band,'psd');
    modelBandPower(j) = bandpower(PmodelFull,f,band,'psd');
end

modelBandErrorPct = 100*(modelBandPower-testBandPower)./testBandPower;

toneMetrics = table( ...
    model.toneFreq(:),testBandPower,modelBandPower,modelBandErrorPct, ...
    'VariableNames',{'Frequency_Hz','TestPower','ARTonePower', ...
    'ARToneError_pct'});

%% PLOT FORMATTING
cTest = [0 0.4470 0.7410];
cModel = [0.4660 0.6740 0.1880];
cTone = [0.4940 0.1840 0.5560];

%% 1. PRIMARY PSD COMPARISONS
figure('Name','AR + Tone Sensor Model PSD');
tiledlayout(2,1);

nexttile;
semilogy(f,Presidual,'Color',cTest,'LineWidth',2); hold on;
semilogy(f,Par,'Color',cModel,'LineWidth',2);
grid on; xlim([0 Fs/2]);
xlabel('Frequency [Hz]'); ylabel('PSD [units^2/Hz]');
title(sprintf('Residual vs AR Model (%d-Run Mean PSD)',nRealizations));
legend('Test Residual','AR Model','Location','best');

nexttile;
semilogy(f,PtestFull,'Color',cTest,'LineWidth',2); hold on;
semilogy(f,PmodelFull,'Color',cModel,'LineWidth',2);
for j = 1:nTones
    xline(model.toneFreq(j),'--','Color',cTone, ...
        'LineWidth',1.2,'HandleVisibility','off');
end
grid on; xlim([0 Fs/2]);
xlabel('Frequency [Hz]'); ylabel('PSD [units^2/Hz]');
title(sprintf('Full Test vs AR + Tones (%d-Run Mean PSD)',nRealizations));
legend('Test','AR + Tones','Location','best');

%% 2. CUMULATIVE INTEGRATED PSD POWER
figure('Name','Cumulative Integrated PSD Power');
plot(f,cumPowerTest,'Color',cTest,'LineWidth',2); hold on;
plot(f,cumPowerModel,'Color',cModel,'LineWidth',2);
grid on; xlim([0 Fs/2]);
xlabel('Frequency [Hz]');
ylabel('Cumulative Integrated PSD Power [units^2]');
title('Cumulative Spectral Power vs Frequency');
legend('Test','AR + Tones','Location','best');

%% 3. FULL-SIGNAL AUTOCORRELATION
figure('Name','Full-Signal Autocorrelation');
plot(lagSec,Rtest,'Color',cTest,'LineWidth',2); hold on;
plot(lagSec,Rmodel,'Color',cModel,'LineWidth',2);
grid on;
xlabel('Lag [s]'); ylabel('Normalized Autocorrelation');
title('Full Bias-Removed Signal Autocorrelation');
legend('Test','AR + Tones Ensemble','Location','best');

%% 4. REPRESENTATIVE TIME HISTORIES
nPlot = min(N,round(5*Fs));

figure('Name','Representative Time Histories');
plot(t(1:nPlot),testFull(1:nPlot),'Color',cTest,'LineWidth',1); hold on;
plot(t(1:nPlot),modelFull(1:nPlot,1),'Color',cModel,'LineWidth',1);
grid on;
xlabel('Time [s]'); ylabel('Sensor Error');
title('Test vs Representative AR + Tone Realization');
legend('Test','AR + Tones','Location','best');

%% 5. FULL-SIGNAL AMPLITUDE DISTRIBUTIONS
% This is the single full-signal comparison from the tone/white script.
% The separate standardized "Amplitude Change 2" section is intentionally
% omitted. Pool realizations; do not average their time histories.
ampBins = 60;
ampLimit = max([max(abs(testFull)),max(abs(modelFull(:)))]);
if ampLimit == 0
    ampLimit = 1;
end
ampEdges = linspace(-ampLimit,ampLimit,ampBins+1);

figure('Name','Full-Signal Amplitude Distributions');
histogram(testFull,ampEdges,'Normalization','pdf', ...
    'DisplayStyle','stairs','EdgeColor',cTest,'LineWidth',2);
hold on;
histogram(modelFull(:),ampEdges,'Normalization','pdf', ...
    'DisplayStyle','stairs','EdgeColor',cModel,'LineWidth',2);
grid on; xlim([-ampLimit ampLimit]);
xlabel('Bias-Removed Sensor Error');
ylabel('Probability Density');
title('Full-Signal Amplitude Distribution');
legend('Test',sprintf('AR + Tones (%d runs pooled)',nRealizations), ...
    'Location','best');

%% 6. FULL-SIGNAL ALLAN DEVIATION
figure('Name','Full-Signal Allan Deviation');
loglog(tau,adevTest,'Color',cTest,'LineWidth',2); hold on;
loglog(tau,adevModel,'Color',cModel,'LineWidth',2);
grid on;
xlabel('Averaging Time, \tau [s]'); ylabel('Allan Deviation');
title('Full-Signal Allan Deviation');
legend('Test','AR + Tones Ensemble','Location','best');

%% 7. AR FILTER VALIDATION - RESIDUAL ONLY
% These plots isolate the stochastic filter so tones cannot hide an AR
% mismatch in the complete-signal comparisons above.
figure('Name','AR Filter Validation - Residual Only');
tiledlayout(3,1);

nexttile;
semilogy(f,Presidual,'Color',cTest,'LineWidth',2); hold on;
semilogy(f,Par,'Color',cModel,'LineWidth',2);
grid on; xlim([0 Fs/2]);
xlabel('Frequency [Hz]'); ylabel('PSD [units^2/Hz]');
title('Residual vs AR PSD');
legend('Test Residual','AR Ensemble','Location','best');

nexttile;
plot(lagSec,Rresidual,'Color',cTest,'LineWidth',2); hold on;
plot(lagSec,Rar,'Color',cModel,'LineWidth',2);
grid on;
xlabel('Lag [s]'); ylabel('Normalized Autocorrelation');
title('Residual vs AR Autocorrelation');
legend('Test Residual','AR Ensemble','Location','best');

nexttile;
loglog(tauResidual,adevResidual,'Color',cTest,'LineWidth',2); hold on;
loglog(tauResidual,adevAR,'Color',cModel,'LineWidth',2);
grid on;
xlabel('Averaging Time, \tau [s]'); ylabel('Allan Deviation');
title('Residual vs AR Allan Deviation');
legend('Test Residual','AR Ensemble','Location','best');

%% NUMERICAL SUMMARY
fprintf('\n============================================================\n')
fprintf('AR + TONE MODEL CORRELATION - REGIME %d\n',regimeToUse)
fprintf('Realizations = %d | AR order = %d\n', ...
    nRealizations,length(model.noiseA)-1)
fprintf('============================================================\n')

fprintf('\n--- RMS ------------------------------------------------------\n')
fprintf('Test residual RMS          = %.6g\n',residualRMS)
fprintf('AR ensemble RMS            = %.6g | error = %.2f %%\n', ...
    arRMS,residualRMSErrorPct)
fprintf('Full test RMS              = %.6g\n',testRMS)
fprintf('AR + tone RMS              = %.6g | error = %.2f %%\n', ...
    modelRMS,modelRMSErrorPct)

fprintf('\n--- PSD ------------------------------------------------------\n')
fprintf('Residual/AR PSD RMSE       = %.3f dB\n',residualPsdRMSE_dB)
fprintf('Full-signal PSD RMSE       = %.3f dB\n',modelPsdRMSE_dB)
fprintf('Residual/AR PSD Rel L2     = %.2f %%\n',residualPsdRelativeL2Pct)
fprintf('Full-signal PSD Rel L2     = %.2f %%\n',modelPsdRelativeL2Pct)

fprintf('\n--- INTEGRATED PSD POWER -------------------------------------\n')
fprintf('Test integrated power      = %.6g\n',totalPowerTest)
fprintf('AR + tone power            = %.6g | error = %.2f %%\n', ...
    totalPowerModel,modelPowerErrorPct)

fprintf('\n--- AUTOCORRELATION ------------------------------------------\n')
fprintf('Residual/AR ACF RMSE       = %.6f\n',residualAcfRMSE)
fprintf('Full-signal ACF RMSE       = %.6f\n',modelAcfRMSE)

fprintf('\n--- ALLAN DEVIATION (SECONDARY) ------------------------------\n')
fprintf('Residual/AR Allan RMSE     = %.3f dB\n',allanResidualRMSE_dB)
fprintf('Full-signal Allan RMSE     = %.3f dB\n',allanModelRMSE_dB)

fprintf('\n--- TONE-BAND POWER ------------------------------------------\n')
disp(toneMetrics)
fprintf('============================================================\n')
