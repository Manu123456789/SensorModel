%% GYRO AR + TONE MODEL CORRELATION - ENSEMBLE AVERAGE
% Required sensorModel fields:
% Fs, residual, toneFreq, toneAmp, tonePhase, noiseA, noiseB

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

%% BUILD 500 INDEPENDENT AR + TONE REALIZATIONS
% Each matrix column is one independent realization. Using one seeded random
% stream is statistically correct and avoids repeatedly resetting the RNG.
% AMPLITUDE CHANGE 1: include MA memory; scalar noiseB still works for AR.
burnIn = max(10*(max(length(model.noiseA),length(model.noiseB))-1),round(5*Fs));
w = randn(N+burnIn,nRealizations);
arTemp = filter(model.noiseB,model.noiseA,w);
arNoise = arTemp(burnIn+1:end,:);
arNoise = arNoise - mean(arNoise,1);

modelFull = arNoise + toneModel;
modelFull = modelFull - mean(modelFull,1);

%% COMMON WELCH SETTINGS
segmentLength = min(maxWelchLength,N-1);
if segmentLength < 8
    error('Selected regime is too short for validation.')
end
window = hamming(segmentLength,'periodic');
overlap = floor(segmentLength/2);
nfft = max(256,2^nextpow2(segmentLength));

%% 1. RESIDUAL VS ENSEMBLE-MEAN AR STOCHASTIC PSD
[Presidual,f] = pwelch(residual,window,overlap,nfft,Fs);
[ParEach,~] = pwelch(arNoise,window,overlap,nfft,Fs);
Par = mean(ParEach,2); % Average power first, never dB

%% 2. FULL TEST VS ENSEMBLE-MEAN AR + TONES PSD
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

%% 4. AUTOCORRELATION: RESIDUAL VS ENSEMBLE-MEAN AR OUTPUT
maxLag = min(round(maxLagSec*Fs),N-1);
[Rresidual,lags] = xcorr(residual,maxLag,'coeff');
Rar = zeros(size(Rresidual));
for k = 1:nRealizations
    Rar = Rar + xcorr(arNoise(:,k),maxLag,'biased');
end
Rar = Rar/nRealizations;
Rar = Rar/Rar(maxLag+1); % Normalize after ensemble averaging
lagSec = lags/Fs;

%% 5. ALLAN DEVIATION: RESIDUAL VS ENSEMBLE-MEAN AR OUTPUT
maxM = floor((N-2)/2);
m = unique(round(logspace(0,log10(maxM),35)));
m = m(m >= 1 & m < (N-1)/2);

[avarResidual,tauResidual] = allanvar(residual,m,Fs);
avarResidual = avarResidual(:);
tauResidual = tauResidual(:);
avarAR = zeros(numel(m),1);
for k = 1:nRealizations
    avarAR = avarAR + reshape(allanvar(arNoise(:,k),m,Fs),[],1);
end
adevResidual = sqrt(avarResidual);
adevAR = sqrt(avarAR/nRealizations); % Average variance, then take square root

%% PLOTS
cTest = [0 0.4470 0.7410];
cModel = [0.4660 0.6740 0.1880];
cTone = [0.4940 0.1840 0.5560];

figure('Name','AR + Tone Model Correlation');
tiledlayout(3,2);

nexttile;
semilogy(f,Presidual,'Color',cTest,'LineWidth',2); hold on;
semilogy(f,Par,'Color',cModel,'LineWidth',2);
grid on; xlim([0 Fs/2]);
xlabel('Frequency [Hz]'); ylabel('PSD [units^2/Hz]');
title('Residual vs AR PSD');
legend('Test Residual','500-Run Mean AR','Location','best');

nexttile;
semilogy(f,PtestFull,'Color',cTest,'LineWidth',2); hold on;
semilogy(f,PmodelFull,'Color',cModel,'LineWidth',2);
for j = 1:length(model.toneFreq)
    xline(model.toneFreq(j),'--','Color',cTone, ...
        'LineWidth',1.5,'HandleVisibility','off');
