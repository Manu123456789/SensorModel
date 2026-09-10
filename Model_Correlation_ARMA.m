%% GYRO ARMA + TONE MODEL CORRELATION - ENSEMBLE AVERAGE
% Required sensorModel fields:
% Fs, residual, toneFreq, toneAmp, tonePhase, noiseA, noiseB
%
% noiseA = ARMA denominator A(z)
% noiseB = effective numerator sqrt(noiseVar)*C(z)

clc;
close all;
rng(1); % Makes the complete 500-realization ensemble repeatable

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

testFull = residual + toneModel;
testFull = testFull - mean(testFull);

%% BUILD 500 INDEPENDENT ARMA + TONE REALIZATIONS
% Each matrix column is one independent realization. The effective
% numerator model.noiseB already includes sqrt(noiseVar), so w is unit
% Gaussian white noise.
arOrder = length(model.noiseA)-1;
maOrder = length(model.noiseB)-1;
burnIn = max(10*max(arOrder,maOrder),round(5*Fs));

w = randn(N+burnIn,nRealizations);
armaTemp = filter(model.noiseB,model.noiseA,w);
armaNoise = armaTemp(burnIn+1:end,:);
armaNoise = armaNoise - mean(armaNoise,1);

modelFull = armaNoise + toneModel;
modelFull = modelFull - mean(modelFull,1);

%% COMMON WELCH SETTINGS
segmentLength = min(maxWelchLength,N-1);
if segmentLength < 8
    error('Selected regime is too short for validation.')
end
window = hamming(segmentLength,'periodic');
overlap = floor(segmentLength/2);
nfft = max(256,2^nextpow2(segmentLength));

%% 1. RESIDUAL VS ENSEMBLE-MEAN ARMA STOCHASTIC PSD
[Presidual,f] = pwelch(residual,window,overlap,nfft,Fs);
[ParmaEach,~] = pwelch(armaNoise,window,overlap,nfft,Fs);
Parma = mean(ParmaEach,2); % Average power first, never dB

%% 2. FULL TEST VS ENSEMBLE-MEAN ARMA + TONES PSD
[PtestFull,~] = pwelch(testFull,window,overlap,nfft,Fs);
[PmodelFullEach,~] = pwelch(modelFull,window,overlap,nfft,Fs);
PmodelFull = mean(PmodelFullEach,2);

%% 3. DIFFERENCED TEST VS ENSEMBLE-MEAN DIFFERENCED MODEL
deltaTest = diff(testFull);
deltaTest = deltaTest - mean(deltaTest);
deltaModel = diff(modelFull,1,1);
deltaModel = deltaModel - mean(deltaModel,1);

[PdeltaTest,~] = pwelch(deltaTest,window,overlap,nfft,Fs);
[PdeltaModelEach,~] = pwelch(deltaModel,window,overlap,nfft,Fs);
PdeltaModel = mean(PdeltaModelEach,2);

%% 4. AUTOCORRELATION: RESIDUAL VS ENSEMBLE-MEAN ARMA OUTPUT
maxLag = min(round(maxLagSec*Fs),N-1);
[Rresidual,lags] = xcorr(residual,maxLag,'coeff');
Rarma = zeros(size(Rresidual));
for k = 1:nRealizations
    Rarma = Rarma + xcorr(armaNoise(:,k),maxLag,'biased');
end
Rarma = Rarma/nRealizations;
Rarma = Rarma/Rarma(maxLag+1); % Normalize after ensemble averaging
lagSec = lags/Fs;

%% 5. ALLAN DEVIATION: RESIDUAL VS ENSEMBLE-MEAN ARMA OUTPUT
maxM = floor((N-2)/2);
m = unique(round(logspace(0,log10(maxM),35)));
m = m(m >= 1 & m < (N-1)/2);

[avarResidual,tauResidual] = allanvar(residual,m,Fs);
avarResidual = avarResidual(:);
tauResidual = tauResidual(:);
avarARMA = zeros(numel(m),1);
for k = 1:nRealizations
    avarARMA = avarARMA + reshape(allanvar(armaNoise(:,k),m,Fs),[],1);
end
adevResidual = sqrt(avarResidual);
adevARMA = sqrt(avarARMA/nRealizations); % Average variance, then sqrt

%% PLOTS
cTest = [0 0.4470 0.7410];
cModel = [0.4660 0.6740 0.1880];
cTone = [0.4940 0.1840 0.5560];

figure('Name','ARMA + Tone Model Correlation');
tiledlayout(3,2);

nexttile;
semilogy(f,Presidual,'Color',cTest,'LineWidth',2); hold on;
semilogy(f,Parma,'Color',cModel,'LineWidth',2);
grid on; xlim([0 Fs/2]);
xlabel('Frequency [Hz]'); ylabel('PSD [units^2/Hz]');
title('Residual vs ARMA PSD');
legend('Test Residual','500-Run Mean ARMA','Location','best');