end
grid on; xlim([0 Fs/2]);
xlabel('Frequency [Hz]'); ylabel('PSD [units^2/Hz]');
title('Full Test vs AR + Tones PSD');
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
plot(lagSec,Rar,'Color',cModel,'LineWidth',2);
grid on;
xlabel('Lag [s]'); ylabel('Normalized Autocorrelation');
title('Residual vs AR Autocorrelation');
legend('Test Residual','500-Run Mean AR','Location','best');

nexttile;
loglog(tauResidual,adevResidual,'Color',cTest,'LineWidth',2); hold on;
loglog(tauResidual,adevAR,'Color',cModel,'LineWidth',2);
grid on;
xlabel('Averaging Time, \tau [s]'); ylabel('Allan Deviation');
title('Residual vs AR Allan Deviation');
legend('Test Residual','500-Run Mean AR','Location','best');

nexttile;
nPlot = min(N,round(5*Fs));
plot(t(1:nPlot),testFull(1:nPlot),'Color',cTest,'LineWidth',1); hold on;
plot(t(1:nPlot),modelFull(1:nPlot,1),'Color',cModel,'LineWidth',1);
grid on;
xlabel('Time [s]'); ylabel('Noise');
title('Representative Complete Signals');
legend('Test Noise','Model Realization 1','Location','best');

%% NUMERICAL SUMMARY
% Model RMS values use all samples from all realizations: average power,
% then square root. This is the ensemble RMS, not an average of percentages.
residualRMS = sqrt(mean(residual.^2));
arRMS = sqrt(mean(arNoise(:).^2));
testFullRMS = sqrt(mean(testFull.^2));
modelFullRMS = sqrt(mean(modelFull(:).^2));
deltaTestRMS = sqrt(mean(deltaTest.^2));
deltaModelRMS = sqrt(mean(deltaModel(:).^2));

psdRMSE = sqrt(mean((10*log10(max(Par,realmin)) - ...
    10*log10(max(Presidual,realmin))).^2));
fullPsdRMSE = sqrt(mean((10*log10(max(PmodelFull,realmin)) - ...
    10*log10(max(PtestFull,realmin))).^2));
deltaPsdRMSE = sqrt(mean((10*log10(max(PdeltaModel,realmin)) - ...
    10*log10(max(PdeltaTest,realmin))).^2));
acfRMSE = sqrt(mean((Rar-Rresidual).^2));

valid = adevResidual > 0 & adevAR > 0;
allanRMSE = sqrt(mean((20*log10(adevAR(valid)) - ...
    20*log10(adevResidual(valid))).^2));

fprintf('\nGYRO MODEL CORRELATION - REGIME %d (%d REALIZATIONS)\n', ...
    regimeToUse,nRealizations)
fprintf('Residual RMS: test = %.6g, AR ensemble = %.6g, error = %.2f %%\n', ...
    residualRMS,arRMS,100*(arRMS-residualRMS)/residualRMS)
fprintf('Full RMS: test = %.6g, model ensemble = %.6g, error = %.2f %%\n', ...
    testFullRMS,modelFullRMS,100*(modelFullRMS-testFullRMS)/testFullRMS)
fprintf('Difference RMS: test = %.6g, model ensemble = %.6g, error = %.2f %%\n', ...
    deltaTestRMS,deltaModelRMS,100*(deltaModelRMS-deltaTestRMS)/deltaTestRMS)
fprintf('PSD RMSE: residual = %.3f dB, full = %.3f dB, difference = %.3f dB\n', ...
    psdRMSE,fullPsdRMSE,deltaPsdRMSE)
fprintf('ACF RMSE = %.5f, Allan RMSE = %.3f dB\n',acfRMSE,allanRMSE)

%% TONE-BAND POWER ERRORS
% Error is calculated after averaging the 500 PSDs in linear power units.
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