nexttile;
semilogy(f,PtestFull,'Color',cTest,'LineWidth',2); hold on;
semilogy(f,PmodelFull,'Color',cModel,'LineWidth',2);
for j = 1:length(model.toneFreq)
    xline(model.toneFreq(j),'--','Color',cTone, ...
        'LineWidth',1.5,'HandleVisibility','off');
end
grid on; xlim([0 Fs/2]);
xlabel('Frequency [Hz]'); ylabel('PSD [units^2/Hz]');
title('Full Test vs ARMA + Tones PSD');
legend('Test Noise','500-Run Mean Model','Location','best');

nexttile;
semilogy(f,PdeltaTest,'Color',cTest,'LineWidth',2); hold on;
semilogy(f,PdeltaModel,'Color',cModel,'LineWidth',2);
grid on; xlim([0 Fs/2]);
xlabel('Frequency [Hz]'); ylabel('PSD [units^2/Hz]');
title('Differenced Test vs Differenced Model');
legend('Test Noise','500-Run Mean Model','Location','best');

nexttile;
plot(lagSec,Rresidual,'Color',cTest,'LineWidth',2); hold on;
plot(lagSec,Rarma,'Color',cModel,'LineWidth',2);
grid on;
xlabel('Lag [s]'); ylabel('Normalized Autocorrelation');
title('Residual vs ARMA Autocorrelation');
legend('Test Residual','500-Run Mean ARMA','Location','best');

nexttile;
loglog(tauResidual,adevResidual,'Color',cTest,'LineWidth',2); hold on;
loglog(tauResidual,adevARMA,'Color',cModel,'LineWidth',2);
grid on;
xlabel('Averaging Time, \tau [s]'); ylabel('Allan Deviation');
title('Residual vs ARMA Allan Deviation');
legend('Test Residual','500-Run Mean ARMA','Location','best');

nexttile;
nPlot = min(N,round(5*Fs));
plot(t(1:nPlot),testFull(1:nPlot),'Color',cTest,'LineWidth',1); hold on;
plot(t(1:nPlot),modelFull(1:nPlot,1),'Color',cModel,'LineWidth',1);
grid on;
xlabel('Time [s]'); ylabel('Noise');
title('Representative Complete Signals');
legend('Test Noise','Model Realization 1','Location','best');

%% NUMERICAL SUMMARY
residualRMS = sqrt(mean(residual.^2));
armaRMS = sqrt(mean(armaNoise(:).^2));
testFullRMS = sqrt(mean(testFull.^2));
modelFullRMS = sqrt(mean(modelFull(:).^2));
deltaTestRMS = sqrt(mean(deltaTest.^2));
deltaModelRMS = sqrt(mean(deltaModel(:).^2));

psdRMSE = sqrt(mean((10*log10(max(Parma,realmin)) - ...
    10*log10(max(Presidual,realmin))).^2));
fullPsdRMSE = sqrt(mean((10*log10(max(PmodelFull,realmin)) - ...
    10*log10(max(PtestFull,realmin))).^2));
deltaPsdRMSE = sqrt(mean((10*log10(max(PdeltaModel,realmin)) - ...
    10*log10(max(PdeltaTest,realmin))).^2));
acfRMSE = sqrt(mean((Rarma-Rresidual).^2));

valid = adevResidual > 0 & adevARMA > 0;
allanRMSE = sqrt(mean((20*log10(adevARMA(valid)) - ...
    20*log10(adevResidual(valid))).^2));

fprintf('\nGYRO ARMA MODEL CORRELATION - REGIME %d (%d REALIZATIONS)\n', ...
    regimeToUse,nRealizations)
fprintf('Residual RMS: test = %.6g, ARMA ensemble = %.6g, error = %.2f %%\n', ...
    residualRMS,armaRMS,100*(armaRMS-residualRMS)/residualRMS)
fprintf('Full RMS: test = %.6g, model ensemble = %.6g, error = %.2f %%\n', ...
    testFullRMS,modelFullRMS,100*(modelFullRMS-testFullRMS)/testFullRMS)
fprintf('Difference RMS: test = %.6g, model ensemble = %.6g, error = %.2f %%\n', ...
    deltaTestRMS,deltaModelRMS,100*(deltaModelRMS-deltaTestRMS)/deltaTestRMS)
fprintf('PSD RMSE: residual = %.3f dB, full = %.3f dB, difference = %.3f dB\n', ...
    psdRMSE,fullPsdRMSE,deltaPsdRMSE)
fprintf('ACF RMSE = %.5f, Allan RMSE = %.3f dB\n',acfRMSE,allanRMSE)

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

bandPowerErrorPct = 100*(modelBandPower-testBandPower)./testBandPower;
toneMetrics = table(model.toneFreq(:),testBandPower,modelBandPower, ...
    bandPowerErrorPct,'VariableNames', ...
    {'Frequency_Hz','TestPower','MeanModelPower','Error_pct'});

disp(toneMetrics)