%% AMPLITUDE CHANGE 2: TEST RESIDUAL VS AR / ARMA AMPLITUDE DISTRIBUTIONS
% Append this section after disp(toneMetrics).
% Uses existing residual, arNoise, residualRMS, arRMS, cTest, and cModel.
% Pool samples across realizations; do NOT average the time histories.
% With equal-length records and common bins, pooling is equivalent to
% averaging their PDF histograms. No additional noise is generated here.
% The standardized view changes plotting copies only, not the model gain.

ampBins = 60; % Fewer bins give a smoother estimate from the single test record.
figure('Name','Residual Amplitude Distributions - AR / ARMA');
tiledlayout(1,2);

for ampView = 1:2
    nexttile;
    if ampView == 1
        ampTest = residual(:);
        ampModel = arNoise(:);
        ampLabel = 'Residual amplitude [sensor units]';
        ampTitle = 'Original amplitude: scale + shape';
    else
        if ~isfinite(residualRMS) || ~isfinite(arRMS) || ...
                residualRMS <= 0 || arRMS <= 0
            axis off;
            text(0.5,0.5,'Shape comparison requires positive, finite RMS.', ...
                'Units','normalized','HorizontalAlignment','center');
            continue;
        end
        ampTest = residual(:)/residualRMS;
        ampModel = arNoise(:)/arRMS;
        ampLabel = 'Residual amplitude / own RMS';
        ampTitle = 'Unit RMS: distribution shape';
    end

    % Use identical bin edges for test and model; include all sample values.
    ampLimit = max([max(abs(ampTest)),max(abs(ampModel))]);
    if ampLimit == 0
        ampLimit = 1; % Keep histogram edges valid for an all-zero signal.
    end
    ampEdges = linspace(-ampLimit,ampLimit,ampBins+1);

    histogram(ampTest,ampEdges,'Normalization','pdf', ...
        'DisplayStyle','stairs','EdgeColor',cTest,'LineWidth',2);
    hold on;
    histogram(ampModel,ampEdges,'Normalization','pdf', ...
        'DisplayStyle','stairs','EdgeColor',cModel,'LineWidth',2);
    grid on; xlim([-ampLimit ampLimit]);
    xlabel(ampLabel); ylabel('Probability density');
    title(ampTitle);
    legend('Test residual',sprintf('Model: %d realizations pooled', ...
        nRealizations),'Location','best');
end
% END AMPLITUDE CHANGE 2

%% PSD ADDITION: POINTWISE PERCENTILE BAND ACROSS REALIZATIONS
% Paste this entire section at the bottom of the correlation script.
% Uses existing f, Presidual, ParEach, Par, Fs, cTest, and cModel.
% All columns of ParEach are used; choose nRealizations in SETTINGS.
% The band describes variation between individual realization PSDs.
% It is NOT uncertainty in the mean or a simultaneous bound over frequency.
% No new noise is generated. This works for AR and ARMA models.

psdPercentiles = [2.5 97.5]; % Central 95% range; use [5 95] for 90%.

% Each row is one frequency; dimension 2 runs across realizations.
% Calculate percentiles in linear power units, before logarithmic plotting.
psdBand = prctile(ParEach,psdPercentiles,2);

figure('Name','Residual PSD - Pointwise Realization Band');
fill([f(:); flipud(f(:))], ...
    [max(psdBand(:,1),realmin); flipud(max(psdBand(:,2),realmin))], ...
    [0.8 0.8 0.8],'EdgeColor','none','FaceAlpha',0.5);
hold on;
plot(f,max(Presidual,realmin),'Color',cTest,'LineWidth',2);
plot(f,max(Par,realmin),'Color',cModel,'LineWidth',2);
set(gca,'YScale','log'); % Apply log scale to both the band and curves.
grid on; xlim([0 Fs/2]);
xlabel('Frequency [Hz]'); ylabel('PSD [units^2/Hz]');
title('Residual vs AR / ARMA PSD: Variation Between Realizations');
legend(sprintf('Pointwise %g-%g percentile band', ...
    psdPercentiles(1),psdPercentiles(2)), ...
    'Test residual', ...
    sprintf('Model ensemble mean (%d runs)',size(ParEach,2)), ...
    'Location','best');
hold off;
% END PSD ADDITION
